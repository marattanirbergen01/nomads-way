import { useEffect, useState } from 'react';
import { api } from '../api';
import { ROLE_TITLES, type Role } from '../types';
import { toast, toastError } from '../components/Toast';

interface U { id: number; login: string; name: string; role: Role; created_at: string }

const ROLE_HELP: Record<Role, string> = {
  admin: 'всё, включая сборку серии и команду',
  writer: 'сцены, реплики, развилки, персонажи; статусы сцен',
  historian: 'факты (covers), вопросы, виза на текст сцены и серию',
  media: 'кадры, промпты, загрузка и утверждение медиа',
  agent_script: 'как сценарист + факты; правки помечаются «предложено агентом»',
  agent_media: 'как медиа, без утверждения',
  viewer: 'только смотреть и комментировать',
};

export function UsersPage() {
  const [users, setUsers] = useState<U[]>([]);
  const [f, setF] = useState({ login: '', name: '', role: 'writer' as Role, password: '' });
  const load = () => api.get<U[]>('/users').then(setUsers).catch(toastError);
  useEffect(() => {
    load();
  }, []);

  const add = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await api.post('/users', f);
      setF({ login: '', name: '', role: 'writer', password: '' });
      toast('Пользователь создан');
      load();
    } catch (e) {
      toastError(e);
    }
  };
  const setRole = (u: U, role: Role) => api.patch(`/users/${u.id}`, { role }).then(load).catch(toastError);
  const setPassword = (u: U) => {
    const password = prompt(`Новый пароль для ${u.login}`);
    if (password) api.patch(`/users/${u.id}`, { password }).then(() => toast('Пароль изменён')).catch(toastError);
  };
  const token = async (u: U) => {
    const label = prompt('Метка токена (например, «окно Контент на Mac Марата»)') ?? '';
    try {
      const r = await api.post(`/users/${u.id}/token`, { label });
      prompt('API-токен (скопируйте, больше не покажем):', r.token);
    } catch (e) {
      toastError(e);
    }
  };
  const del = (u: U) => confirm(`Удалить ${u.login}?`) && api.del(`/users/${u.id}`).then(load).catch(toastError);

  return (
    <div className="page">
      <h2>Команда</h2>
      <table className="table">
        <thead><tr><th>Логин</th><th>Имя</th><th>Роль</th><th></th></tr></thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id}>
              <td><span className="code">{u.login}</span></td>
              <td>{u.name}</td>
              <td>
                <select value={u.role} onChange={(e) => setRole(u, e.target.value as Role)}>
                  {(Object.keys(ROLE_TITLES) as Role[]).map((r) => <option key={r} value={r}>{ROLE_TITLES[r]}</option>)}
                </select>
              </td>
              <td>
                <button className="link" onClick={() => setPassword(u)}>пароль</button>
                {u.role.startsWith('agent') && <button className="link" onClick={() => token(u)}>API-токен</button>}
                <button className="link danger" onClick={() => del(u)}>удалить</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      <form className="card inline-form" onSubmit={add}>
        <label>Логин<input value={f.login} onChange={(e) => setF({ ...f, login: e.target.value })} required /></label>
        <label>Имя<input value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} required /></label>
        <label>Роль
          <select value={f.role} onChange={(e) => setF({ ...f, role: e.target.value as Role })}>
            {(Object.keys(ROLE_TITLES) as Role[]).map((r) => <option key={r} value={r}>{ROLE_TITLES[r]}</option>)}
          </select>
        </label>
        <label>Пароль<input value={f.password} onChange={(e) => setF({ ...f, password: e.target.value })} placeholder="для агентов не нужен" /></label>
        <button className="primary">Добавить</button>
      </form>
      <h4>Что может каждая роль</h4>
      <ul className="small">
        {(Object.keys(ROLE_HELP) as Role[]).map((r) => <li key={r}><b>{ROLE_TITLES[r]}</b> — {ROLE_HELP[r]}. Комментировать могут все.</li>)}
      </ul>
    </div>
  );
}
