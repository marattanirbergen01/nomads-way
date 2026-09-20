import { useEffect, useRef, useState } from 'react';
import { api, mediaUrl } from '../api';
import { can, useMe } from '../App';
import { useLive } from '../live';
import type { Media } from '../types';
import { toast, toastError } from '../components/Toast';
import { Dialog } from '../components/Dialog';

const KIND_TITLES: Record<string, string> = {
  scene: 'Кадры сцен',
  avatar: 'Аватары игрока',
  character: 'Портреты персонажей',
  map: 'Карты',
  cover: 'Обложки',
  banner: 'Баннеры',
  icon: 'Иконка',
};
const STATUS_TITLES: Record<string, string> = { missing: 'нет файла', draft: 'черновик', approved: 'утверждён' };

export function MediaPage({ season }: { season: string }) {
  const me = useMe();
  const [items, setItems] = useState<Media[]>([]);
  const [open, setOpen] = useState<Media | null>(null);
  const [filter, setFilter] = useState('');
  const load = () => api.get<Media[]>(`/media/${season}`).then(setItems).catch(toastError);
  useEffect(() => {
    load();
  }, [season]);
  useLive((ev) => {
    if (ev.type === 'media.changed' && ev.seasonId === season) load();
  }, [season]);
  useEffect(() => {
    if (open) setOpen(items.find((m) => m.id === open.id) ?? null);
  }, [items]);

  const kinds = Object.keys(KIND_TITLES).filter((k) => items.some((m) => m.kind === k));
  const shown = items.filter((m) => !filter || m.id.includes(filter) || (m.brief ?? '').toLowerCase().includes(filter.toLowerCase()));

  return (
    <div className="page media-page">
      <div className="row">
        <h2>Медиа · сезон {season.replace('s', '')}</h2>
        <input placeholder="поиск по id или брифу" value={filter} onChange={(e) => setFilter(e.target.value)} />
        <div className="spacer" />
        {can(me, 'media.edit') && (
          <button className="primary" onClick={() => {
            const id = prompt('id нового медиа (art_s1e02_010, char_esen_buga, …)');
            if (!id) return;
            const kind = id.startsWith('avatar_') ? 'avatar' : id.startsWith('char_') ? 'character' : id.startsWith('map_') ? 'map' : id.startsWith('cover_') ? 'cover' : 'scene';
            api.put(`/media/${season}/${id}`, { kind, brief: '' }).then(load).catch(toastError);
          }}>+ медиа</button>
        )}
      </div>
      <div className="small muted">Утверждённые файлы попадают в сборку; у каждого должен быть источник. Кадры сцен 768×1344 (новые серии — 1080×1920), аватары: портрет + _bust с альфой.</div>
      {kinds.map((k) => (
        <section key={k}>
          <h3>{KIND_TITLES[k]} <span className="muted small">{shown.filter((m) => m.kind === k).length}</span></h3>
          <div className="media-grid">
            {shown.filter((m) => m.kind === k).map((m) => (
              <div key={m.id} className={'media-card st-' + m.status} onClick={() => setOpen(m)}>
                <div className={'thumb ' + m.kind}>
                  {m.hasFile ? <img src={mediaUrl(season, m.id) + '?v=' + m.version} alt="" loading="lazy" /> : <span className="muted">нет файла</span>}
                </div>
                <div className="code small">{m.id}</div>
                <div className="row small">
                  <span className={'badge ms-' + m.status}>{STATUS_TITLES[m.status]}</span>
                  {m.status === 'approved' && !m.source && <span className="warn" title="Нет записи в sources/media.yaml">нет источника</span>}
                </div>
              </div>
            ))}
          </div>
        </section>
      ))}
      {open && <MediaDialog m={open} season={season} onClose={() => setOpen(null)} />}
    </div>
  );
}

