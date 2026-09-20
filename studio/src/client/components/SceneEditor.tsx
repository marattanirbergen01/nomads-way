import { useEffect, useState } from 'react';
import { api, Conflict } from '../api';
import { can, useMe } from '../App';
import type { Beat, Episode, Media, PresenceEntry, Scene, SceneStatus } from '../types';
import { SCENE_STATUS_TITLES } from '../types';
import { toast, toastError } from './Toast';
import { BeatCard } from './BeatCard';
import { ChoiceCard } from './ChoiceCard';
import type { Target } from '../pages/Episode';

interface Props {
  ep: Episode;
  scene: Scene;
  media: Media[];
  presence: PresenceEntry[];
  target: Target | null;
  onTarget: (t: Target) => void;
  onEditing: (key: string | null) => void;
}

export function SceneEditor({ ep, scene, media, presence, target, onTarget, onEditing }: Props) {
  const me = useMe();
  const editable = can(me, 'scene.edit');

  // --- шапка сцены: id, названия, слой ---
  const [head, setHead] = useState({ scene_id: scene.scene_id, title_kk: scene.title_kk ?? '', title_ru: scene.title_ru ?? '', layer: scene.layer ?? '' });
  const [headDirty, setHeadDirty] = useState(false);
  useEffect(() => {
    if (!headDirty) setHead({ scene_id: scene.scene_id, title_kk: scene.title_kk ?? '', title_ru: scene.title_ru ?? '', layer: scene.layer ?? '' });
  }, [scene.version]);

  const saveHead = async () => {
    if (!headDirty) return;
    const patch: any = {};
    if (head.scene_id !== scene.scene_id) patch.scene_id = head.scene_id;
    if (head.title_kk !== (scene.title_kk ?? '')) patch.title_kk = head.title_kk || null;
    if (head.title_ru !== (scene.title_ru ?? '')) patch.title_ru = head.title_ru || null;
    if (head.layer !== (scene.layer ?? '')) patch.layer = head.layer || null;
    setHeadDirty(false);
    if (!Object.keys(patch).length) return;
    try {
      await api.patch(`/scenes/${scene.id}`, { ...patch, version: scene.version });
      if (patch.scene_id) location.hash = `#/episode/${ep.id}/${patch.scene_id}`;
    } catch (e) {
      if (e instanceof Conflict) toast('Сцену только что изменил другой участник — поля обновлены', 'err');
      else toastError(e);
    }
  };

  const setStatus = async (status: SceneStatus) => {
    try {
      await api.patch(`/scenes/${scene.id}`, { status });
      toast('Статус: ' + SCENE_STATUS_TITLES[status]);
    } catch (e) {
      toastError(e);
    }
  };

  const addBeat = async (kind: 'say' | 'choice', after: Beat | null) => {
    try {
      const prevSay = after?.kind === 'say' ? after : null;
      const who = kind === 'say' ? guessNextWho(scene, prevSay, ep) : undefined;
      await api.post(`/scenes/${scene.id}/beats`, { kind, after: after?.id ?? null, who });
    } catch (e) {
      toastError(e);
    }
  };
  const moveBeat = async (b: Beat, dir: -1 | 1) => {
    const ids = scene.beats.map((x) => x.id);
    const i = ids.indexOf(b.id);
    const k = i + dir;
    if (k < 0 || k >= ids.length) return;
    [ids[i], ids[k]] = [ids[k], ids[i]];
    try {
      await api.post(`/scenes/${scene.id}/beats/reorder`, { ids });
    } catch (e) {
      toastError(e);
    }
  };
  const deleteBeat = async (b: Beat) => {
    if (!confirm('Удалить реплику?')) return;
    try {
      await api.del(`/beats/${b.id}`);
    } catch (e) {
      toastError(e);
    }
  };
  const deleteScene = async () => {
    if (!confirm(`Удалить сцену ${scene.scene_id} со всеми репликами?`)) return;
    try {
      await api.del(`/scenes/${scene.id}`);
      location.hash = `#/episode/${ep.id}`;
    } catch (e) {
      toastError(e);
    }
  };

  const statusOptions = (Object.keys(SCENE_STATUS_TITLES) as SceneStatus[]).filter((s) => {
    if (s === 'text_ok') return can(me, 'history.approve');
    return can(me, 'scene.status');
  });
  const sceneSelected = target?.type === 'scene' && target.id === String(scene.id);
  const editors = presence.filter((p) => p.sceneId === scene.id && p.editing);

  return (
    <div className="scene-editor">
      <div className={'scene-head card' + (sceneSelected ? ' selected' : '')} onClick={() => onTarget({ type: 'scene', id: String(scene.id), title: `Сцена ${scene.scene_id}` })}>
        <div className="row">
          <input
            className="code-input"
            value={head.scene_id}
            disabled={!editable}
            onChange={(e) => {
              setHead({ ...head, scene_id: e.target.value });
              setHeadDirty(true);
            }}
            onBlur={saveHead}
          />
          <select
            value={head.layer}
            disabled={!editable}
            onChange={(e) => {
              setHead({ ...head, layer: e.target.value });
              setHeadDirty(true);
            }}
            onBlur={saveHead}
            title="Слой: история — факты и вопросы; личная — жизнь аватара, без вопросов"
          >
            <option value="">слой не задан</option>
            <option value="history">история</option>
            <option value="personal">личная</option>
          </select>
          <div className="spacer" />
          {statusOptions.length > 0 ? (
            <select value={scene.status} onChange={(e) => setStatus(e.target.value as SceneStatus)} className={'status-select st-' + scene.status}>
              {(Object.keys(SCENE_STATUS_TITLES) as SceneStatus[]).map((s) => (
                <option key={s} value={s} disabled={!statusOptions.includes(s) && s !== scene.status}>
                  {SCENE_STATUS_TITLES[s]}
                </option>
              ))}
            </select>
          ) : (
            <span className={'badge st-' + scene.status}>{SCENE_STATUS_TITLES[scene.status]}</span>
          )}
          {editable && (
            <button className="link danger small" onClick={deleteScene} title="Удалить сцену">
              удалить
            </button>
          )}
        </div>
        <div className="row titles">
          <input
            placeholder="Название сцены (kk) — необязательно"
            value={head.title_kk}
            disabled={!editable}
            onChange={(e) => {
              setHead({ ...head, title_kk: e.target.value });
              setHeadDirty(true);
            }}
            onBlur={saveHead}
          />
          <input
            placeholder="Название сцены (ru)"
            value={head.title_ru}
            disabled={!editable}
            onChange={(e) => {
              setHead({ ...head, title_ru: e.target.value });
              setHeadDirty(true);
            }}
            onBlur={saveHead}
          />
        </div>
        <div className="row small muted">
          <span>
            кадр: {scene.art ? <span className="code">{scene.art}</span> : <span className="warn">не задан</span>}
          </span>
          <span>факты: {scene.covers.length ? scene.covers.join(', ') : '—'}</span>
          <span>вопросов: {scene.quiz.length}</span>
          {editors.length > 0 && <span className="pill">{editors.map((p) => p.name).join(', ')} — правит</span>}
        </div>
      </div>

      <div className="beats">
        {scene.beats.length === 0 && editable && (
          <div className="add-between">
            <button className="link" onClick={() => addBeat('say', null)}>
              + реплика
            </button>
            <button className="link" onClick={() => addBeat('choice', null)}>
              + развилка
            </button>
          </div>
        )}
        {scene.beats.map((b, i) => (
          <div key={b.id}>
            {b.kind === 'say' ? (
              <BeatCard
                ep={ep}
                scene={scene}
                beat={b}
                media={media}
                editable={editable}
                selected={target?.type === 'beat' && target.id === String(b.id)}
                commentCount={ep.commentCounts['beat:' + b.id] ?? 0}
                onSelect={() => onTarget({ type: 'beat', id: String(b.id), title: `Реплика ${i + 1} · ${scene.scene_id}` })}
                onEditing={(v) => onEditing(v ? 'beat:' + b.id : null)}
                onMove={(d) => moveBeat(b, d)}
                onDelete={() => deleteBeat(b)}
                first={i === 0}
                last={i === scene.beats.length - 1}
                editingBy={presence.find((p) => p.editing === 'beat:' + b.id)?.name}
              />
            ) : (
              <ChoiceCard
                ep={ep}
                scene={scene}
                beat={b}
                media={media}
                editable={editable}
                selected={target?.type === 'beat' && target.id === String(b.id)}
                commentCount={ep.commentCounts['beat:' + b.id] ?? 0}
                onSelect={() => onTarget({ type: 'beat', id: String(b.id), title: `Развилка · ${scene.scene_id}` })}
                onEditing={(v) => onEditing(v ? 'beat:' + b.id : null)}
                onMove={(d) => moveBeat(b, d)}
                onDelete={() => deleteBeat(b)}
                first={i === 0}
                last={i === scene.beats.length - 1}
                editingBy={presence.find((p) => p.editing === 'beat:' + b.id)?.name}
              />
            )}
            {editable && (
              <div className="add-between">
                <button className="link" onClick={() => addBeat('say', b)}>
                  + реплика
                </button>
                <button className="link" onClick={() => addBeat('choice', b)}>
                  + развилка
                </button>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// Кто говорит следующим: чередуем аватара и последнего не-аватара, иначе рассказчик.
function guessNextWho(scene: Scene, prev: Beat | null, ep: Episode) {
  const avatar = ep.characters.find((c) => c.avatar)?.char_id;
  if (!prev) return scene.beats.length ? undefined : 'narrator';
  if (prev.who === avatar) {
    const other = [...scene.beats].reverse().find((b) => b.kind === 'say' && b.who && b.who !== avatar && b.who !== 'narrator');
    return other?.who ?? 'narrator';
  }
  return avatar ?? 'narrator';
}
