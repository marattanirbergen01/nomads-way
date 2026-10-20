#!/usr/bin/env node
// CLI студии для окон Claude Code (агент-сценарий, агент-медиа) и людей в терминале.
//
//   studio status [s1e01]                       серии и готовность / проверки одной серии
//   studio pull s1e01 [dir]                     YAML серии и вопросов → dir (по умолчанию studio/work/s1e01/)
//   studio push s1e01 [dir] [--replace]         YAML из dir → студия (правки помечаются «от агента»)
//   studio comments s1e01 [--all]               открытые комментарии (контекст, не задание)
//   studio media list s1                        медиа сезона
//   studio media upload s1 <id> <file> [--seed N] [--brief "…"] [--prompt file.md] [--kind scene]
//   studio media set s1 <id> [--seed N] [--brief "…"] [--prompt file.md] [--note "…"]
//   studio whoami                               чей токен используется
//
// Настройка: STUDIO_URL (по умолчанию http://localhost:8795) и STUDIO_TOKEN —
// в окружении или в studio/.env. Токен выдаёт админ на странице «Команда».
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const studioRoot = path.resolve(here, '..');
// STUDIO_ENV=.env.media — токен другого агента; читается раньше .env, поэтому главнее.
const envFiles = [process.env.STUDIO_ENV, '.env'].filter(Boolean).map((f) => path.resolve(studioRoot, f));
for (const envFile of envFiles) {
  if (!fs.existsSync(envFile)) continue;
  for (const line of fs.readFileSync(envFile, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2];
  }
}
const URL_ = (process.env.STUDIO_URL ?? 'http://localhost:8795').replace(/\/$/, '');
const TOKEN = process.env.STUDIO_TOKEN;
if (!TOKEN) {
  console.error('Нет STUDIO_TOKEN. Возьмите токен у админа (Команда → API-токен) и положите в studio/.env: STUDIO_TOKEN=…');
  process.exit(2);
}

async function call(method, url, body, form) {
  const res = await fetch(URL_ + '/api' + url, {
    method,
    headers: { authorization: 'Bearer ' + TOKEN, ...(form ? {} : body ? { 'content-type': 'application/json' } : {}) },
    body: form ?? (body ? JSON.stringify(body) : undefined),
  });
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { error: text }; }
  if (!res.ok) throw new Error(`${res.status}: ${data.error ?? text}`);
  return data;
}

const args = process.argv.slice(2);
const flags = {};
const pos = [];
for (let i = 0; i < args.length; i++) {
  if (args[i].startsWith('--')) {
    const k = args[i].slice(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) flags[k] = args[++i];
    else flags[k] = true;
  } else pos.push(args[i]);
}
const [cmd, ...rest] = pos;

const STATUS = { draft: 'черновик', review: 'на утверждении', approved: 'утверждена', published: 'собрана' };

