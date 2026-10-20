// Звук раскрытия награды: синтез офлайн, без сэмплов. node audio.mjs <папка>
// Пишет award0..3.wav (48 кГц, стерео, 16 бит), события — из timeline.js.
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
await import(pathToFileURL(resolve(here, 'timeline.js')).href);
const TL = globalThis.TL, SR = 48000, N = Math.round(TL.DUR * SR);
const outDir = process.argv[2] || resolve(here, 'out'); mkdirSync(outDir, { recursive: true });

const hz = (n) => 440 * Math.pow(2, (n - 69) / 12);       // MIDI → Гц
let seed = 7; const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296) * 2 - 1;

function bus() { return { L: new Float32Array(N), R: new Float32Array(N) }; }
function add(b, t0, sig, gain = 1, pan = 0) {          // pan −1..1, равная мощность
  const s0 = Math.round(t0 * SR), gl = gain * Math.cos((pan + 1) * Math.PI / 4), gr = gain * Math.sin((pan + 1) * Math.PI / 4);
  for (let i = 0; i < sig.length; i++) { const j = s0 + i; if (j < 0 || j >= N) continue; b.L[j] += sig[i] * gl; b.R[j] += sig[i] * gr; }
}
const env = (n, a, r) => (i) => Math.min(1, i / (a * SR)) * Math.exp(-i / (r * SR));

// домбра: Karplus–Strong с мягким телом
function pluck(f, dur = 2.2, bright = 0.5) {
  const n = Math.round(dur * SR), p = Math.max(2, Math.round(SR / f)), buf = new Float32Array(p), o = new Float32Array(n);
  for (let i = 0; i < p; i++) buf[i] = rnd() * (0.6 + 0.4 * bright);
  let lp = 0, k = 0;
  for (let i = 0; i < n; i++) {
    const a = buf[k], b = buf[(k + 1) % p], v = 0.5 * (a + b) * 0.996;
    buf[k] = v; k = (k + 1) % p; lp += (a - lp) * 0.35; o[i] = lp * Math.min(1, i / 40);
  }
  return o;
}
// колокольчик: неровные партиалы, быстрый спад верхних
function bell(f, dur = 2) {
  const n = Math.round(dur * SR), o = new Float32Array(n), P = [[1, 1, 1.6], [2.01, 0.42, 1.0], [2.76, 0.3, 0.7], [4.07, 0.14, 0.45], [5.43, 0.07, 0.3]];
  for (let i = 0; i < n; i++) { const t = i / SR; let v = 0; for (const [m, a, d] of P) v += a * Math.sin(2 * Math.PI * f * m * t) * Math.exp(-t / d); o[i] = v * Math.min(1, i / 120); }
  return o;
}
// тёплая нота пэда: несколько гармоник, два расстроенных голоса
function padNote(f, dur, att, rel) {
  const n = Math.round(dur * SR), o = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const t = i / SR, e = Math.min(1, t / att) * Math.min(1, Math.max(0, (dur - t) / rel)); let v = 0;
    for (let h = 1; h <= 6; h++) { const a = 1 / Math.pow(h, 1.8); v += a * (Math.sin(2 * Math.PI * f * h * t * 1.0015) + Math.sin(2 * Math.PI * f * h * t * 0.9985 + h)); }
    o[i] = v * e * 0.5;
  }
  return o;
}
// шум через полосовой фильтр с движущейся частотой (скан, вжух)
function sweep(dur, f0, f1, q, shape) {
  const n = Math.round(dur * SR), o = new Float32Array(n); let low = 0, band = 0;
  for (let i = 0; i < n; i++) {
    const u = i / n, f = f0 * Math.pow(f1 / f0, u), fc = 2 * Math.sin(Math.PI * Math.min(0.45, f / SR));
    const x = rnd(); low += fc * band; const high = x - low - band / q; band += fc * high;
    o[i] = band * shape(u);
  }
  return o;
}
function tone(dur, f0, f1, a = 0.02) {
  const n = Math.round(dur * SR), o = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const u = i / n; ph += 2 * Math.PI * (f0 * Math.pow(f1 / f0, u)) / SR; o[i] = Math.sin(ph) * Math.sin(Math.PI * u) ** 2 * Math.min(1, i / (a * SR)); }
  return o;
}
function tick(f = 3200, d = 0.03) { const n = Math.round(d * SR), o = new Float32Array(n); for (let i = 0; i < n; i++) o[i] = (Math.sin(2 * Math.PI * f * i / SR) * 0.7 + rnd() * 0.3) * Math.exp(-i / (0.006 * SR)); return o; }
function thump() { const n = Math.round(0.5 * SR), o = new Float32Array(n); let ph = 0; for (let i = 0; i < n; i++) { const t = i / SR; ph += 2 * Math.PI * (46 + 50 * Math.exp(-t / 0.05)) / SR; o[i] = Math.sin(ph) * Math.exp(-t / 0.16) * Math.min(1, i / 60); } return o; }

// реверберация: 4 гребёнки + 2 фазовращателя на канал
function reverb(x, spread) {
  const y = new Float32Array(N), combs = [1557, 1617, 1491, 1422].map((d) => d + spread), aps = [225, 556].map((d) => d + spread);
  for (const d of combs) { const buf = new Float32Array(d); let k = 0, lp = 0; for (let i = 0; i < N; i++) { const o = buf[k]; lp = o * 0.6 + lp * 0.4; buf[k] = x[i] + lp * 0.78; k = (k + 1) % d; y[i] += o * 0.25; } }
  for (const d of aps) { const buf = new Float32Array(d); let k = 0; for (let i = 0; i < N; i++) { const b = buf[k], v = y[i] + b * 0.5; buf[k] = v; y[i] = b - v * 0.5; k = (k + 1) % d; } }
  return y;
}

