// Покадровый рендер через headless Chrome (CDP, без зависимостей).
// node render.mjs <папка_кадров> <route|south> <kk|ru> [кадр,кадр,...]
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const [outDir, map = "route", lang = "kk", only] = process.argv.slice(2);
const tag = `${map}_${lang}`;
mkdirSync(outDir, { recursive: true });
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const port = 9400 + (map === "south" ? 2 : 0) + (lang === "ru" ? 1 : 0);
const chrome = spawn(CHROME, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${resolve(outDir, '..', `.chrome_${tag}`)}`,
  '--allow-file-access-from-files', '--force-device-scale-factor=1', '--window-size=1080,1890', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });

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
await send('Page.navigate', { url: `file://${here}/index.html?render&map=${map}&lang=${lang}` });
for (let i = 0; i < 100; i++) { if (await ev('typeof globalThis.ready === "object"').catch(() => false)) break; await sleep(100); }
await ev('globalThis.ready');
const total = Math.round(await ev('TL.DUR * TL.FPS'));
const frames = only ? only.split(',').map(Number) : [...Array(total).keys()];
const t0 = Date.now();
for (const f of frames) {
  const url = await ev(`renderFrame(${f})`);
  writeFileSync(resolve(outDir, `f${String(f).padStart(5, '0')}.png`), Buffer.from(url.split(',')[1], 'base64'));
}
if (process.env.BOXES) {   // рамки подписей последнего кадра → проверка полей
  const boxes = await ev('(() => { globalThis.BOXES = []; renderAt(TL.DUR); const b = globalThis.BOXES; globalThis.BOXES = null; return b; })()');
  let bad = 0;
  for (const b of boxes) {
    if (b.text.trim().length < 2) continue;
    const e = []; if (b.x0 < 64) e.push('лево'); if (b.x1 > 1016) e.push('право'); if (b.y0 < 1890 * 0.08) e.push('верх'); if (b.y1 > 1890 * 0.6) e.push('низ');
    bad += e.length; console.log(`${e.length ? '✗' : '✓'} ${b.text.padEnd(22)} x ${b.x0}–${b.x1}  y ${b.y0}–${b.y1} ${e.join(',')}`);
  }
  console.log(bad ? `нарушений: ${bad}` : 'все подписи в зоне: поля ≥ 64 px, ниже 8 %, выше 60 %');
}
console.log(`${tag}: ${frames.length} кадров за ${((Date.now() - t0) / 1000).toFixed(1)} с`);
ws.close(); chrome.kill();