try {
  if (cmd === 'whoami') {
    const { user } = await call('GET', '/me');
    console.log(user ? `${user.login} · ${user.roleTitle} · права: ${user.permissions.join(', ') || '—'}` : 'токен не принят');
  } else if (cmd === 'status') {
    if (rest[0]) {
      const pf = await call('GET', `/episodes/${rest[0]}/preflight`);
      const ep = await call('GET', `/episodes/${rest[0]}`);
      console.log(`${ep.id} · ${ep.title_ru} · ${STATUS[ep.status]} · виза: ${ep.approved_by ?? '—'} · сцен ${ep.scenes.length}`);
      for (const s of ep.scenes) {
        const pending = s.beats.filter((b) => b.needs_review).length;
        console.log(`  ${s.scene_id.padEnd(8)} ${s.status.padEnd(9)} кадр: ${(s.art ?? '—').padEnd(22)} реплик ${String(s.beats.length).padStart(2)}${pending ? `  (ждут просмотра: ${pending})` : ''}`);
      }
      if (pf.errors.length) { console.log('\nНе готово к сборке:'); pf.errors.forEach((e) => console.log('  ✗ ' + e)); }
      if (pf.warnings.length) { console.log('\nПредупреждения:'); pf.warnings.forEach((e) => console.log('  ⚠ ' + e)); }
      if (!pf.errors.length) console.log('\n✓ Серия готова к сборке.');
    } else {
      const { episodes } = await call('GET', '/episodes');
      for (const e of episodes) console.log(`${e.id}  ${STATUS[e.status].padEnd(15)} сцен ${e.scene_count} (готово ${e.ready_count})  комментариев: ${e.open_comments}  ${e.title_ru}`);
    }
  } else if (cmd === 'pull') {
    const id = rest[0];
    if (!id) throw new Error('studio pull <episodeId> [dir]');
    const dir = rest[1] ?? path.join(studioRoot, 'work', id);
    fs.mkdirSync(dir, { recursive: true });
    const r = await call('GET', `/episodes/${id}/export`);
    fs.writeFileSync(path.join(dir, 'episode.yaml'), r.yaml);
    fs.writeFileSync(path.join(dir, 'questions.yaml'), r.questions);
    console.log(`→ ${path.join(dir, 'episode.yaml')}\n→ ${path.join(dir, 'questions.yaml')}\nПравьте эти файлы и верните: studio push ${id} ${rest[1] ? dir : ''}`.trim());
  } else if (cmd === 'push') {
    const id = rest[0];
    if (!id) throw new Error('studio push <episodeId> [dir] [--replace]');
    const dir = rest[1] ?? path.join(studioRoot, 'work', id);
    const epFile = fs.existsSync(path.join(dir, 'episode.yaml')) ? path.join(dir, 'episode.yaml') : dir.endsWith('.yaml') ? dir : null;
    if (!epFile) throw new Error('Нет episode.yaml в ' + dir);
    const qFile = path.join(path.dirname(epFile), 'questions.yaml');
    const r = await call('POST', `/episodes/${id}/push`, {
      yaml: fs.readFileSync(epFile, 'utf8'),
      questions: fs.existsSync(qFile) ? fs.readFileSync(qFile, 'utf8') : undefined,
      replace: !!flags.replace,
    });
    console.log(r.report.length ? r.report.join('\n') : 'Изменений нет.');
  } else if (cmd === 'comments') {
    const id = rest[0];
    if (!id) throw new Error('studio comments <episodeId> [--all]');
    const list = await call('GET', `/episodes/${id}/comments/agent${flags.all ? '?all=1' : ''}`);
    if (!list.length) console.log('Открытых комментариев нет.');
    for (const c of list) console.log(`${c.resolved ? '[решено] ' : ''}${c.reply_to ? '   ↳ ' : ''}[${c.where}] ${c.author} (${c.role}): ${c.body}`);
  } else if (cmd === 'media') {
    const [sub, season, id, file] = rest;
    if (sub === 'list') {
      const list = await call('GET', `/media/${season}`);
      for (const m of list) console.log(`${m.id.padEnd(30)} ${m.kind.padEnd(10)} ${m.status.padEnd(9)} ${m.hasFile ? 'файл' : '—   '}  ${m.brief ?? ''}`);
    } else if (sub === 'upload' || sub === 'set') {
      if (!season || !id) throw new Error('studio media upload <season> <id> <file> | studio media set <season> <id> --seed …');
      const patch = {};
      if (flags.seed) patch.seed = Number(flags.seed);
      if (flags.brief) patch.brief = flags.brief;
      if (flags.note) patch.note = flags.note;
      if (flags.kind) patch.kind = flags.kind;
      if (flags.prompt) patch.prompt_text = fs.readFileSync(flags.prompt, 'utf8');
      await call('PUT', `/media/${season}/${id}`, patch);
      if (sub === 'upload') {
        if (!file) throw new Error('Укажите файл');
        const form = new FormData();
        form.append('file', new Blob([fs.readFileSync(file)]), path.basename(file));
        await call('POST', `/media/${season}/${id}/upload`, undefined, form);
        console.log(`Загружено ${id} ← ${file}`);
      } else console.log('ok');
    } else throw new Error('studio media list|upload|set');
  } else {
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 13).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
  }
} catch (e) {
  console.error('✗', e.message);
  process.exit(1);
}