function MediaDialog({ m, season, onClose }: { m: Media; season: string; onClose: () => void }) {
  const me = useMe();
  const edit = can(me, 'media.edit');
  const approve = can(me, 'media.approve');
  const [f, setF] = useState({ brief: m.brief ?? '', seed: m.seed ?? '', prompt_text: m.prompt_text ?? '', note: m.note ?? '' });
  const [src, setSrc] = useState({ license: m.source?.license ?? 'own-generation', origin: m.source?.origin ?? '', tool: m.source?.tool ?? '', author: m.source?.author ?? '' });
  const fileRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  const save = async () => {
    try {
      await api.put(`/media/${season}/${m.id}`, {
        brief: f.brief, seed: f.seed === '' ? null : Number(f.seed), prompt_text: f.prompt_text || null, note: f.note || null,
        source: src.origin ? { id: m.id, file: m.file ? `content/media/${season}/${m.file}` : null, ...src, date: m.generated ?? new Date().toISOString().slice(0, 10), hist_review: m.source?.hist_review ?? null } : m.source,
      });
      toast('Сохранено');
    } catch (e) {
      toastError(e);
    }
  };
  const upload = async (file: File) => {
    setBusy(true);
    try {
      const fd = new FormData();
      fd.append('file', file);
      await api.upload(`/media/${season}/${m.id}/upload`, fd);
      toast('Файл загружен');
    } catch (e) {
      toastError(e);
    } finally {
      setBusy(false);
    }
  };
  const setStatus = async (status: string) => {
    try {
      await api.put(`/media/${season}/${m.id}`, { status, approved_by: status === 'approved' ? me.name : null });
    } catch (e) {
      toastError(e);
    }
  };
  const del = async () => {
    if (!confirm(`Удалить ${m.id}?`)) return;
    try {
      await api.del(`/media/${season}/${m.id}`);
      onClose();
    } catch (e) {
      toastError(e);
    }
  };

  return (
    <Dialog title={m.id} onClose={onClose} wide>
      <div className="media-dialog">
        <div className="preview-col">
          <div className={'thumb big ' + m.kind}>
            {m.hasFile ? <img src={mediaUrl(season, m.id) + '?v=' + m.version} alt="" /> : <span className="muted">файла нет</span>}
          </div>
          {m.kind === 'avatar' && m.hasFile && (
            <div className="small muted">бюст: {m.id}_bust {/* показываем, если есть */}
              <img className="bust-thumb" src={mediaUrl(season, m.id + '_bust')} alt="" onError={(e) => ((e.target as HTMLImageElement).style.display = 'none')} />
            </div>
          )}
          {edit && (
            <div className="row">
              <input ref={fileRef} type="file" accept="image/png,image/jpeg,image/webp" style={{ display: 'none' }} onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />
              <button onClick={() => fileRef.current?.click()} disabled={busy}>{busy ? 'Загрузка…' : m.hasFile ? 'Заменить файл' : 'Загрузить файл'}</button>
              <button className="link danger" onClick={del}>удалить</button>
            </div>
          )}
          <div className="row small">
            <span className={'badge ms-' + m.status}>{STATUS_TITLES[m.status]}</span>
            {m.approved_by && <span className="muted">виза: {m.approved_by}</span>}
            {approve && m.hasFile && m.status !== 'approved' && <button className="primary small" onClick={() => setStatus('approved')}>Утвердить</button>}
            {approve && m.status === 'approved' && <button className="link" onClick={() => setStatus('draft')}>снять утверждение</button>}
          </div>
          <div className="small muted">файл: {m.file ?? '—'} {m.upload && '(загружен через студию)'} · {m.generated ?? ''}</div>
        </div>
        <div className="form">
          <label>Бриф (что в кадре)<textarea rows={3} value={f.brief} disabled={!edit} onChange={(e) => setF({ ...f, brief: e.target.value })} /></label>
          <label>Seed<input className="code-input" value={f.seed} disabled={!edit} onChange={(e) => setF({ ...f, seed: e.target.value })} /></label>
          <label>Промпт<textarea rows={6} className="code-input" value={f.prompt_text} disabled={!edit} onChange={(e) => setF({ ...f, prompt_text: e.target.value })} placeholder="Промпт генерации; уйдёт в prompts/<тип>/<id>.md" /></label>
          <label>Заметка<textarea rows={2} value={f.note} disabled={!edit} onChange={(e) => setF({ ...f, note: e.target.value })} /></label>
          <h4>Источник (sources/media.yaml)</h4>
          <label>Лицензия
            <select value={src.license} disabled={!edit} onChange={(e) => setSrc({ ...src, license: e.target.value })}>
              {['own-generation', 'cc-by', 'cc-by-sa', 'public-domain', 'licensed'].map((l) => <option key={l}>{l}</option>)}
            </select>
          </label>
          <label>Происхождение<input value={src.origin} disabled={!edit} onChange={(e) => setSrc({ ...src, origin: e.target.value })} placeholder="ИИ-генерация по промпту …; 768×1344, seed …" /></label>
          <label>Инструмент<input value={src.tool} disabled={!edit} onChange={(e) => setSrc({ ...src, tool: e.target.value })} placeholder="Draw Things · FLUX.2 / Gemini" /></label>
          <label>Автор<input value={src.author} disabled={!edit} onChange={(e) => setSrc({ ...src, author: e.target.value })} /></label>
          {edit && <button className="primary" onClick={save}>Сохранить</button>}
        </div>
      </div>
    </Dialog>
  );
}
