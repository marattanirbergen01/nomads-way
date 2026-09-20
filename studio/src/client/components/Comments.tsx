import { useEffect, useState } from 'react';
import { api } from '../api';
import { useMe } from '../App';
import { useLive } from '../live';
import type { Comment, Episode } from '../types';
import { ROLE_TITLES } from '../types';
import type { Target } from '../pages/Episode';
import { toastError } from './Toast';
import { fmtDate } from './SidePanel';

export function Comments({ ep, target, onTarget }: { ep: Episode; target: Target; onTarget: (t: Target) => void }) {
  const me = useMe();
  const [mode, setMode] = useState<'target' | 'all'>('target');
  const [items, setItems] = useState<Comment[]>([]);
  const [text, setText] = useState('');
  const [replyTo, setReplyTo] = useState<number | null>(null);
  const [showResolved, setShowResolved] = useState(false);

  const load = () =>
    (mode === 'target'
      ? api.get<Comment[]>(`/comments/${target.type}/${target.id}`)
      : api.get<Comment[]>(`/episodes/${ep.id}/comments`)
    )
      .then(setItems)
      .catch(toastError);
  useEffect(() => {
    load();
  }, [target.type, target.id, mode]);
  useLive((ev) => {
    if (ev.type === 'comment' && (ev.episodeId === ep.id || (ev.targetType === target.type && ev.targetId === target.id))) load();
  }, [target.type, target.id, mode, ep.id]);

  const send = async () => {
    if (!text.trim()) return;
    try {
      await api.post('/comments', { target_type: target.type, target_id: target.id, body: text, parent_id: replyTo });
      setText('');
      setReplyTo(null);
    } catch (e) {
      toastError(e);
    }
  };
  const resolve = (c: Comment, v: boolean) => api.patch(`/comments/${c.id}`, { resolved: v }).catch(toastError);
  const del = (c: Comment) => confirm('Удалить комментарий?') && api.del(`/comments/${c.id}`).catch(toastError);

  const roots = items.filter((c) => !c.parent_id && (showResolved || !c.resolved));
  const replies = (id: number) => items.filter((c) => c.parent_id === id);

  const targetLabel = (c: Comment) => {
    if (c.target_type === 'scene') {
      const s = ep.scenes.find((s) => String(s.id) === c.target_id);
      return s ? `Сцена ${s.scene_id}` : 'сцена';
    }
    if (c.target_type === 'beat') {
      for (const s of ep.scenes) {
        const i = s.beats.findIndex((b) => String(b.id) === c.target_id);
        if (i >= 0) return `${s.scene_id} · реплика ${i + 1}`;
      }
      return 'реплика (удалена)';
    }
    if (c.target_type === 'question') {
      const q = ep.questions.find((q) => String(q.id) === c.target_id);
      return q ? `Вопрос ${q.q_id}` : 'вопрос';
    }
    return 'Серия';
  };
  const jump = (c: Comment) => {
    if (c.target_type === 'beat') {
      for (const s of ep.scenes) {
        const i = s.beats.findIndex((b) => String(b.id) === c.target_id);
        if (i >= 0) {
          location.hash = `#/episode/${ep.id}/${s.scene_id}`;
          setTimeout(() => onTarget({ type: 'beat', id: c.target_id, title: `Реплика ${i + 1} · ${s.scene_id}` }), 50);
          setMode('target');
          return;
        }
      }
    }
    if (c.target_type === 'scene') {
      const s = ep.scenes.find((s) => String(s.id) === c.target_id);
      if (s) {
        location.hash = `#/episode/${ep.id}/${s.scene_id}`;
        setMode('target');
      }
    }
  };

  return (
    <div className="comments">
      <div className="row small">
        <button className={'link' + (mode === 'target' ? ' active' : '')} onClick={() => setMode('target')}>{target.title}</button>
        <button className={'link' + (mode === 'all' ? ' active' : '')} onClick={() => setMode('all')}>Вся серия</button>
        <div className="spacer" />
        <label className="muted">
          <input type="checkbox" checked={showResolved} onChange={(e) => setShowResolved(e.target.checked)} /> закрытые
        </label>
      </div>
      <div className="comment-list">
        {roots.map((c) => (
          <div key={c.id} className={'comment' + (c.resolved ? ' resolved' : '')}>
            <div className="small muted row">
              <b>{c.author_name}</b>
              <span>{ROLE_TITLES[c.author_role]}</span>
              <span>{fmtDate(c.created_at)}</span>
              {mode === 'all' && <button className="link" onClick={() => jump(c)}>{targetLabel(c)}</button>}
            </div>
            <div className="body">{c.body}</div>
            {replies(c.id).map((r) => (
              <div key={r.id} className="reply-item">
                <div className="small muted"><b>{r.author_name}</b> · {fmtDate(r.created_at)}</div>
                <div className="body">{r.body}</div>
              </div>
            ))}
            <div className="row small tools">
              <button className="link" onClick={() => { setReplyTo(c.id); setMode('target'); }}>ответить</button>
              {c.resolved ? (
                <button className="link" onClick={() => resolve(c, false)}>открыть снова</button>
              ) : (
                <button className="link" onClick={() => resolve(c, true)}>✓ решено</button>
              )}
              {(c.author_id === me.id || me.role === 'admin') && <button className="link danger" onClick={() => del(c)}>удалить</button>}
            </div>
          </div>
        ))}
        {roots.length === 0 && <div className="muted small">Комментариев нет.</div>}
      </div>
      {mode === 'target' && (
        <div className="comment-form">
          {replyTo && (
            <div className="small muted">
              ответ на комментарий · <button className="link" onClick={() => setReplyTo(null)}>отмена</button>
            </div>
          )}
          <textarea
            rows={3}
            placeholder={`Комментарий к: ${target.title}. Ctrl+Enter — отправить`}
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') send();
            }}
          />
          <button className="primary" onClick={send} disabled={!text.trim()}>Отправить</button>
        </div>
      )}
    </div>
  );
}
