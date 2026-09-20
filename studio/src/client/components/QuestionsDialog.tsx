import type { Episode } from '../types';
import type { Target } from '../pages/Episode';
import { Dialog } from './Dialog';

// Первая версия: просмотр и комментарии. Редактор вопросов — следующим шагом.
export function QuestionsDialog({ ep, onClose, onTarget }: { ep: Episode; onClose: () => void; onTarget: (t: Target) => void }) {
  return (
    <Dialog title={`Вопросы серии (${ep.questions.length})`} onClose={onClose} wide>
      <p className="muted small">Пока только просмотр и комментарии: нажмите «💬», чтобы обсудить вопрос. Правки — через YAML в content/questions (агент-сценарий) до появления редактора.</p>
      <div className="questions">
        {ep.questions.map((q) => {
          const d = q.data;
          const scene = ep.scenes.find((s) => s.quiz.includes(q.q_id));
          const n = ep.commentCounts['question:' + q.id] ?? 0;
          return (
            <div key={q.id} className="question card">
              <div className="row small muted">
                <span className="code">{q.q_id}</span>
                <span>факт {d.fact}</span>
                <span>{d.format}{d.context ? ` · ${d.context}` : ''}</span>
                <span>сложность {d.difficulty}</span>
                <span>{scene ? `после ${scene.scene_id}` : <span className="warn">не привязан к сцене</span>}</span>
                <div className="spacer" />
                <button className="link" onClick={() => { onTarget({ type: 'question', id: String(q.id), title: `Вопрос ${q.q_id}` }); onClose(); }}>💬 {n || ''}</button>
              </div>
              <div className="stem" lang="kk">{d.stem?.kk}</div>
              <div className="stem" lang="ru">{d.stem?.ru}</div>
              <ol className="opts">
                {(d.options ?? []).map((o: any) => (
                  <li key={o.id} className={o.correct ? 'correct' : ''}>{o.ru} <span className="muted">/ {o.kk}</span></li>
                ))}
              </ol>
              <div className="small muted">{d.explain?.ru}</div>
              <div className="small muted">источник: {d.source}</div>
            </div>
          );
        })}
      </div>
    </Dialog>
  );
}
