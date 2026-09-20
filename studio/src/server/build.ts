// «Собрать серию»: проверки → запись в content/ → упаковка новых медиа →
// compile --check → compile + pack → git commit (+ push) → редакция в базе.
// Одна сборка за раз. Лог идёт в WebSocket и хранится, пока сервер жив.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import { config, contentDir } from './config.js';
import { all, get, run, j } from './db.js';
import { broadcast } from './ws.js';
import { planExport, preflight, writeExport } from './exporter.js';
import { loadEpisode, logActivity } from './service.js';
import type { User } from './auth.js';
import { KIND_DIR } from './media.js';

export interface BuildState {
  episodeId: string;
  running: boolean;
  ok: boolean | null;
  log: string[];
  startedAt: string;
  finishedAt?: string;
  by: string;
}

const states = new Map<string, BuildState>();
let running: string | null = null;

export function buildState(episodeId: string) {
  return states.get(episodeId) ?? null;
}

function sh(cmd: string, args: string[], cwd: string, log: (s: string) => void, env?: Record<string, string>) {
  return new Promise<number>((resolve) => {
    log(`$ ${cmd} ${args.join(' ')}`);
    const p = spawn(cmd, args, { cwd, env: { ...process.env, ...env }, shell: false });
    p.stdout.on('data', (d) => String(d).split('\n').filter(Boolean).forEach(log));
    p.stderr.on('data', (d) => String(d).split('\n').filter(Boolean).forEach((l) => log('! ' + l)));
    p.on('error', (e) => {
      log('! ' + e.message);
      resolve(127);
    });
    p.on('close', (code) => resolve(code ?? 1));
  });
}

// Упаковка одного файла по правилам tools/pack_media.sh (sips) — на любой ОС.
async function packOne(season: string, kind: string, id: string, src: string, log: (s: string) => void) {
  const out = path.join(contentDir, 'media', season, 'out');
  fs.mkdirSync(path.join(out, 'avatars'), { recursive: true });
  fs.mkdirSync(path.join(out, 'characters'), { recursive: true });
  const meta = await sharp(src).metadata();
  const maxDim = Math.max(meta.width ?? 0, meta.height ?? 0);
  const fit = (limit: number) => (maxDim > limit ? sharp(src).resize({ width: limit, height: limit, fit: 'inside', withoutEnlargement: true }) : sharp(src));
  let target: string;
  if (kind === 'map') {
    target = path.join(out, id + '.png');
    fs.copyFileSync(src, target);
  } else if (kind === 'avatar' && id.endsWith('_bust')) {
    target = path.join(out, 'avatars', id + '.png');
    await fit(960).png().toFile(target);
  } else if (kind === 'avatar') {
    target = path.join(out, 'avatars', id + '.jpg');
    await fit(512).jpeg({ quality: 82 }).toFile(target);
  } else if (kind === 'character') {
    target = path.join(out, 'characters', id + '.jpg');
    await fit(512).jpeg({ quality: 82 }).toFile(target);
  } else if (kind === 'cover' || kind === 'banner') {
    target = path.join(out, id + '.jpg');
    await fit(1600).jpeg({ quality: 82 }).toFile(target);
  } else {
    target = path.join(out, id + '.jpg');
    await fit(1920).jpeg({ quality: 82 }).toFile(target);
  }
  log(`  ${id} → ${path.relative(contentDir, target)} (${Math.round(fs.statSync(target).size / 1024)} KB)`);
  return path.relative(config.repoDir, target);
}

