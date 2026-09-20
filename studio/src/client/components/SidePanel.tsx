import { useEffect, useState } from 'react';
import { api, mediaUrl } from '../api';
import { can, useMe } from '../App';
import type { Beat, Episode, Media, Scene } from '../types';
import { EMOTION_TITLES } from '../types';
import type { Target } from '../pages/Episode';
import { Comments } from './Comments';
import { toast, toastError } from './Toast';
import { avatarIdsFor } from './BeatCard';
import { useLive } from '../live';

type Tab = 'preview' | 'comments' | 'scene' | 'history';

export function SidePanel({ ep, scene, media, target, onTarget }: { ep: Episode; scene?: Scene; media: Media[]; target: Target | null; onTarget: (t: Target) => void }) {
  const [tab, setTab] = useState<Tab>('preview');
  // при клике на реплику/сцену с комментариями — переключаемся на комментарии
  useEffect(() => {
    if (target && (ep.commentCounts[`${target.type}:${target.id}`] ?? 0) > 0) setTab('comments');
  }, [target?.type, target?.id]);

  const openTotal = Object.values(ep.commentCounts).reduce((a, b) => a + b, 0);
  return (
    <aside className="side-panel">
      <div className="tabs">
        <button className={tab === 'preview' ? 'active' : ''} onClick={() => setTab('preview')}>Превью</button>
        <button className={tab === 'comments' ? 'active' : ''} onClick={() => setTab('comments')}>
          Комментарии {openTotal > 0 && <span className="pill">{openTotal}</span>}
        </button>
        <button className={tab === 'scene' ? 'active' : ''} onClick={() => setTab('scene')}>Кадр и факты</button>
        <button className={tab === 'history' ? 'active' : ''} onClick={() => setTab('history')}>История</button>
      </div>
      <div className="tab-body">
        {tab === 'preview' && scene && <Preview ep={ep} scene={scene} media={media} target={target} />}
        {tab === 'comments' && <Comments ep={ep} target={target ?? { type: 'episode', id: ep.id, title: 'Серия' }} onTarget={onTarget} />}
        {tab === 'scene' && scene && <SceneSettings ep={ep} scene={scene} media={media} />}
        {tab === 'history' && <Activity ep={ep} />}
      </div>
    </aside>
  );
}

// ---------------------------------------------------------------- превью 9:16
function Preview({ ep, scene, media, target }: { ep: Episode; scene: Scene; media: Media[]; target: Target | null }) {
  const looks = avatarIdsFor(media);
  const [look, setLook] = useState(looks[0]);
  useEffect(() => {
    if (!look && looks[0]) setLook(looks[0]);
  }, [looks.join()]);
  const says = scene.beats.filter((b) => b.kind === 'say');
  const targetBeat = target?.type === 'beat' ? scene.beats.find((b) => String(b.id) === target.id) : undefined;
  const [idx, setIdx] = useState(0);
  useEffect(() => {
    if (targetBeat && targetBeat.kind === 'say') setIdx(says.findIndex((b) => b.id === targetBeat.id));
  }, [targetBeat?.id]);
  const beat: Beat | undefined = says[Math.min(idx, says.length - 1)];
  const ch = beat ? ep.characters.find((c) => c.char_id === beat.who) : undefined;
  const isAvatar = !!ch?.avatar;
  const artOk = scene.art && media.some((m) => m.id === scene.art && m.hasFile);
  const emotion = beat?.emotion ?? 'calm';
  const bust = look ? `${look}_${emotion}_bust` : null;
  const showBust = isAvatar && !scene.avatar_in_art && bust;
  const portrait = ch?.portrait ?? (isAvatar && look ? `${look}_${emotion}` : ch ? `char_${ch.char_id}` : null);
  const [lang, setLang] = useState<'kk' | 'ru'>('ru');

  return (
    <div className="preview">
      <div className="row small">
        <select value={look} onChange={(e) => setLook(e.target.value)}>
          {looks.map((l) => (
            <option key={l} value={l}>{l.replace(/^avatar_\d+_/, '')}</option>
          ))}
        </select>
        <button className={'link' + (lang === 'kk' ? ' active' : '')} onClick={() => setLang('kk')}>kk</button>
        <button className={'link' + (lang === 'ru' ? ' active' : '')} onClick={() => setLang('ru')}>ru</button>
        <div className="spacer" />
        <button className="link" disabled={idx <= 0} onClick={() => setIdx(idx - 1)}>‹</button>
        <span className="muted">{says.length ? `${Math.min(idx, says.length - 1) + 1} / ${says.length}` : '—'}</span>
        <button className="link" disabled={idx >= says.length - 1} onClick={() => setIdx(idx + 1)}>›</button>
      </div>
      <div className="phone">
        {artOk ? <img className="art" src={mediaUrl(ep.season_id, scene.art!)} alt="" style={{ objectPosition: `${scene.pan ?? 50}% 50%` }} /> : <div className="art missing">нет кадра</div>}
        <div className="ornament" />
        {showBust && <img className={'bust ' + (scene.avatar_side ?? 'left')} src={mediaUrl(ep.season_id, bust!)} alt="" />}
        <div className="panel">
          {beat && (
            <>
              <div className="speaker">
                {portrait && media.some((m) => m.id === portrait && m.hasFile) && <img src={mediaUrl(ep.season_id, portrait)} alt="" />}
                <span>{ch ? (lang === 'kk' ? ch.name_kk : ch.name_ru) : beat.who}</span>
                {isAvatar && <em className="muted">· {EMOTION_TITLES[emotion]}</em>}
              </div>
              <div className="text" lang={lang}>{beat[lang] || <span className="muted">(пусто)</span>}</div>
            </>
          )}
          {!beat && <div className="muted">нет реплик</div>}
        </div>
      </div>
      <div className="muted small">Так игрок увидит реплику: кадр сцены, бюст аватара с эмоцией, панель текста. Точная вёрстка — во Flutter.</div>
    </div>
  );
}

