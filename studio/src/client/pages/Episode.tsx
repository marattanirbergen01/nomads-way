import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../api';
import { setPresence, useLive } from '../live';
import { can, useMe } from '../App';
import {
  EPISODE_STATUS_TITLES, SCENE_STATUS_TITLES, type Episode, type Media, type PresenceEntry, type Scene,
} from '../types';
import { toast, toastError } from '../components/Toast';
import { SceneEditor } from '../components/SceneEditor';
import { SidePanel } from '../components/SidePanel';
import { CharactersDialog } from '../components/CharactersDialog';
import { QuestionsDialog } from '../components/QuestionsDialog';
import { EpisodeSettingsDialog } from '../components/EpisodeSettingsDialog';
import { BuildDialog } from '../components/BuildDialog';

export type Target = { type: 'episode' | 'scene' | 'beat' | 'question'; id: string; title: string };

export function EpisodePage({ id, sceneKey }: { id: string; sceneKey?: string }) {
  const me = useMe();
  const [ep, setEp] = useState<Episode | null>(null);
  const [media, setMedia] = useState<Media[]>([]);
  const [presence, setPresenceList] = useState<PresenceEntry[]>([]);
  const [target, setTarget] = useState<Target | null>(null);
  const [dialog, setDialog] = useState<'characters' | 'questions' | 'settings' | 'build' | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [error, setError] = useState('');

  const load = useCallback(() => api.get<Episode>(`/episodes/${id}`).then(setEp).catch((e) => setError(e.message)), [id]);
  const loadMedia = useCallback(
    (season: string) => api.get<Media[]>(`/media/${season}`).then(setMedia).catch(toastError),
    [],
  );
  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    if (ep) loadMedia(ep.season_id);
  }, [ep?.season_id]);

  // live-обновления: перечитываем серию целиком — она маленькая, а логика простая и надёжная
  const reloadTimer = useRef<number | undefined>();
  useLive(
    (ev) => {
      if ((ev.type === 'episode.changed' || ev.type === 'comment') && ev.episodeId === id) {
        clearTimeout(reloadTimer.current);
        reloadTimer.current = window.setTimeout(load, 150);
      }
      if (ev.type === 'media.changed' && ep && ev.seasonId === ep.season_id) loadMedia(ep.season_id);
      if (ev.type === 'presence' && ev.episodeId === id) setPresenceList(ev.users);
    },
    [id, ep?.season_id],
  );

  // выбранная сцена — из адреса (#/episode/s1e01/sc010) или первая
  const scene: Scene | undefined = useMemo(() => {
    if (!ep) return undefined;
    return ep.scenes.find((s) => s.scene_id === sceneKey) ?? ep.scenes[0];
  }, [ep, sceneKey]);

  useEffect(() => {
    setPresence({ episodeId: id, sceneId: scene?.id ?? null, editing });
  }, [id, scene?.id, editing]);
  useEffect(() => () => setPresence({ episodeId: null }), []);

  // при смене сцены сбрасываем цель комментариев на сцену
  useEffect(() => {
    if (scene) setTarget({ type: 'scene', id: String(scene.id), title: `Сцена ${scene.scene_id}` });
  }, [scene?.id]);

  if (error) return <div className="page error">{error}</div>;
  if (!ep) return <div className="page muted">Загрузка…</div>;

  const selectScene = (s: Scene) => {
    location.hash = `#/episode/${ep.id}/${s.scene_id}`;
  };

  const addScene = async (after: Scene | null) => {
    const suggested = nextSceneId(ep.scenes, after);
    const scene_id = prompt('id новой сцены', suggested);
    if (!scene_id) return;
    try {
      await api.post(`/episodes/${ep.id}/scenes`, { scene_id, after: after?.id ?? null });
      location.hash = `#/episode/${ep.id}/${scene_id}`;
    } catch (e) {
      toastError(e);
    }
  };

  const moveScene = async (s: Scene, dir: -1 | 1) => {
    const ids = ep.scenes.map((x) => x.id);
    const i = ids.indexOf(s.id);
    const k = i + dir;
    if (k < 0 || k >= ids.length) return;
    [ids[i], ids[k]] = [ids[k], ids[i]];
    try {
      await api.post(`/episodes/${ep.id}/scenes/reorder`, { ids });
    } catch (e) {
      toastError(e);
    }
  };

  const setEpisodeStatus = async (status: string) => {
    try {
      await api.patch(`/episodes/${ep.id}`, { status });
      toast('Статус серии: ' + EPISODE_STATUS_TITLES[status as keyof typeof EPISODE_STATUS_TITLES]);
    } catch (e) {
      toastError(e);
    }
  };

  const others = presence.filter((p) => p.userId !== me.id);

  return (
    <div className="episode-layout">
      <aside className="scene-list">
        <div className="ep-head">
          <a href="#/" className="muted small">
            ← Серии
          </a>
          <h2>
            {ep.title_ru || ep.id} <span className="muted">· {ep.title_kk}</span>
          </h2>
          <div className="row small">
            <span className="code">{ep.id}</span>
            <span className={'badge st-' + ep.status}>{EPISODE_STATUS_TITLES[ep.status]}</span>
            {ep.approved_by && <span className="pill ok">виза: {ep.approved_by}</span>}
          </div>
          <div className="row small tools">
            <button className="link" onClick={() => setDialog('characters')}>
              Персонажи ({ep.characters.length})
            </button>
            <button className="link" onClick={() => setDialog('questions')}>
              Вопросы ({ep.questions.length})
            </button>
            <button className="link" onClick={() => setDialog('settings')}>
              Серия…
            </button>
            <button className="link" onClick={() => setDialog('build')}>
              Сборка{ep.revision > 0 ? ` (ред. ${ep.revision})` : ''}
            </button>
          </div>
          {others.length > 0 && (
            <div className="presence">
              {others.map((p) => (
                <span key={p.userId} className="avatar-chip" title={`${p.name}${p.editing ? ' — редактирует' : ''}`}>
                  {initials(p.name)}
                </span>
              ))}
              <span className="muted small">
                {others.length === 1 ? 'сейчас тут' : 'сейчас тут'}: {others.map((p) => p.name).join(', ')}
              </span>
            </div>
          )}
        </div>
        <ol>
          {ep.scenes.map((s, i) => {
            const here = others.filter((p) => p.sceneId === s.id);
            const cc = ep.commentCounts['scene:' + s.id] ?? 0;
            const beatComments = s.beats.reduce((n, b) => n + (ep.commentCounts['beat:' + b.id] ?? 0), 0);
            const agentPending = s.beats.some((b) => b.needs_review);
            return (
              <li key={s.id} className={scene?.id === s.id ? 'active' : ''} onClick={() => selectScene(s)}>
                <div className="row">
                  <span className="code">{s.scene_id}</span>
                  <span className={'dot-status ' + s.status} title={SCENE_STATUS_TITLES[s.status]} />
                </div>
                <div className="scene-title">{s.title_ru || firstLine(s) || <span className="muted">пустая сцена</span>}</div>
                <div className="row small muted">
                  <span>
                    {s.layer === 'personal' ? 'личная' : s.layer === 'history' ? 'история' : '—'} · {s.beats.length} репл.
                  </span>
                  {cc + beatComments > 0 && <span className="pill">💬 {cc + beatComments}</span>}
                  {agentPending && <span className="pill agent">агент</span>}
                  {here.map((p) => (
                    <span key={p.userId} className="avatar-chip tiny" title={p.name}>
                      {initials(p.name)}
                    </span>
                  ))}
                </div>
                {can(me, 'scene.edit') && scene?.id === s.id && (
                  <div className="row small scene-tools" onClick={(e) => e.stopPropagation()}>
                    <button className="link" disabled={i === 0} onClick={() => moveScene(s, -1)}>
                      ↑
                    </button>
                    <button className="link" disabled={i === ep.scenes.length - 1} onClick={() => moveScene(s, 1)}>
                      ↓
                    </button>
                    <button className="link" onClick={() => addScene(s)}>
                      + сцена после
                    </button>
                  </div>
                )}
              </li>
            );
          })}
        </ol>
        {can(me, 'scene.edit') && (
          <button className="link" style={{ margin: 12 }} onClick={() => addScene(null)}>
            + сцена в конец
          </button>
        )}
        {can(me, 'episode.manage') && (
          <div className="ep-status-tools small">
            <span className="muted">Статус серии:</span>
            <select value={ep.status} onChange={(e) => setEpisodeStatus(e.target.value)}>
              {Object.entries(EPISODE_STATUS_TITLES).map(([k, v]) => (
                <option key={k} value={k} disabled={k === 'published'}>
                  {v}
                </option>
              ))}
            </select>
          </div>
        )}
      </aside>

      <main className="scene-main">
        {scene ? (
          <SceneEditor
            key={scene.id}
            ep={ep}
            scene={scene}
            media={media}
            presence={others}
            onTarget={setTarget}
            target={target}
            onEditing={setEditing}
          />
        ) : (
          <div className="muted" style={{ padding: 40 }}>
            В серии пока нет сцен.
          </div>
        )}
      </main>

      <SidePanel ep={ep} scene={scene} media={media} target={target} onTarget={setTarget} />

      {dialog === 'characters' && <CharactersDialog ep={ep} media={media} onClose={() => setDialog(null)} />}
      {dialog === 'questions' && <QuestionsDialog ep={ep} onClose={() => setDialog(null)} onTarget={setTarget} />}
      {dialog === 'settings' && <EpisodeSettingsDialog ep={ep} onClose={() => setDialog(null)} />}
      {dialog === 'build' && <BuildDialog ep={ep} onClose={() => setDialog(null)} />}
    </div>
  );
}

export function initials(name: string) {
  return name
    .split(/\s+/)
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

function firstLine(s: Scene) {
  const b = s.beats.find((b) => b.kind === 'say' && (b.ru || b.kk));
  const t = b ? b.ru || b.kk : '';
  return t.length > 60 ? t.slice(0, 60) + '…' : t;
}

// sc010, sc012 … предлагаем следующий свободный номер между соседями
function nextSceneId(scenes: Scene[], after: Scene | null) {
  const nums = scenes.map((s) => Number(s.scene_id.replace(/\D/g, '')) || 0);
  if (!after) {
    const max = Math.max(0, ...nums);
    return 'sc' + String(Math.ceil((max + 1) / 10) * 10).padStart(3, '0');
  }
  const i = scenes.findIndex((s) => s.id === after.id);
  const a = nums[i];
  const b = i + 1 < nums.length ? nums[i + 1] : a + 10;
  const mid = a + 1 < b ? Math.floor((a + b) / 2) : a + 1;
  return 'sc' + String(mid).padStart(3, '0');
}
