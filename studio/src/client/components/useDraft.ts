import { useEffect, useRef, useState } from 'react';
import { api, Conflict } from '../api';
import { toast, toastError } from './Toast';

// Локальный черновик записи с версией. Пока поле в фокусе (dirty), live-обновления
// его не затирают; при сохранении сервер сверяет версию, конфликт показываем явно.
export function useDraft<T extends Record<string, any>>(
  url: string,
  serverValue: T,
  serverVersion: number,
  pick: (v: T) => Partial<T>,
) {
  const [draft, setDraft] = useState<Partial<T>>(() => pick(serverValue));
  const [dirty, setDirty] = useState(false);
  const [conflict, setConflict] = useState<Partial<T> | null>(null);
  const versionRef = useRef(serverVersion);
  const [remoteChanged, setRemoteChanged] = useState(false);

  useEffect(() => {
    if (!dirty) {
      setDraft(pick(serverValue));
      versionRef.current = serverVersion;
      setRemoteChanged(false);
    } else if (serverVersion !== versionRef.current) {
      setRemoteChanged(true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [serverVersion]);

  const set = (patch: Partial<T>) => {
    setDraft((d) => ({ ...d, ...patch }));
    setDirty(true);
  };

  const save = async (force = false) => {
    if (!dirty && !force) return true;
    const patch: Record<string, any> = {};
    const base = pick(serverValue);
    for (const k of Object.keys(draft)) {
      if (JSON.stringify(draft[k]) !== JSON.stringify(base[k])) patch[k] = draft[k];
    }
    if (!Object.keys(patch).length) {
      setDirty(false);
      return true;
    }
    try {
      const r = await api.patch<{ version: number }>(url, force ? patch : { ...patch, version: versionRef.current });
      versionRef.current = r.version;
      setDirty(false);
      setConflict(null);
      setRemoteChanged(false);
      return true;
    } catch (e) {
      if (e instanceof Conflict) {
        setConflict(pick(e.current));
        return false;
      }
      toastError(e);
      return false;
    }
  };

  const takeTheirs = () => {
    if (conflict) setDraft(conflict);
    setDirty(false);
    setConflict(null);
    setRemoteChanged(false);
    toast('Взята версия коллеги');
  };
  const keepMine = async () => {
    setConflict(null);
    await save(true);
    toast('Ваша версия сохранена');
  };

  return { draft, set, save, dirty, conflict, takeTheirs, keepMine, remoteChanged };
}
