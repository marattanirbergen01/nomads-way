import { useEffect } from 'react';

export function Dialog({ title, onClose, children, wide }: { title: string; onClose: () => void; children: React.ReactNode; wide?: boolean }) {
  useEffect(() => {
    const h = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    addEventListener('keydown', h);
    return () => removeEventListener('keydown', h);
  }, [onClose]);
  return (
    <div className="dialog-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={'dialog card' + (wide ? ' wide' : '')}>
        <div className="row">
          <h3>{title}</h3>
          <div className="spacer" />
          <button className="link" onClick={onClose}>✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}
