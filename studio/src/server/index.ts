import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { serveStatic } from '@hono/node-server/serve-static';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { api } from './routes.js';
import { attachWs } from './ws.js';
import { resolveMediaFile } from './media.js';
import { get, run } from './db.js';
import { hashPassword } from './auth.js';
import { episodeCount, importAll } from './importer.js';

const app = new Hono();

app.route('/api', api);

// Картинки: /media/<season>/<id> — без расширения, студия сама найдёт файл.
app.get('/media/:season/:id', (c) => {
  const file = resolveMediaFile(c.req.param('season'), c.req.param('id').replace(/\.[a-z]+$/, ''));
  if (!file) return c.text('нет файла', 404);
  const ext = path.extname(file).slice(1);
  const type = ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
  c.header('Content-Type', type);
  c.header('Cache-Control', 'private, max-age=60');
  return c.body(fs.readFileSync(file));
});

// Собранный фронтенд (dist/), в dev его отдаёт vite.
const dist = path.join(config.studioRoot, 'dist');
if (fs.existsSync(dist)) {
  app.use('/assets/*', serveStatic({ root: path.relative(process.cwd(), dist) }));
  app.get('*', (c) => c.html(fs.readFileSync(path.join(dist, 'index.html'), 'utf8')));
} else {
  app.get('*', (c) => c.text('Студия: фронтенд не собран. npm run build или npm run dev.', 200));
}

// Первый запуск: пустая база → импортируем content/ и создаём админа.
if (episodeCount() === 0) {
  const r = importAll();
  if (r.length) console.log('Импортировано из content/:', r.map((x) => x.episodeId).join(', '));
}
if (!get('SELECT id FROM users LIMIT 1')) {
  const pw = process.env.ADMIN_PASSWORD ?? 'admin';
  run("INSERT INTO users(login, name, role, password_hash) VALUES ('admin', 'Марат', 'admin', ?)", hashPassword(pw));
  console.log(`Создан пользователь admin (пароль: ${pw === 'admin' ? 'admin — смените!' : 'из ADMIN_PASSWORD'})`);
}

const server = serve({ fetch: app.fetch, port: config.port }, (info) => {
  console.log(`Студия: http://localhost:${info.port}  (repo: ${config.repoDir}, data: ${config.dataDir})`);
});
attachWs(server as any);
