// Покадровый рендер через headless Chrome (CDP, без зависимостей).
// node render.mjs <папка_кадров> <award 0..3> [кадр,кадр,...]
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [outDir, awardArg = '0', only] = process.argv.slice(2);
const award = +awardArg;
mkdirSync(outDir, { recursive: true });
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9300 + award;
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${resolve(outDir, '..', `.chrome${award}`)}`,
  '--allow-file-access-from-files', '--force-device-scale-factor=1', '--window-size=1080,1920', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws;
for (let i = 0; i < 60; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const page = list.find((p) => p.type === 'page'); if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
  } catch {}
  await sleep(200);
}
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let id = 0; const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
const ev = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails).slice(0, 800));
  return r.result.result.value;
};

await send('Page.enable');
await send('Page.navigate', { url: `file://${here}/index.html?render&award=${award}` });
for (let i = 0; i < 100; i++) { if (await ev('typeof globalThis.ready === "object"').catch(() => false)) break; await sleep(100); }
await ev('globalThis.ready');
const total = Math.round(await ev('TL.DUR * TL.FPS'));
const frames = only ? only.split(',').map(Number) : [...Array(total).keys()];
const t0 = Date.now();
for (const f of frames) {
  const url = await ev(`renderFrame(${f})`);
  writeFileSync(resolve(outDir, `f${String(f).padStart(5, '0')}.png`), Buffer.from(url.split(',')[1], 'base64'));
}
console.log(`award ${award}: ${frames.length} кадров за ${((Date.now() - t0) / 1000).toFixed(1)} с`);
ws.close(); chrome.kill();
