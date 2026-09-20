import { useEffect, useState } from 'react';

type Toast = { id: number; text: string; kind: 'ok' | 'err' };
const listeners = new Set<(t: Toast) => void>();
let n = 0;
export function toast(text: string, kind: 'ok' | 'err' = 'ok') {
  listeners.forEach((l) => l({ id: ++n, text, kind }));
}
export function toastError(e: unknown) {
  toast(e instanceof Error ? e.message : String(e), 'err');
}

export function ToastHost() {
  const [items, setItems] = useState<Toast[]>([]);
  useEffect(() => {
    const l = (t: Toast) => {
      setItems((s) => [...s, t]);
      setTimeout(() => setItems((s) => s.filter((x) => x.id !== t.id)), t.kind === 'err' ? 6000 : 2500);
    };
    listeners.add(l);
    return () => {
      listeners.delete(l);
    };
  }, []);
  return (
    <div className="toasts">
      {items.map((t) => (
        <div key={t.id} className={'toast ' + t.kind}>
          {t.text}
        </div>
      ))}
    </div>
  );
}
