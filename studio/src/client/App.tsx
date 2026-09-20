import { createContext, useContext, useEffect, useState } from 'react';
import { api } from './api';
import type { Me } from './types';
import { connectLive, disconnectLive, useOnline } from './live';
import { LoginPage } from './pages/Login';
import { EpisodesPage } from './pages/Episodes';
import { EpisodePage } from './pages/Episode';
import { MediaPage } from './pages/Media';
import { UsersPage } from './pages/Users';
import { ToastHost } from './components/Toast';

export const MeContext = createContext<Me>(null as any);
export const useMe = () => useContext(MeContext);
export const can = (me: Me, p: string) => me.permissions.includes(p);

// Маршруты по hash: #/ , #/episode/s1e01 , #/media/s1 , #/users
function useRoute() {
  const [hash, setHash] = useState(location.hash);
  useEffect(() => {
    const h = () => setHash(location.hash);
    addEventListener('hashchange', h);
    return () => removeEventListener('hashchange', h);
  }, []);
  const parts = hash.replace(/^#\/?/, '').split('/').filter(Boolean);
  return { parts, hash };
}
export const go = (path: string) => {
  location.hash = path;
};

export function App() {
  const [me, setMe] = useState<Me | null | undefined>(undefined);
  const { parts } = useRoute();

  const refreshMe = () => api.get('/me').then((r) => setMe(r.user));
  useEffect(() => {
    refreshMe();
  }, []);
  useEffect(() => {
    if (me) connectLive();
    else disconnectLive();
  }, [!!me]);

  if (me === undefined) return <div className="center muted">Загрузка…</div>;
  if (!me) return <LoginPage onLogin={refreshMe} />;

  let page;
  if (parts[0] === 'episode' && parts[1]) page = <EpisodePage id={parts[1]} sceneKey={parts[2]} />;
  else if (parts[0] === 'media') page = <MediaPage season={parts[1] ?? 's1'} />;
  else if (parts[0] === 'users') page = <UsersPage />;
  else page = <EpisodesPage />;

  return (
    <MeContext.Provider value={me}>
      <TopBar me={me} onLogout={() => api.post('/logout').then(() => setMe(null))} />
      {page}
      <ToastHost />
    </MeContext.Provider>
  );
}

function TopBar({ me, onLogout }: { me: Me; onLogout: () => void }) {
  const online = useOnline();
  return (
    <header className="topbar">
      <a href="#/" className="brand">
        <span className="brand-dot" /> Nomad's Way · Студия
      </a>
      <nav>
        <a href="#/">Серии</a>
        <a href="#/media/s1">Медиа</a>
        {me.permissions.includes('users.manage') && <a href="#/users">Команда</a>}
      </nav>
      <div className="spacer" />
      <span className={'dot ' + (online ? 'on' : 'off')} title={online ? 'Связь есть' : 'Нет связи, переподключение…'} />
      <span className="me">
        {me.name} <span className="muted">· {me.roleTitle}</span>
      </span>
      <button className="link" onClick={onLogout}>
        Выйти
      </button>
    </header>
  );
}
