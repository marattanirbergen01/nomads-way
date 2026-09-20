import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import type { Context, Next } from 'hono';
import { getCookie, setCookie, deleteCookie } from 'hono/cookie';
import { db, get, run } from './db.js';

export type Role =
  | 'admin'
  | 'writer'
  | 'historian'
  | 'media'
  | 'agent_script'
  | 'agent_media'
  | 'viewer';

export interface User {
  id: number;
  login: string;
  name: string;
  role: Role;
}

export const ROLE_TITLES: Record<Role, string> = {
  admin: 'Админ',
  writer: 'Сценарист',
  historian: 'Историк',
  media: 'Медиа',
  agent_script: 'Агент-сценарий',
  agent_media: 'Агент-медиа',
  viewer: 'Наблюдатель',
};

// --- пароли ---------------------------------------------------------------
export function hashPassword(pw: string) {
  const salt = randomBytes(16).toString('hex');
  return salt + ':' + scryptSync(pw, salt, 64).toString('hex');
}
export function verifyPassword(pw: string, stored: string | null) {
  if (!stored) return false;
  const [salt, hash] = stored.split(':');
  const a = Buffer.from(hash, 'hex');
  const b = scryptSync(pw, salt, 64);
  return a.length === b.length && timingSafeEqual(a, b);
}

// --- сессии и токены ------------------------------------------------------
const COOKIE = 'studio_session';

export function createSession(userId: number) {
  const token = randomBytes(32).toString('hex');
  run('INSERT INTO sessions(token, user_id) VALUES (?, ?)', token, userId);
  return token;
}

export function userFromRequest(c: Context): User | undefined {
  const bearer = c.req.header('authorization');
  if (bearer?.startsWith('Bearer ')) {
    const t = bearer.slice(7).trim();
    return get<User>(
      'SELECT u.id, u.login, u.name, u.role FROM api_tokens t JOIN users u ON u.id = t.user_id WHERE t.token = ?',
      t,
    );
  }
  const token = getCookie(c, COOKIE);
  if (!token) return undefined;
  return get<User>(
    'SELECT u.id, u.login, u.name, u.role FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?',
    token,
  );
}

export function setSessionCookie(c: Context, token: string) {
  setCookie(c, COOKIE, token, {
    httpOnly: true,
    sameSite: 'Lax',
    path: '/',
    maxAge: 60 * 60 * 24 * 90,
  });
}
export function clearSession(c: Context) {
  const token = getCookie(c, COOKIE);
  if (token) run('DELETE FROM sessions WHERE token = ?', token);
  deleteCookie(c, COOKIE, { path: '/' });
}

export function sessionUser(token: string): User | undefined {
  return get<User>(
    'SELECT u.id, u.login, u.name, u.role FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?',
    token,
  );
}

// --- middleware -----------------------------------------------------------
export type Env = { Variables: { user: User } };

export async function requireUser(c: Context<Env>, next: Next) {
  const user = userFromRequest(c);
  if (!user) return c.json({ error: 'Нужен вход' }, 401);
  c.set('user', user);
  await next();
}

// --- права ----------------------------------------------------------------
// Что может каждая роль. Комментировать могут все.
export type Action =
  | 'scene.edit' // текст сцен, реплики, развилки, персонажи
  | 'scene.status' // статусы сцены (кроме исторической визы)
  | 'facts.edit' // covers, quiz, вопросы
  | 'history.approve' // виза историка на сцене и серии
  | 'media.edit' // кадры, промпты, seed, загрузка файлов
  | 'media.approve'
  | 'episode.manage' // создать серию/сезон, статусы серии
  | 'episode.build' // «Собрать серию»
  | 'users.manage';

const MATRIX: Record<Role, Action[]> = {
  admin: [
    'scene.edit', 'scene.status', 'facts.edit', 'history.approve', 'media.edit',
    'media.approve', 'episode.manage', 'episode.build', 'users.manage',
  ],
  writer: ['scene.edit', 'scene.status', 'episode.manage'],
  historian: ['facts.edit', 'history.approve', 'scene.status'],
  media: ['media.edit', 'media.approve', 'scene.status'],
  agent_script: ['scene.edit', 'facts.edit'],
  agent_media: ['media.edit'],
  viewer: [],
};

export function can(user: User, action: Action) {
  return MATRIX[user.role]?.includes(action) ?? false;
}
export function isAgent(user: User) {
  return user.role === 'agent_script' || user.role === 'agent_media';
}
export function permissionsOf(user: User) {
  return MATRIX[user.role] ?? [];
}

// Проверка в маршруте: возвращает ответ 403 или undefined.
export function forbidUnless(c: Context<Env>, action: Action) {
  if (!can(c.get('user'), action)) {
    return c.json({ error: 'Нет прав: ' + action }, 403);
  }
}

export { db };
