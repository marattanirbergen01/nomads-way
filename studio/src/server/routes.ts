import { Hono } from 'hono';
import {
  requireUser, forbidUnless, createSession, setSessionCookie, clearSession, verifyPassword,
  hashPassword, permissionsOf, ROLE_TITLES, type Env, userFromRequest,
} from './auth.js';
import { all, get, run } from './db.js';
import * as S from './service.js';
import * as M from './media.js';
import { importEpisodeFile, findEpisodeFile } from './importer.js';
import { randomBytes } from 'node:crypto';
import { buildState, startBuild } from './build.js';
import { episodeToYaml, planExport, preflight, questionsToYaml } from './exporter.js';
import { pushYaml } from './push.js';

export const api = new Hono<Env>();

// ---------------------------------------------------------------- вход
api.post('/login', async (c) => {
  const { login, password } = await c.req.json();
  const u = get('SELECT * FROM users WHERE login = ?', String(login ?? '').trim().toLowerCase());
  if (!u || !verifyPassword(String(password ?? ''), u.password_hash)) {
    return c.json({ error: 'Неверный логин или пароль' }, 401);
  }
  setSessionCookie(c, createSession(u.id));
  return c.json({ ok: true });
});
api.post('/logout', (c) => {
  clearSession(c);
  return c.json({ ok: true });
});
api.get('/me', (c) => {
  const u = userFromRequest(c);
  if (!u) return c.json({ user: null });
  return c.json({ user: { ...u, roleTitle: ROLE_TITLES[u.role], permissions: permissionsOf(u) } });
});

// всё ниже — только для вошедших
api.use('*', requireUser);

// ---------------------------------------------------------------- ошибки
api.onError((err, c) => {
  if (err instanceof S.ConflictError) return c.json({ error: 'conflict', current: err.current }, 409);
  if (err instanceof S.NotFound) return c.json({ error: 'Не найдено' }, 404);
  console.error(err);
  return c.json({ error: err.message || 'Ошибка' }, 400);
});

// ---------------------------------------------------------------- серии
api.get('/episodes', (c) => c.json(S.listEpisodes()));
api.get('/episodes/:id', (c) => c.json(S.loadEpisode(c.req.param('id'))));
api.post('/episodes', async (c) => {
  const denied = forbidUnless(c, 'episode.manage');
  if (denied) return denied;
  const id = S.createEpisode(c.get('user'), await c.req.json());
  return c.json({ id });
});
api.patch('/episodes/:id', async (c) => {
  const body = await c.req.json();
  const user = c.get('user');
  // виза историка — отдельное право
  if ('approved_by' in body) {
    const denied = forbidUnless(c, 'history.approve');
    if (denied) return denied;
  } else {
    const denied = forbidUnless(c, 'episode.manage');
    if (denied) return denied;
  }
  S.updateEpisode(user, c.req.param('id'), body);
  return c.json({ ok: true });
});
api.post('/seasons', async (c) => {
  const denied = forbidUnless(c, 'episode.manage');
  if (denied) return denied;
  S.createSeason(c.get('user'), await c.req.json());
  return c.json({ ok: true });
});
api.post('/episodes/:id/reimport', (c) => {
  const denied = forbidUnless(c, 'episode.build');
  if (denied) return denied;
  const id = c.req.param('id');
  const file = findEpisodeFile(id.split('e')[0], id);
  if (!file) return c.json({ error: 'YAML серии не найден в content/' }, 404);
  const r = importEpisodeFile(file, { userId: c.get('user').id });
  S.logActivity(c.get('user'), id, 'episode.reimport', 'episode', id, r);
  return c.json(r);
});
// ---------------------------------------------------------------- сборка
api.get('/episodes/:id/preflight', (c) => c.json(preflight(c.req.param('id'))));
api.get('/episodes/:id/export', (c) => {
  const plan = planExport(c.req.param('id'));
  return c.json({ yaml: episodeToYaml(c.req.param('id')).text, questions: questionsToYaml(c.req.param('id')), files: plan.files.map((f) => f.path) });
});
// YAML → студия (агенты через CLI). Тело: { yaml, questions?, replace? }
api.post('/episodes/:id/push', async (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  const body = await c.req.json();
  if (!body.yaml) return c.json({ error: 'Нет yaml' }, 400);
  const report = pushYaml(c.get('user'), c.req.param('id'), body.yaml, { replace: !!body.replace, questionsYaml: body.questions });
  return c.json({ report });
});
// открытые комментарии в удобном для агента виде
api.get('/episodes/:id/comments/agent', (c) => {
  const id = c.req.param('id');
  const ep = S.loadEpisode(id);
  const label = (cm: any) => {
    if (cm.target_type === 'scene') return ep.scenes.find((s: any) => String(s.id) === cm.target_id)?.scene_id ?? 'scene?';
    if (cm.target_type === 'beat') {
      for (const s of ep.scenes) { const i = s.beats.findIndex((b: any) => String(b.id) === cm.target_id); if (i >= 0) return `${s.scene_id} · реплика ${i + 1} (${(s.beats[i].ru || s.beats[i].kk).slice(0, 50)})`; }
      return 'beat?';
    }
    if (cm.target_type === 'question') return ep.questions.find((q: any) => String(q.id) === cm.target_id)?.q_id ?? 'question?';
    return 'серия';
  };
  const list = S.listEpisodeComments(id, c.req.query('all') !== '1').map((cm: any) => ({ id: cm.id, where: label(cm), author: cm.author_name, role: cm.author_role, body: cm.body, resolved: !!cm.resolved, reply_to: cm.parent_id, at: cm.created_at }));
  return c.json(list);
});
api.get('/episodes/:id/build', (c) => c.json(buildState(c.req.param('id'))));
api.post('/episodes/:id/build', async (c) => {
  const denied = forbidUnless(c, 'episode.build');
  if (denied) return denied;
  const body = await c.req.json().catch(() => ({}));
  const st = startBuild(c.get('user'), c.req.param('id'), { push: body.push });
  return c.json(st);
});
api.get('/episodes/:id/activity', (c) => c.json(S.listActivity(c.req.param('id'))));
api.get('/episodes/:id/comments', (c) =>
  c.json(S.listEpisodeComments(c.req.param('id'), c.req.query('open') === '1')),
);

