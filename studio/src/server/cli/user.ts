// npm run user -- add <login> <role> "<Имя>" <пароль>
// npm run user -- token <login> "<метка>"      — API-токен (для агентов)
// npm run user -- list
import { randomBytes } from 'node:crypto';
import { all, get, run } from '../db.js';
import { hashPassword, ROLE_TITLES } from '../auth.js';

const [cmd, ...a] = process.argv.slice(2);
if (cmd === 'add') {
  const [login, role, name, password] = a;
  if (!login || !role || !name) {
    console.error('use: add <login> <role> "<Имя>" [пароль]'); process.exit(1);
  }
  if (!(role in ROLE_TITLES)) { console.error('роли:', Object.keys(ROLE_TITLES).join(' ')); process.exit(1); }
  run('INSERT INTO users(login, name, role, password_hash) VALUES (?, ?, ?, ?) ON CONFLICT(login) DO UPDATE SET role=excluded.role, name=excluded.name, password_hash=COALESCE(excluded.password_hash, users.password_hash)',
    login, name, role, password ? hashPassword(password) : null);
  console.log('ok', login, role);
} else if (cmd === 'token') {
  const [login, label] = a;
  const u = get<{ id: number }>('SELECT id FROM users WHERE login = ?', login);
  if (!u) { console.error('нет пользователя', login); process.exit(1); }
  const token = randomBytes(24).toString('hex');
  run('INSERT INTO api_tokens(token, user_id, label) VALUES (?, ?, ?)', token, u.id, label ?? null);
  console.log(token);
} else {
  for (const u of all('SELECT id, login, name, role FROM users ORDER BY id')) console.log(u);
}
