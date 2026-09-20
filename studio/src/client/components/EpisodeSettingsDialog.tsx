import { useState } from 'react';
import { api } from '../api';
import { can, useMe } from '../App';
import type { Episode } from '../types';
import { Dialog } from './Dialog';
import { toast, toastError } from './Toast';

export function EpisodeSettingsDialog({ ep, onClose }: { ep: Episode; onClose: () => void }) {
  const me = useMe();
  const manage = can(me, 'episode.manage');
  const approve = can(me, 'history.approve');
  const [f, setF] = useState({ title_kk: ep.title_kk, title_ru: ep.title_ru, era: ep.era ?? '', topics: ep.topics.join(', ') });
  const [visa, setVisa] = useState(ep.approved_by ?? '');

  const save = async () => {
    try {
      await api.patch(`/episodes/${ep.id}`, { ...f, topics: f.topics.split(/[,\s]+/).filter(Boolean) });
      toast('Сохранено');
      onClose();
    } catch (e) {
      toastError(e);
    }
  };
  const setVisaNow = async (v: string | null) => {
    try {
      await api.patch(`/episodes/${ep.id}`, { approved_by: v });
      toast(v ? 'Виза историка поставлена' : 'Виза снята');
    } catch (e) {
      toastError(e);
    }
  };
  const reimport = async () => {
    if (!confirm('Перечитать серию из content/ YAML? Все правки в студии по этой серии будут заменены содержимым файла.')) return;
    try {
      const r = await api.post(`/episodes/${ep.id}/reimport`);
      toast(`Импортировано: сцен ${r.scenes}, реплик ${r.beats}`);
      onClose();
    } catch (e) {
      toastError(e);
    }
  };

  return (
    <Dialog title={`Серия ${ep.id}`} onClose={onClose}>
      <div className="form">
        <label>Название kk<input value={f.title_kk} disabled={!manage} onChange={(e) => setF({ ...f, title_kk: e.target.value })} /></label>
        <label>Название ru<input value={f.title_ru} disabled={!manage} onChange={(e) => setF({ ...f, title_ru: e.target.value })} /></label>
        <label>Эпоха<input value={f.era} disabled={!manage} placeholder="1457–1468" onChange={(e) => setF({ ...f, era: e.target.value })} /></label>
        <label>Темы программы<input className="code-input" value={f.topics} disabled={!manage} placeholder="kz.4.1" onChange={(e) => setF({ ...f, topics: e.target.value })} /></label>
        <div className="small muted">Файл: content/episodes/{ep.season_id}/{ep.slug}.yaml · собранных редакций: {ep.revision}</div>
        {manage && <button className="primary" onClick={save}>Сохранить</button>}
      </div>
      <h4>Виза историка</h4>
      {ep.approved_by ? (
        <div className="row">
          <span className="pill ok">approved_by: {ep.approved_by}</span>
          {approve && <button className="link danger" onClick={() => setVisaNow(null)}>снять визу</button>}
        </div>
      ) : approve ? (
        <div className="row">
          <input placeholder="Имя историка" value={visa} onChange={(e) => setVisa(e.target.value)} />
          <button className="primary" disabled={!visa.trim()} onClick={() => setVisaNow(visa.trim())}>Поставить визу</button>
        </div>
      ) : (
        <div className="muted small">Визы нет. Ставит историк. Без визы серия не собирается.</div>
      )}
      {can(me, 'episode.build') && (
        <>
          <h4>Служебное</h4>
          <button className="link" onClick={reimport}>Перечитать из YAML (content/)</button>
        </>
      )}
    </Dialog>
  );
}
