import { useEffect, useState } from 'react';
import { api } from '../api';
import { useLive } from '../live';
import { can, useMe } from '../App';
import { EPISODE_STATUS_TITLES, type EpisodeSummary, type Season } from '../types';
import { toastError } from '../components/Toast';

export function EpisodesPage() {
  const me = useMe();
  const [data, setData] = useState<{ seasons: Season[]; episodes: EpisodeSummary[] } | null>(null);
  const [newEp, setNewEp] = useState<string | null>(null); // season id
  const [newSeason, setNewSeason] = useState(false);

  const load = () => api.get('/episodes').then(setData).catch(toastError);
  useEffect(() => {
    load();
  }, []);
  useLive((ev) => {
    if (ev.type === 'episodes.changed' || ev.type === 'episode.changed' || ev.type === 'comment') load();
  });

  if (!data) return <div className="page muted">Загрузка…</div>;
  const manage = can(me, 'episode.manage');

  return (
    <div className="page">
      {data.seasons.map((s) => {
        const eps = data.episodes.filter((e) => e.season_id === s.id);
        return (
          <section key={s.id} className="season">
            <h2>
              {s.title_ru} <span className="muted">· {s.title_kk}</span>
              {manage && (
                <button className="link small" onClick={() => setNewEp(s.id)}>
                  + серия
                </button>
              )}
            </h2>
            <div className="episode-grid">
              {eps.map((e) => (
                <a key={e.id} href={`#/episode/${e.id}`} className="card episode-card">
                  <div className="row">
                    <span className="code">{e.id}</span>
                    <span className={'badge st-' + e.status}>{EPISODE_STATUS_TITLES[e.status]}</span>
                  </div>
                  <h3>{e.title_ru || '(без названия)'}</h3>
                  <div className="muted">{e.title_kk}</div>
                  {e.era && <div className="muted small">{e.era}</div>}
                  <div className="row small muted" style={{ marginTop: 8 }}>
                    <span>
                      сцен: {e.scene_count} · готово: {e.ready_count}
                    </span>
                    {e.open_comments > 0 && <span className="pill">💬 {e.open_comments}</span>}
                  </div>
                  <div className="progress">
                    <div style={{ width: e.scene_count ? `${(100 * e.ready_count) / e.scene_count}%` : 0 }} />
                  </div>
                </a>
              ))}
              {eps.length === 0 && <div className="muted">Серий пока нет.</div>}
            </div>
            {newEp === s.id && <NewEpisodeForm season={s.id} onDone={() => setNewEp(null)} />}
          </section>
        );
      })}
      {manage && (
        <div style={{ marginTop: 24 }}>
          {newSeason ? (
            <NewSeasonForm onDone={() => setNewSeason(false)} />
          ) : (
            <button className="link" onClick={() => setNewSeason(true)}>
              + новый сезон
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function NewEpisodeForm({ season, onDone }: { season: string; onDone: () => void }) {
  const [number, setNumber] = useState('');
  const [slug, setSlug] = useState('');
  const [kk, setKk] = useState('');
  const [ru, setRu] = useState('');
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const r = await api.post('/episodes', { season_id: season, number: Number(number), slug, title_kk: kk, title_ru: ru });
      onDone();
      location.hash = `#/episode/${r.id}`;
    } catch (e) {
      toastError(e);
    }
  };
  return (
    <form className="card inline-form" onSubmit={submit}>
      <label>
        Номер
        <input value={number} onChange={(e) => setNumber(e.target.value)} placeholder="2" style={{ width: 60 }} required />
      </label>
      <label>
        Имя файла (латиницей)
        <input value={slug} onChange={(e) => setSlug(e.target.value)} placeholder="kasym_khan" required />
      </label>
      <label>
        Название kk
        <input value={kk} onChange={(e) => setKk(e.target.value)} required />
      </label>
      <label>
        Название ru
        <input value={ru} onChange={(e) => setRu(e.target.value)} required />
      </label>
      <button className="primary">Создать</button>
      <button type="button" className="link" onClick={onDone}>
        Отмена
      </button>
    </form>
  );
}

function NewSeasonForm({ onDone }: { onDone: () => void }) {
  const [id, setId] = useState('');
  const [kk, setKk] = useState('');
  const [ru, setRu] = useState('');
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api.post('/seasons', { id, title_kk: kk, title_ru: ru });
      onDone();
    } catch (e) {
      toastError(e);
    }
  };
  return (
    <form className="card inline-form" onSubmit={submit}>
      <label>
        id
        <input value={id} onChange={(e) => setId(e.target.value)} placeholder="s2" style={{ width: 60 }} required />
      </label>
      <label>
        Название kk
        <input value={kk} onChange={(e) => setKk(e.target.value)} required />
      </label>
      <label>
        Название ru
        <input value={ru} onChange={(e) => setRu(e.target.value)} required />
      </label>
      <button className="primary">Создать</button>
      <button type="button" className="link" onClick={onDone}>
        Отмена
      </button>
    </form>
  );
}
