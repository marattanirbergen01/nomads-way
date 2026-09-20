import { mediaUrl } from '../api';
import type { Beat, Choice, ChoiceOption, Episode, Media, Scene } from '../types';
import { EMOTIONS, EMOTION_TITLES } from '../types';
import { useDraft } from './useDraft';
import { AutoTextarea } from './AutoTextarea';
import { avatarIdsFor } from './BeatCard';

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

const emptyChoice: Choice = { prompt: { kk: '', ru: '' }, options: [] };

// set: {practical: 1, yurt_river: 1} ↔ "practical: 1, yurt_river: 1"
function setToText(s: Record<string, number> | null) {
  return s ? Object.entries(s).map(([k, v]) => `${k}: ${v}`).join(', ') : '';
}
function textToSet(t: string): Record<string, number> | null {
  const out: Record<string, number> = {};
  for (const part of t.split(',')) {
    const m = part.trim().match(/^([a-z_][a-z0-9_]*)\s*[:=]\s*([+-]?\d+)$/i);
    if (m) out[m[1]] = Number(m[2]);
  }
  return Object.keys(out).length ? out : null;
}

export function ChoiceCard(p: Props) {
  const { beat, ep, scene } = p;
  const d = useDraft(`/beats/${beat.id}`, beat, beat.version, (b) => ({ choice: b.choice ?? emptyChoice }));
  const choice: Choice = d.draft.choice ?? emptyChoice;
  const setChoice = (c: Choice) => d.set({ choice: c } as any);
  const setOpt = (i: number, patch: Partial<ChoiceOption>) =>
    setChoice({ ...choice, options: choice.options.map((o, k) => (k === i ? { ...o, ...patch } : o)) });

  const blur = async () => {
    p.onEditing(false);
    await d.save();
  };
  const focus = () => {
    p.onEditing(true);
    p.onSelect();
  };
  const sceneIds = ep.scenes.map((s) => s.scene_id);
  const arts = p.media.filter((m) => m.kind === 'scene');
  const look = avatarIdsFor(p.media)[0];
  const nextIdx = ep.scenes.findIndex((s) => s.id === scene.id) + 1;
  const nextScene = ep.scenes[nextIdx]?.scene_id ?? 'end';

  const addOption = () => {
    const id = String.fromCharCode(97 + choice.options.length);
    setChoice({ ...choice, options: [...choice.options, { id, kk: '', ru: '', set: null, goto: nextScene, art: null, reply: null }] });
    setTimeout(() => d.save(), 0);
  };
  const removeOption = (i: number) => {
    setChoice({ ...choice, options: choice.options.filter((_, k) => k !== i) });
    setTimeout(() => d.save(), 0);
  };

  return (
    <div className={'beat choice card' + (p.selected ? ' selected' : '') + (beat.needs_review ? ' needs-review' : '')} onClick={p.onSelect}>
      <div className="beat-side">
        <div className="portrait choice-mark">?</div>
      </div>
      <div className="beat-body">
        <div className="row beat-top">
          <b>Развилка</b>
          <span className="muted small">игрок выбирает; вопрос и варианты</span>
          <div className="spacer" />
          {beat.needs_review === 1 && <span className="pill agent">предложено агентом</span>}
          {p.editingBy && <span className="pill">{p.editingBy} правит</span>}
          {p.commentCount > 0 && <span className="pill">💬 {p.commentCount}</span>}
          {p.editable && (
            <span className="beat-tools">
              <button className="link" disabled={p.first} onClick={(e) => { e.stopPropagation(); p.onMove(-1); }}>↑</button>
              <button className="link" disabled={p.last} onClick={(e) => { e.stopPropagation(); p.onMove(1); }}>↓</button>
              <button className="link danger" onClick={(e) => { e.stopPropagation(); p.onDelete(); }}>✕</button>
            </span>
          )}
        </div>
        <div className="langs">
          <AutoTextarea lang="kk" placeholder="Сұрақ (kk)" value={choice.prompt.kk} disabled={!p.editable}
            onChange={(v) => setChoice({ ...choice, prompt: { ...choice.prompt, kk: v } })} onFocus={focus} onBlur={blur} />
          <AutoTextarea lang="ru" placeholder="Вопрос игроку (ru)" value={choice.prompt.ru} disabled={!p.editable}
            onChange={(v) => setChoice({ ...choice, prompt: { ...choice.prompt, ru: v } })} onFocus={focus} onBlur={blur} />
        </div>
        <div className="options">
          {choice.options.map((o, i) => (
            <div key={i} className="option">
              <div className="row small">
                <input className="code-input tiny" value={o.id} disabled={!p.editable} title="id варианта"
                  onChange={(e) => setOpt(i, { id: e.target.value })} onFocus={focus} onBlur={blur} />
                <span className="muted">→</span>
                <select value={o.goto ?? ''} disabled={!p.editable} onChange={(e) => { setOpt(i, { goto: e.target.value || null }); setTimeout(() => d.save(), 0); }} onFocus={focus} onBlur={blur} title="Куда ведёт">
                  <option value="">(следующая сцена)</option>
                  {sceneIds.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                  <option value="end">end — конец серии</option>
                </select>
                <input className="code-input" placeholder="set: practical: 1, yurt_river: 1" defaultValue={setToText(o.set)} disabled={!p.editable}
                  title="Переменные сюжета" onFocus={focus}
                  onBlur={(e) => { setOpt(i, { set: textToSet(e.target.value) }); blur(); }} />
                <select value={o.art ?? ''} disabled={!p.editable} onChange={(e) => { setOpt(i, { art: e.target.value || null }); setTimeout(() => d.save(), 0); }} onFocus={focus} onBlur={blur} title="Свой кадр у варианта (развилка двумя кадрами)">
                  <option value="">без своего кадра</option>
                  {arts.map((m) => (
                    <option key={m.id} value={m.id}>{m.id}</option>
                  ))}
                </select>
                {p.editable && (
                  <button className="link danger" onClick={() => removeOption(i)} title="Убрать вариант">✕</button>
                )}
              </div>
              <div className="langs">
                <AutoTextarea lang="kk" placeholder="Нұсқа (kk)" value={o.kk} disabled={!p.editable} onChange={(v) => setOpt(i, { kk: v })} onFocus={focus} onBlur={blur} />
                <AutoTextarea lang="ru" placeholder="Вариант (ru)" value={o.ru} disabled={!p.editable} onChange={(v) => setOpt(i, { ru: v })} onFocus={focus} onBlur={blur} />
              </div>
              <div className="reply">
                <div className="row small">
                  <span className="muted">ответ аватара после выбора:</span>
                  <div className="emotions small">
                    {EMOTIONS.map((e) => (
                      <button key={e} type="button" disabled={!p.editable}
                        className={'emotion' + ((o.reply?.emotion ?? 'calm') === e ? ' active' : '')} title={EMOTION_TITLES[e]}
                        onClick={(ev) => { ev.stopPropagation(); setOpt(i, { reply: { kk: o.reply?.kk ?? '', ru: o.reply?.ru ?? '', emotion: e } }); setTimeout(() => d.save(), 0); }}>
                        {look && p.media.some((m) => m.id === `${look}_${e}` && m.hasFile) ? <img src={mediaUrl(ep.season_id, `${look}_${e}`)} alt="" /> : <span>{EMOTION_TITLES[e][0]}</span>}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="langs">
                  <AutoTextarea lang="kk" placeholder="Жауап (kk) — необязательно" value={o.reply?.kk ?? ''} disabled={!p.editable}
                    onChange={(v) => setOpt(i, { reply: { kk: v, ru: o.reply?.ru ?? '', emotion: o.reply?.emotion ?? null } })} onFocus={focus} onBlur={blur} />
                  <AutoTextarea lang="ru" placeholder="Ответ (ru)" value={o.reply?.ru ?? ''} disabled={!p.editable}
                    onChange={(v) => setOpt(i, { reply: { kk: o.reply?.kk ?? '', ru: v, emotion: o.reply?.emotion ?? null } })} onFocus={focus} onBlur={blur} />
                </div>
              </div>
            </div>
          ))}
          {p.editable && (
            <button className="link" onClick={addOption}>+ вариант</button>
          )}
        </div>
        {d.conflict && (
          <div className="conflict">
            <b>Развилку одновременно изменил другой участник.</b>
            <div className="row">
              <button className="primary" onClick={d.takeTheirs}>Взять их версию</button>
              <button onClick={d.keepMine}>Оставить мою</button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
