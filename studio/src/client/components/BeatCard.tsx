import { useState } from 'react';
import { api, mediaUrl } from '../api';
import { can, useMe } from '../App';
import type { Beat, Episode, Media, Scene } from '../types';
import { EMOTIONS, EMOTION_TITLES } from '../types';
import { useDraft } from './useDraft';
import { toastError } from './Toast';
import { AutoTextarea } from './AutoTextarea';

interface Props {
  ep: Episode;
  scene: Scene;
  beat: Beat;
  media: Media[];
  editable: boolean;
  selected: boolean;
  commentCount: number;
  onSelect: () => void;
  onEditing: (v: boolean) => void;
  onMove: (dir: -1 | 1) => void;
  onDelete: () => void;
  first: boolean;
  last: boolean;
  editingBy?: string;
}

// Аватар игрока: первая утверждённая внешность — для картинок эмоций в редакторе.
export function avatarIdsFor(media: Media[]) {
  const looks = new Map<string, string[]>();
  for (const m of media) {
    if (m.kind !== 'avatar' || !m.hasFile) continue;
    const mm = m.id.match(/^(avatar_\d+_[a-z]+)_([a-z]+)$/);
    if (!mm) continue;
    if (!looks.has(mm[1])) looks.set(mm[1], []);
    looks.get(mm[1])!.push(mm[2]);
  }
  return [...looks.keys()].sort();
}