// ---------------------------------------------------------------- кадр, факты, вопросы
function SceneSettings({ ep, scene, media }: { ep: Episode; scene: Scene; media: Media[] }) {
  const me = useMe();
  const arts = media.filter((m) => m.kind === 'scene' || m.kind === 'map');
  const [covers, setCovers] = useState(scene.covers.join(', '));
  const [quiz, setQuiz] = useState(scene.quiz.join(', '));
  const [note, setNote] = useState(scene.note ?? '');
  const [artWhen, setArtWhen] = useState(JSON.stringify(scene.art_when ?? []));
  useEffect(() => {
    setCovers(scene.covers.join(', '));
    setQuiz(scene.quiz.join(', '));
    setNote(scene.note ?? '');
    setArtWhen(JSON.stringify(scene.art_when ?? []));
  }, [scene.version]);

  const patch = async (p: Record<string, any>) => {
    try {
      await api.patch(`/scenes/${scene.id}`, p);
    } catch (e) {
      toastError(e);
    }
  };
  const list = (s: string) => s.split(/[,\s]+/).map((x) => x.trim()).filter(Boolean);
  const mediaOk = can(me, 'media.edit');
  const factsOk = can(me, 'facts.edit');
  const textOk = can(me, 'scene.edit');
  const art = media.find((m) => m.id === scene.art);

  return (
    <div className="scene-settings">
      <h4>Кадр сцены</h4>
      <select value={scene.art ?? ''} disabled={!mediaOk} onChange={(e) => patch({ art: e.target.value || null })}>
        <option value="">— не задан —</option>
        {arts.map((m) => (
          <option key={m.id} value={m.id}>{m.id} {m.status === 'approved' ? '✓' : m.hasFile ? '(черновик)' : '(нет файла)'}</option>
        ))}
      </select>
      {scene.art && (
        <div className="art-thumb">
          {art?.hasFile ? <img src={mediaUrl(ep.season_id, scene.art)} alt="" /> : <div className="missing">файла нет</div>}
          <div className="small muted">{art?.brief}</div>
          <a className="small" href={`#/media/${ep.season_id}`}>открыть в медиа →</a>
        </div>
      )}
      {mediaOk && (
        <button className="link small" onClick={() => {
          const id = prompt('id нового кадра', `art_${ep.id}_${scene.scene_id.replace(/^sc/, '')}`);
          if (!id) return;
          api.put(`/media/${ep.season_id}/${id}`, { kind: 'scene', brief: '' }).then(() => patch({ art: id })).then(() => toast('Кадр заведён: ' + id)).catch(toastError);
        }}>+ завести кадр для этой сцены</button>
      )}
      <label className="small">
        Панорама (pan 0–100, 50 = центр)
        <input type="number" min={0} max={100} defaultValue={scene.pan ?? ''} disabled={!mediaOk} onBlur={(e) => patch({ pan: e.target.value === '' ? null : Number(e.target.value) })} />
      </label>
      <label className="small">
        Кадр по условию (art_when, JSON)
        <input className="code-input" value={artWhen} disabled={!mediaOk} onChange={(e) => setArtWhen(e.target.value)} onBlur={() => {
          try {
            const v = JSON.parse(artWhen || '[]');
            patch({ art_when: Array.isArray(v) && v.length ? v : null });
          } catch {
            toast('art_when: неверный JSON', 'err');
          }
        }} />
      </label>

      <h4>Аватар</h4>
      <div className="row small">
        <label>
          <input type="checkbox" checked={!!scene.avatar_in_art} disabled={!textOk} onChange={(e) => patch({ avatar_in_art: e.target.checked })} /> аватар нарисован в кадре (бюст не показывать)
        </label>
      </div>
      <div className="row small">
        <span className="muted">сторона бюста:</span>
        <select value={scene.avatar_side ?? ''} disabled={!textOk} onChange={(e) => patch({ avatar_side: e.target.value || null })}>
          <option value="">слева (по умолчанию)</option>
          <option value="left">слева</option>
          <option value="right">справа</option>
        </select>
      </div>

      <h4>Факты, которые прозвучали (covers)</h4>
      <input className="code-input" value={covers} disabled={!factsOk} placeholder="f.4.1.a, f.4.1.b" onChange={(e) => setCovers(e.target.value)} onBlur={() => patch({ covers: list(covers) })} />
      <div className="muted small">Историк. Вопрос может спрашивать только то, что есть в covers этой или более ранней сцены.</div>

      <h4>Вопросы после сцены (quiz)</h4>
      <input className="code-input" value={quiz} disabled={!factsOk} placeholder="q_s1e01_001, q_s1e01_002" onChange={(e) => setQuiz(e.target.value)} onBlur={() => patch({ quiz: list(quiz) })} />
      <div className="small">
        {scene.quiz.map((q) => {
          const qq = ep.questions.find((x) => x.q_id === q);
          return (
            <div key={q} className={qq ? '' : 'warn'}>
              <span className="code">{q}</span> {qq ? <span className="muted">— {qq.data.stem?.ru}</span> : '— нет такого вопроса'}
            </div>
          );
        })}
      </div>

      <h4>Заметка сценариста</h4>
      <textarea value={note} disabled={!textOk} rows={3} onChange={(e) => setNote(e.target.value)} onBlur={() => patch({ note: note || null })} placeholder="Что важно помнить об этой сцене (пойдёт комментарием в YAML)" />
    </div>
  );
}