// ---------------------------------------------------------------- персонажи
api.put('/episodes/:id/characters', async (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  S.upsertCharacter(c.get('user'), c.req.param('id'), await c.req.json());
  return c.json({ ok: true });
});
api.delete('/episodes/:id/characters/:charId', (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  S.deleteCharacter(c.get('user'), c.req.param('id'), c.req.param('charId'));
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- сцены
api.post('/episodes/:id/scenes', async (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  const id = S.createScene(c.get('user'), c.req.param('id'), await c.req.json());
  return c.json({ id });
});
api.post('/episodes/:id/scenes/reorder', async (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  S.reorderScenes(c.get('user'), c.req.param('id'), (await c.req.json()).ids);
  return c.json({ ok: true });
});

// Какие поля сцены кому можно: текстовые — сценаристу, факты — историку, кадры — медиа.
const SCENE_FIELD_ACTION: Record<string, Parameters<typeof forbidUnless>[1]> = {
  scene_id: 'scene.edit', title_kk: 'scene.edit', title_ru: 'scene.edit', layer: 'scene.edit', note: 'scene.edit',
  avatar_side: 'scene.edit', avatar_in_art: 'scene.edit',
  covers: 'facts.edit', quiz: 'facts.edit',
  art: 'media.edit', art_when: 'media.edit', pan: 'media.edit',
  status: 'scene.status',
};
api.patch('/scenes/:id', async (c) => {
  const { version, ...patch } = await c.req.json();
  for (const k of Object.keys(patch)) {
    const action = SCENE_FIELD_ACTION[k];
    if (!action) continue;
    const denied = forbidUnless(c, action);
    if (denied) return denied;
  }
  // историческую визу сцены (text_ok) ставит историк, остальные статусы — по scene.status
  if (patch.status === 'text_ok') {
    const denied = forbidUnless(c, 'history.approve');
    if (denied) return denied;
  }
  const v = S.updateScene(c.get('user'), Number(c.req.param('id')), patch, version);
  return c.json({ version: v });
});
api.delete('/scenes/:id', (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  S.deleteScene(c.get('user'), Number(c.req.param('id')));
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- реплики
api.post('/scenes/:id/beats', async (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  const id = S.createBeat(c.get('user'), Number(c.req.param('id')), await c.req.json());
  return c.json({ id });
});
api.post('/scenes/:id/beats/reorder', async (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  S.reorderBeats(c.get('user'), Number(c.req.param('id')), (await c.req.json()).ids);
  return c.json({ ok: true });
});
api.patch('/beats/:id', async (c) => {
  const { version, ...patch } = await c.req.json();
  // «просмотрено» может поставить любой человек с правом на сцены; остальное — scene.edit
  const onlyReview = Object.keys(patch).every((k) => k === 'needs_review');
  const denied = forbidUnless(c, onlyReview ? 'scene.status' : 'scene.edit');
  if (denied) return denied;
  const v = S.updateBeat(c.get('user'), Number(c.req.param('id')), patch, version);
  return c.json({ version: v });
});
api.delete('/beats/:id', (c) => {
  const denied = forbidUnless(c, 'scene.edit');
  if (denied) return denied;
  S.deleteBeat(c.get('user'), Number(c.req.param('id')));
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- комментарии
api.get('/comments/:type/:id', (c) => c.json(S.listComments(c.req.param('type'), c.req.param('id'))));
api.post('/comments', async (c) => {
  const id = S.addComment(c.get('user'), await c.req.json());
  return c.json({ id });
});
api.patch('/comments/:id', async (c) => {
  const { resolved } = await c.req.json();
  S.resolveComment(c.get('user'), Number(c.req.param('id')), !!resolved);
  return c.json({ ok: true });
});
api.delete('/comments/:id', (c) => {
  S.deleteComment(c.get('user'), Number(c.req.param('id')));
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- медиа
api.get('/media/:season', (c) => {
  const season = c.req.param('season');
  return c.json(S.loadMedia(season).map((m) => ({ ...m, hasFile: M.hasMediaFile(season, m.id) })));
});
api.put('/media/:season/:id', async (c) => {
  const body = await c.req.json();
  const denied = forbidUnless(c, 'status' in body || 'approved_by' in body ? 'media.approve' : 'media.edit');
  if (denied) return denied;
  M.upsertMedia(c.get('user'), c.req.param('season'), c.req.param('id'), body);
  return c.json({ ok: true });
});
api.post('/media/:season/:id/upload', async (c) => {
  const denied = forbidUnless(c, 'media.edit');
  if (denied) return denied;
  const form = await c.req.formData();
  const file = form.get('file');
  if (!(file instanceof File)) return c.json({ error: 'Нет файла' }, 400);
  await M.saveUpload(c.get('user'), c.req.param('season'), c.req.param('id'), file);
  return c.json({ ok: true });
});
api.delete('/media/:season/:id', (c) => {
  const denied = forbidUnless(c, 'media.edit');
  if (denied) return denied;
  M.deleteMedia(c.get('user'), c.req.param('id'));
  return c.json({ ok: true });
});

// ---------------------------------------------------------------- пользователи (админ)
api.get('/users', (c) => {
  const denied = forbidUnless(c, 'users.manage');
  if (denied) return denied;
  return c.json(all('SELECT id, login, name, role, created_at FROM users ORDER BY id'));
});
api.post('/users', async (c) => {
  const denied = forbidUnless(c, 'users.manage');
  if (denied) return denied;
  const { login, name, role, password } = await c.req.json();
  if (!login || !name || !(role in ROLE_TITLES)) return c.json({ error: 'login, name, role обязательны' }, 400);
  run(
    'INSERT INTO users(login, name, role, password_hash) VALUES (?, ?, ?, ?)',
    String(login).trim().toLowerCase(), name, role, password ? hashPassword(password) : null,
  );
  return c.json({ ok: true });
});
api.patch('/users/:id', async (c) => {
  const denied = forbidUnless(c, 'users.manage');
  if (denied) return denied;
  const { name, role, password } = await c.req.json();
  const id = Number(c.req.param('id'));
  if (name) run('UPDATE users SET name = ? WHERE id = ?', name, id);
  if (role && role in ROLE_TITLES) run('UPDATE users SET role = ? WHERE id = ?', role, id);
  if (password) run('UPDATE users SET password_hash = ? WHERE id = ?', hashPassword(password), id);
  return c.json({ ok: true });
});
api.post('/users/:id/token', async (c) => {
  const denied = forbidUnless(c, 'users.manage');
  if (denied) return denied;
  const { label } = await c.req.json().catch(() => ({}));
  const token = randomBytes(24).toString('hex');
  run('INSERT INTO api_tokens(token, user_id, label) VALUES (?, ?, ?)', token, Number(c.req.param('id')), label ?? null);
  return c.json({ token });
});
api.delete('/users/:id', (c) => {
  const denied = forbidUnless(c, 'users.manage');
  if (denied) return denied;
  const id = Number(c.req.param('id'));
  if (id === c.get('user').id) return c.json({ error: 'Себя удалить нельзя' }, 400);
  run('DELETE FROM users WHERE id = ?', id);
  return c.json({ ok: true });
});