export function BeatCard(p: Props) {
  const me = useMe();
  const { beat, ep, scene } = p;
  const d = useDraft(`/beats/${beat.id}`, beat, beat.version, (b) => ({
    who: b.who,
    kk: b.kk,
    ru: b.ru,
    emotion: b.emotion,
    when_cond: b.when_cond,
  }));
  const [more, setMore] = useState(!!beat.when_cond);
  const ch = ep.characters.find((c) => c.char_id === d.draft.who);
  const isAvatar = !!ch?.avatar;
  const looks = avatarIdsFor(p.media);
  const look = looks[0];

  const blur = async () => {
    p.onEditing(false);
    await d.save();
  };
  const focus = () => {
    p.onEditing(true);
    p.onSelect();
  };
  const markReviewed = async () => {
    try {
      await api.patch(`/beats/${beat.id}`, { needs_review: 0 });
    } catch (e) {
      toastError(e);
    }
  };

  const portrait = ch?.portrait ?? (isAvatar && look ? `${look}_${d.draft.emotion ?? 'calm'}` : ch ? `char_${ch.char_id}` : null);
  const hasPortrait = portrait && p.media.some((m) => m.id === portrait && m.hasFile);

  return (
    <div
      className={
        'beat card' +
        (p.selected ? ' selected' : '') +
        (beat.needs_review ? ' needs-review' : '') +
        (d.remoteChanged ? ' remote-changed' : '')
      }
      onClick={p.onSelect}
    >
      <div className="beat-side">
        <div className={'portrait' + (isAvatar ? ' avatar' : '')}>
          {hasPortrait ? <img src={mediaUrl(ep.season_id, portrait!)} alt="" /> : <span>{(ch?.name_ru ?? '?')[0]}</span>}
        </div>
      </div>
      <div className="beat-body">
        <div className="row beat-top">
          <select
            value={d.draft.who ?? ''}
            disabled={!p.editable}
            onChange={(e) => {
              d.set({ who: e.target.value || null } as any);
            }}
            onFocus={focus}
            onBlur={blur}
            className="who"
          >
            <option value="">— кто говорит —</option>
            {ep.characters.map((c) => (
              <option key={c.char_id} value={c.char_id}>
                {c.name_ru} {c.avatar ? '(аватар)' : ''}
              </option>
            ))}
          </select>
          {isAvatar && (
            <div className="emotions" title="Эмоция аватара в этой реплике">
              {EMOTIONS.map((e) => (
                <button
                  key={e}
                  type="button"
                  disabled={!p.editable}
                  className={'emotion' + ((d.draft.emotion ?? 'calm') === e ? ' active' : '')}
                  title={EMOTION_TITLES[e]}
                  onClick={async (ev) => {
                    ev.stopPropagation();
                    p.onSelect();
                    d.set({ emotion: e } as any);
                    // сохраняем сразу — это клик, а не ввод
                    setTimeout(() => d.save(), 0);
                  }}
                >
                  {look && p.media.some((m) => m.id === `${look}_${e}` && m.hasFile) ? (
                    <img src={mediaUrl(ep.season_id, `${look}_${e}`)} alt={EMOTION_TITLES[e]} />
                  ) : (
                    <span>{EMOTION_TITLES[e][0]}</span>
                  )}
                  <em>{EMOTION_TITLES[e]}</em>
                </button>
              ))}
            </div>
          )}
          <div className="spacer" />
          {beat.needs_review === 1 && (
            <span className="pill agent">
              предложено агентом
              {can(me, 'scene.status') && (
                <button className="link" onClick={markReviewed}>
                  · просмотрено
                </button>
              )}
            </span>
          )}
          {p.editingBy && <span className="pill">{p.editingBy} правит</span>}
          {p.commentCount > 0 && <span className="pill">💬 {p.commentCount}</span>}
          {p.editable && (
            <span className="beat-tools">
              <button className="link" disabled={p.first} onClick={(e) => { e.stopPropagation(); p.onMove(-1); }} title="Выше">↑</button>
              <button className="link" disabled={p.last} onClick={(e) => { e.stopPropagation(); p.onMove(1); }} title="Ниже">↓</button>
              <button className="link" onClick={(e) => { e.stopPropagation(); setMore(!more); }} title="Условие показа">⋯</button>
              <button className="link danger" onClick={(e) => { e.stopPropagation(); p.onDelete(); }} title="Удалить">✕</button>
            </span>
          )}
        </div>
        <div className="langs">
          <AutoTextarea
            lang="kk"
            placeholder="Қазақша"
            value={d.draft.kk ?? ''}
            disabled={!p.editable}
            onChange={(v) => d.set({ kk: v } as any)}
            onFocus={focus}
            onBlur={blur}
          />
          <AutoTextarea
            lang="ru"
            placeholder="По-русски"
            value={d.draft.ru ?? ''}
            disabled={!p.editable}
            onChange={(v) => d.set({ ru: v } as any)}
            onFocus={focus}
            onBlur={blur}
          />
        </div>
        {(more || d.draft.when_cond) && (
          <div className="row small when">
            <span className="muted">показывать при условии:</span>
            <input
              className="code-input"
              placeholder="yurt_river  |  loyalty >= 2 && caution == 0"
              value={d.draft.when_cond ?? ''}
              disabled={!p.editable}
              onChange={(e) => d.set({ when_cond: e.target.value || null } as any)}
              onFocus={focus}
              onBlur={blur}
            />
          </div>
        )}
        {d.conflict && (
          <div className="conflict">
            <b>Эту реплику одновременно изменил другой участник.</b>
            <div className="conflict-cols">
              <div>
                <div className="muted small">Их версия</div>
                <div className="q">{d.conflict.kk}</div>
                <div className="q">{d.conflict.ru}</div>
              </div>
              <div>
                <div className="muted small">Ваша версия</div>
                <div className="q">{d.draft.kk}</div>
                <div className="q">{d.draft.ru}</div>
              </div>
            </div>
            <div className="row">
              <button className="primary" onClick={d.takeTheirs}>Взять их</button>
              <button onClick={d.keepMine}>Оставить мою</button>
            </div>
          </div>
        )}
        {d.remoteChanged && !d.conflict && <div className="small warn">Кто-то изменил эту реплику, пока вы её правите — при сохранении покажем обе версии.</div>}
      </div>
    </div>
  );
}