// ---------------------------------------------------------------- история
function Activity({ ep }: { ep: Episode }) {
  const [items, setItems] = useState<any[]>([]);
  const load = () => api.get(`/episodes/${ep.id}/activity`).then(setItems).catch(toastError);
  useEffect(() => {
    load();
  }, [ep.id]);
  useLive((ev) => {
    if ((ev.type === 'episode.changed' || ev.type === 'comment') && ev.episodeId === ep.id) load();
  }, [ep.id]);
  const label = (a: any) => {
    const d = a.detail ?? {};
    switch (a.action) {
      case 'beat.update': return `изменил реплику в ${d.scene} (${(d.fields ?? []).join(', ')})`;
      case 'beat.create': return `добавил реплику в ${d.scene}`;
      case 'beat.delete': return `удалил реплику в ${d.scene}: «${(d.text ?? '').slice(0, 40)}»`;
      case 'beat.reorder': return 'переставил реплики';
      case 'scene.update': return `изменил сцену (${(d.fields ?? []).join(', ')})`;
      case 'scene.create': return `создал сцену ${d.scene_id}`;
      case 'scene.delete': return `удалил сцену ${d.scene_id}`;
      case 'scene.reorder': return 'переставил сцены';
      case 'comment.add': return `комментарий: «${d.body}»`;
      case 'comment.resolve': return 'закрыл комментарий';
      case 'comment.reopen': return 'открыл комментарий';
      case 'episode.update': return `изменил серию (${(d.fields ?? []).join(', ')})`;
      case 'episode.reimport': return `перечитал серию из YAML`;
      case 'episode.push': return `прислал YAML: ${(d.report ?? []).slice(0, 3).join('; ')}`;
      case 'episode.build': return `собрал редакцию ${d.revision}${d.commit ? ` (коммит ${d.commit})` : ''}`;
      case 'character.upsert': return `персонаж ${a.target_id}`;
      case 'character.delete': return `удалил персонажа ${a.target_id}`;
      default: return a.action;
    }
  };
  return (
    <div className="activity">
      {items.map((a) => (
        <div key={a.id} className="act">
          <div className="small muted">{fmtDate(a.created_at)} · {a.user_name ?? 'система'}</div>
          <div>{label(a)}</div>
        </div>
      ))}
      {items.length === 0 && <div className="muted">Пока пусто.</div>}
    </div>
  );
}

export function fmtDate(s: string) {
  // sqlite отдаёт UTC без зоны
  const d = new Date(s.replace(' ', 'T') + 'Z');
  return d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}