export function startBuild(user: User, episodeId: string, opts: { push?: boolean } = {}) {
  if (running) throw new Error(`Уже идёт сборка ${running}`);
  const ep = get('SELECT * FROM episodes WHERE id = ?', episodeId);
  if (!ep) throw new Error('Нет серии');
  const st: BuildState = { episodeId, running: true, ok: null, log: [], startedAt: new Date().toISOString(), by: user.name };
  states.set(episodeId, st);
  running = episodeId;
  const log = (s: string) => {
    st.log.push(s);
    broadcast({ type: 'build', episodeId, line: s, running: true });
  };
  const finish = (ok: boolean) => {
    st.running = false;
    st.ok = ok;
    st.finishedAt = new Date().toISOString();
    running = null;
    broadcast({ type: 'build', episodeId, line: ok ? '✓ Готово' : '✗ Сборка не удалась', running: false, ok });
    broadcast({ type: 'episode.changed', episodeId, what: 'episode', by: user.id }, { episodeId });
    broadcast({ type: 'episodes.changed' });
  };

  (async () => {
    const repo = config.repoDir;
    const written: string[] = [];
    try {
      log(`Сборка ${episodeId} — ${user.name}`);
      // 1. проверки студии
      const pf = preflight(episodeId);
      pf.warnings.forEach((w) => log('⚠ ' + w));
      if (pf.errors.length) {
        pf.errors.forEach((e) => log('✗ ' + e));
        log(`Ошибок: ${pf.errors.length}. Ничего не записано.`);
        return finish(false);
      }
      log('Проверки студии пройдены.');

      // 2. запись файлов
      const plan = planExport(episodeId);
      const existedBefore = new Set(plan.files.filter((f) => fs.existsSync(path.join(repo, f.path))).map((f) => f.path));
      written.push(...writeExport(repo, plan));
      log(`Записано файлов: ${written.length}`);
      written.forEach((f) => log('  ' + f));

      // 3. упаковка медиа, загруженных через студию
      const uploads = all('SELECT * FROM media WHERE season_id = ? AND upload IS NOT NULL', plan.season);
      if (uploads.length) {
        log(`Упаковка новых медиа: ${uploads.length}`);
        for (const m of uploads) {
          const src = path.join(repo, 'content/media', plan.season, m.file);
          if (!fs.existsSync(src)) continue;
          written.push(await packOne(plan.season, m.kind, m.id, src, log));
          // у аватара может быть и _bust
          const bust = src.replace(/(\.[a-z]+)$/, '_bust.png');
          if (m.kind === 'avatar' && fs.existsSync(bust)) written.push(await packOne(plan.season, 'avatar', m.id + '_bust', bust, log));
        }
      }

      // 4. компилятор
      const dart = process.env.DART_BIN ?? 'dart';
      const tools = path.join(repo, 'tools');
      if (!fs.existsSync(path.join(tools, '.dart_tool'))) {
        const pg = await sh(dart, ['pub', 'get'], tools, log);
        if (pg !== 0) { log('✗ dart pub get не удался'); return finish(false); }
      }
      let code = await sh(dart, ['run', 'bin/compile.dart', '--check'], tools, log);
      if (code !== 0) {
        log('✗ Компилятор нашёл ошибки. Откатываем записанные файлы.');
        const tracked = written.filter((f) => existedBefore.has(f));
        if (tracked.length) await sh('git', ['checkout', '--', ...tracked], repo, log);
        for (const f of written) if (!existedBefore.has(f)) fs.rmSync(path.join(repo, f), { force: true });
        return finish(false);
      }
      code = await sh(dart, ['run', 'bin/compile.dart'], tools, log);
      if (code !== 0) return finish(false);
      code = await sh(dart, ['run', 'bin/pack.dart'], tools, log);
      if (code !== 0) return finish(false);

      // 5. git
      const revision = (ep.revision as number) + 1;
      const msg = `studio: ${episodeId} редакция ${revision} — ${ep.title_ru} (виза: ${ep.approved_by}; сборка: ${user.name})`;
      await sh('git', ['add', '--', ...written], repo, log);
      code = await sh('git', ['commit', '-m', msg, '--', ...written], repo, log);
      let hash: string | null = null;
      if (code === 0) {
        hash = await new Promise<string>((res) => {
          const p = spawn('git', ['rev-parse', '--short', 'HEAD'], { cwd: repo });
          let o = '';
          p.stdout.on('data', (d) => (o += d));
          p.on('close', () => res(o.trim()));
        });
        log(`Коммит ${hash}`);
        if (opts.push ?? process.env.GIT_PUSH === '1') {
          const pc = await sh('git', ['push'], repo, log);
          if (pc !== 0) log('⚠ push не удался — коммит остался локально');
        }
      } else {
        log('⚠ git commit не создан (возможно, нет изменений)');
      }

      // 6. редакция и статус
      const snapshot = loadEpisode(episodeId);
      run('INSERT INTO revisions(episode_id, number, snapshot, commit_hash, created_by) VALUES (?, ?, ?, ?, ?)', episodeId, revision, j(snapshot), hash, user.id);
      run("UPDATE episodes SET revision = ?, status = 'published', updated_at = datetime('now') WHERE id = ?", revision, episodeId);
      // загруженные файлы теперь живут в content/ — отметка «загружено через студию» больше не нужна
      run('UPDATE media SET upload = NULL WHERE season_id = ? AND upload IS NOT NULL', plan.season);
      logActivity(user, episodeId, 'episode.build', 'episode', episodeId, { revision, commit: hash });
      log(`Редакция ${revision} записана.`);
      finish(true);
    } catch (e: any) {
      log('✗ ' + (e?.message ?? String(e)));
      finish(false);
    }
  })();
  return st;
}

export { KIND_DIR };
