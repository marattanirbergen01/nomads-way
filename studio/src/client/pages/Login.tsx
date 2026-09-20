import { useState } from 'react';
import { api } from '../api';

export function LoginPage({ onLogin }: { onLogin: () => void }) {
  const [login, setLogin] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setErr('');
    try {
      await api.post('/login', { login, password });
      onLogin();
    } catch (e: any) {
      setErr(e.message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="center">
      <form className="card login" onSubmit={submit}>
        <h1>
          <span className="brand-dot" /> Nomad's Way · Студия
        </h1>
        <label>
          Логин
          <input autoFocus value={login} onChange={(e) => setLogin(e.target.value)} autoComplete="username" />
        </label>
        <label>
          Пароль
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
        </label>
        {err && <div className="error">{err}</div>}
        <button className="primary" disabled={busy}>
          Войти
        </button>
      </form>
    </div>
  );
}
