import { useState } from 'react';
import { api, mediaUrl } from '../api';
import { can, useMe } from '../App';
import type { Character, Episode, Media } from '../types';
import { Dialog } from './Dialog';
import { toastError } from './Toast';

export function CharactersDialog({ ep, media, onClose }: { ep: Episode; media: Media[]; onClose: () => void }) {
  const me = useMe();
  const editable = can(me, 'scene.edit');
  const [edit, setEdit] = useState<Partial<Character> | null>(null);
  const portraits = media.filter((m) => m.kind === 'character' || m.kind === 'avatar');

  const save = async () => {
    if (!edit) return;
    try {
      await api.put(`/episodes/${ep.id}/characters`, edit);
      setEdit(null);
    } catch (e) {
      toastError(e);
    }
  };
  const del = async (c: Character) => {
    if (!confirm(`Удалить персонажа ${c.name_ru}? Реплики с ним останутся без говорящего.`)) return;
    try {
      await api.del(`/episodes/${ep.id}/characters/${c.char_id}`);
    } catch (e) {
      toastError(e);
    }
  };

  return (
    <Dialog title="Персонажи серии" onClose={onClose} wide>
      <table className="table">
        <thead>
          <tr><th></th><th>id</th><th>kk</th><th>ru</th><th>тип</th><th>заметка</th><th></th></tr>
        </thead>
        <tbody>
          {ep.characters.map((c) => {
            const pid = c.portrait ?? `char_${c.char_id}`;
            const has = media.some((m) => m.id === pid && m.hasFile);
            return (
              <tr key={c.id}>
                <td>{has ? <img className="mini" src={mediaUrl(ep.season_id, pid)} alt="" /> : <span className="mini empty" />}</td>
                <td><span className="code">{c.char_id}</span></td>
                <td>{c.name_kk}</td>
                <td>{c.name_ru}</td>
                <td className="small muted">{c.avatar ? 'аватар игрока' : c.fiction ? 'вымышленный' : 'историческое лицо'}</td>
                <td className="small muted">{c.note}</td>
                <td>
                  {editable && (
                    <>
                      <button className="link" onClick={() => setEdit({ ...c })}>изменить</button>
                      <button className="link danger" onClick={() => del(c)}>✕</button>
                    </>
                  )}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
      {editable && !edit && (
        <button className="link" onClick={() => setEdit({ char_id: '', name_kk: '', name_ru: '', fiction: 1, avatar: 0, note: '', portrait: null })}>+ персонаж</button>
      )}
      {edit && (
        <div className="card inline-form" style={{ marginTop: 12 }}>
          <label>id<input className="code-input" value={edit.char_id ?? ''} onChange={(e) => setEdit({ ...edit, char_id: e.target.value })} disabled={!!edit.id} /></label>
          <label>Имя kk<input value={edit.name_kk ?? ''} onChange={(e) => setEdit({ ...edit, name_kk: e.target.value })} /></label>
          <label>Имя ru<input value={edit.name_ru ?? ''} onChange={(e) => setEdit({ ...edit, name_ru: e.target.value })} /></label>
          <label>Тип
            <select value={edit.avatar ? 'avatar' : edit.fiction ? 'fiction' : 'real'} onChange={(e) => {
              const v = e.target.value;
              setEdit({ ...edit, avatar: v === 'avatar' ? 1 : 0, fiction: v === 'real' ? 0 : 1 });
            }}>
              <option value="real">историческое лицо</option>
              <option value="fiction">вымышленный</option>
              <option value="avatar">аватар игрока</option>
            </select>
          </label>
          <label>Портрет
            <select value={edit.portrait ?? ''} onChange={(e) => setEdit({ ...edit, portrait: e.target.value || null })}>
              <option value="">char_{edit.char_id || '…'} (по умолчанию)</option>
              {portraits.map((m) => <option key={m.id} value={m.id}>{m.id}</option>)}
            </select>
          </label>
          <label style={{ flexBasis: '100%' }}>Заметка<input value={edit.note ?? ''} onChange={(e) => setEdit({ ...edit, note: e.target.value })} /></label>
          <button className="primary" onClick={save}>Сохранить</button>
          <button className="link" onClick={() => setEdit(null)}>Отмена</button>
        </div>
      )}
      <p className="muted small">Историческое лицо — только с источником. Аватар игрока: в репликах по имени не называть и не склонять.</p>
    </Dialog>
  );
}