const D = 62, A = 69, E = 64;   // ре-дорийский: D4, A4, E4
for (let award = 0; award < 4; award++) {
  seed = 7 + award;
  const dry = bus(), wet = bus();
  // подложка: низкий бурдон D–A, растёт к подтверждению
  add(dry, 0, padNote(hz(D - 24), TL.DUR, 1.2, 0.5), 0.05); add(dry, 0, padNote(hz(A - 24), TL.DUR, 1.2, 0.5), 0.035);
  // горизонт прорисовывается: воздушный тон
  add(wet, TL.draw[0], tone(0.6, 700, 1050, 0.08), 0.05, 0);
  add(wet, TL.draw[0], sweep(0.6, 2500, 6000, 3, (u) => Math.sin(Math.PI * u) * 0.6), 0.05, 0);
  // сворачивание в кольцо: мягкий вжух и подъём
  add(dry, TL.curl[0], sweep(TL.curl[1] - TL.curl[0] + 0.15, 300, 1400, 1.2, (u) => Math.pow(Math.sin(Math.PI * u), 2)), 0.11, -0.2);
  add(wet, TL.curl[0] + 0.1, tone(0.55, 220, 330, 0.1), 0.04);
  add(dry, TL.curl[1] - 0.03, tick(2400, 0.04), 0.05, 0.1);                  // кольцо замкнулось
  add(wet, TL.inner[0], tone(0.4, 1320, 1180, 0.05), 0.02, 0.2);
  // бирюзовый скан снизу вверх
  add(wet, TL.scan[0], sweep(TL.scan[1] - TL.scan[0] + 0.05, 1200, 5200, 6, (u) => Math.sin(Math.PI * u) ** 1.5), 0.12, 0);
  // детали
  if (award === 0) for (let k = 0; k < 20; k++) add(dry, TL.detail[0] + (TL.detail[1] - 0.12 - TL.detail[0]) * k / 19, tick(3400 + k * 40, 0.025), 0.03, Math.sin(k * Math.PI / 10) * 0.6);
  if (award === 1) for (let k = 0; k < 15; k++) add(dry, TL.detail[0] + (TL.detail[1] - TL.detail[0]) * eio(k / 14), tick(2600, 0.02), 0.025, -0.6 + 1.2 * k / 14);
  if (award === 2) add(wet, TL.detail[0], sweep(0.35, 3000, 1800, 2, (u) => Math.sin(Math.PI * u)), 0.05, 0);
  if (award === 3) [62, 65, 67, 69, 72, 74, 76].forEach((n, k) => add(wet, TL.detail[0] + (TL.detail[1] - 0.06 - TL.detail[0]) * k / 6, pluck(hz(n), 1.2, 0.35), 0.06, -0.5 + k / 6));
  // подтверждение: домбра (кварта-квинта), колокольчик, мягкий удар, аккорд
  const h = TL.hit;
  add(dry, h, pluck(hz(D - 12), 2, 0.6), 0.2, -0.15); add(dry, h + 0.012, pluck(hz(A - 12), 2, 0.6), 0.16, 0.15);
  add(wet, h + 0.02, pluck(hz(D), 1.8, 0.45), 0.1, 0.05);
  add(wet, h, bell(hz(D + 24), 1.4), 0.05, 0.1); add(wet, h + 0.09, bell(hz(A + 12), 1.3), 0.035, -0.1);
  add(dry, h, thump(), 0.32);
  for (const [n, g] of [[D - 12, 0.06], [A - 12, 0.05], [E, 0.035], [A, 0.025]]) add(wet, h - 0.05, padNote(hz(n), TL.DUR - h + 0.05, 0.35, 0.6), g);

  const wl = reverb(wet.L, 0), wr = reverb(wet.R, 23), L = new Float32Array(N), R = new Float32Array(N);
  for (let i = 0; i < N; i++) { L[i] = dry.L[i] + wet.L[i] * 0.8 + wl[i] * 0.5; R[i] = dry.R[i] + wet.R[i] * 0.8 + wr[i] * 0.5; }
  // мастер: нормировка к −1,5 dBFS, мягкое ограничение, затухание хвоста (последние 0,3 с)
  let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  const g = Math.pow(10, -1.5 / 20) / peak, fadeN = Math.round(0.3 * SR);
  const pcm = Buffer.alloc(N * 4);
  for (let i = 0; i < N; i++) {
    const f = i > N - fadeN ? Math.pow((N - i) / fadeN, 2) : 1, fi = Math.min(1, i / 96);
    const l = Math.tanh(L[i] * g * 1.05) * f * fi, r = Math.tanh(R[i] * g * 1.05) * f * fi;
    pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, l + rnd() * 1.5e-5)) * 32767), i * 4);
    pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, r + rnd() * 1.5e-5)) * 32767), i * 4 + 2);
  }
  const hd = Buffer.alloc(44);
  hd.write('RIFF', 0); hd.writeUInt32LE(36 + pcm.length, 4); hd.write('WAVEfmt ', 8); hd.writeUInt32LE(16, 16); hd.writeUInt16LE(1, 20); hd.writeUInt16LE(2, 22);
  hd.writeUInt32LE(SR, 24); hd.writeUInt32LE(SR * 4, 28); hd.writeUInt16LE(4, 32); hd.writeUInt16LE(16, 34); hd.write('data', 36); hd.writeUInt32LE(pcm.length, 40);
  writeFileSync(resolve(outDir, `award${award}.wav`), Buffer.concat([hd, pcm]));
  console.log(`award${award}.wav  peak до нормировки ${peak.toFixed(3)}`);
}
function eio(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
