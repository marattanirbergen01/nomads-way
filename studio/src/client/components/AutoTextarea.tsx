import { useEffect, useRef } from 'react';

interface Props {
  value: string;
  onChange: (v: string) => void;
  onFocus?: () => void;
  onBlur?: () => void;
  placeholder?: string;
  disabled?: boolean;
  lang?: string;
  rows?: number;
}

// Textarea, растущая по содержимому. Ctrl/Cmd+Enter — снять фокус (= сохранить).
export function AutoTextarea({ value, onChange, onFocus, onBlur, placeholder, disabled, lang, rows = 1 }: Props) {
  const ref = useRef<HTMLTextAreaElement>(null);
  const fit = () => {
    const el = ref.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = el.scrollHeight + 2 + 'px';
  };
  useEffect(fit, [value]);
  // высота зависит и от ширины: при смене ширины окна/колонки пересчитываем
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let w = el.clientWidth;
    const ro = new ResizeObserver(() => {
      if (el.clientWidth !== w) {
        w = el.clientWidth;
        fit();
      }
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return (
    <textarea
      ref={ref}
      className={'auto ' + (lang ?? '')}
      lang={lang}
      rows={rows}
      value={value}
      placeholder={placeholder}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
      onFocus={onFocus}
      onBlur={onBlur}
      onKeyDown={(e) => {
        if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') (e.target as HTMLTextAreaElement).blur();
      }}
      spellCheck={lang === 'ru'}
    />
  );
}
