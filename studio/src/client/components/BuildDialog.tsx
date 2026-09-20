import { useEffect, useRef, useState } from 'react';
import { api } from '../api';
import { can, useMe } from '../App';
import { useLive } from '../live';
import type { Episode } from '../types';
import { Dialog } from './Dialog';
import { toastError } from './Toast';

export function BuildDialog({ ep, onClose }: { ep: Episode; onClose: () => void }) {
  const me = useMe();
  const [pf, setPf] = useState<{ errors: string[]; warnings: string[] } | null>(null);
  const [files, setFiles] = useState<string[]>([]);
  const [log, setLog] = useState<string[]>([]);
  const [running, setRunning] = useState(false);
  const [push, setPush] = useState(true);
  const logRef = useRef<HTMLPreElement>(null);

  const refresh = () => {
    api.get(`/episodes/${ep.id}/preflight`).then(setPf).catch(toastError);
    api.get(`/episodes/${ep.id}/export`).then((r) => setFiles(r.files)).catch(toastError);
    api.get(`/episodes/${ep.id}/build`).then((b) => { if (b) { setLog(b.log); setRunning(b.running); } }).catch(() => {});
  };
  useEffect(refresh, [ep.id, ep.version, ep.updated_at]);
  useLive((ev) => {
    if (ev.type === 'build' && ev.episodeId === ep.id) {
      setLog((l) => [...l, ev.line]);
      setRunning(ev.running);
      if (!ev.running) refresh();
    }
  }, [ep.id]);
  useEffect(() => { logRef.current?.scrollTo(0, 1e9); }, [log.length]);

  const start = async () => {
    setLog([]);
    try {
      await api.post(`/episodes/${ep.id}/build`, { push });
      setRunning(true);
    } catch (e) { toastError(e); }
  };
  const ready = pf && pf.errors.length === 0;

  return (
    <Dialog title={`Собрать серию ${ep.id}`} onClose={onClose} wide>
      <p className="muted small">
        Сборка записывает YAML и медиа в <span className="code">content/</span>, запускает компилятор, собирает бандлы и делает коммит.
        Редакция №{ep.revision + 1}. Ничего не записывается, пока есть ошибки.
      </p>
      {!pf ? <div className="muted">Проверяем…</div> : (
        <div className="build-checks">
          {pf.errors.map((e, i) => <div key={i} className="warn">✗ {e}</div>)}
          {pf.warnings.map((e, i) => <div key={'w' + i} className="muted">⚠ {e}</div>)}
          {ready && <div className="ok">✓ Проверки студии пройдены. Компилятор проверит факты и вопросы.</div>}
        </div>
      )}
      <details className="small" style={{ margin: '10px 0' }}>
        <summary className="muted">Что будет записано ({files.length})</summary>
        <ul>{files.map((f) => <li key={f}><span className="code">{f}</span></li>)}</ul>
      </details>
      {can(me, 'episode.build') && (
        <div className="row">
          <button className="primary" disabled={!ready || running} onClick={start}>{running ? 'Идёт сборка…' : 'Собрать и закоммитить'}</button>
          <label className="small muted"><input type="checkbox" checked={push} onChange={(e) => setPush(e.target.checked)} /> git push после коммита</label>
        </div>
      )}
      {log.length > 0 && <pre className="build-log" ref={logRef}>{log.join('\n')}</pre>}
    </Dialog>
  );
}
