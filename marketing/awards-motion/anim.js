'use strict';
// Nomad's Way — раскрытие награды, 2,6 с. Управляемый таймлайн: renderAt(t) детерминирован.
// ?award=0..3 — какая награда; ?t=секунды — стоп-кадр; ?render — режим покадрового экспорта.
(() => {
const W = 1080, H = 1920, F = 1500;
const TL = globalThis.TL;
const C = {
  bg: '#1A1410', line: '#3A2D21',
  ink: '#F4ECDF', inkSoft: '#B8A68F', inkFaint: '#9D8C75', warm: '#E8D9BD',
  gold: '#D9A441', goldBright: '#F1C453', goldDark: '#8E6E1E', goldDim: '#57472F',
  medal: '#2F241B', turq: '#4FA7A0', turqBright: '#86CFC6',
};

// ---------- время и кривые ----------
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const eio = (t) => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
const eioS = (t) => -(Math.cos(Math.PI * t) - 1) / 2;
const prog = (t, a, b) => clamp((t - a) / (b - a));
const ep = (t, a, b, e = eio) => e(prog(t, a, b));
const pulse = (t, t0, dur = 0.9) => {
  if (t < t0 || t > t0 + dur) return 0;
  const x = t - t0;
  return x < 0.14 ? eioS(x / 0.14) : 1 - eio((x - 0.14) / (dur - 0.14));
};

// ---------- холсты ----------
const outC = document.getElementById('c'); outC.width = W; outC.height = H;
const out = outC.getContext('2d');
const mk = () => { const c = document.createElement('canvas'); c.width = W; c.height = H; return c; };
const frameC = mk(), fctx = frameC.getContext('2d');
const glowC = mk(), gctx = glowC.getContext('2d');
const noiseC = document.createElement('canvas'); noiseC.width = noiseC.height = 512;
{
  const n = noiseC.getContext('2d'), id = n.createImageData(512, 512); let s = 20261021;
  for (let i = 0; i < id.data.length; i += 4) {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    const v = 128 + ((s >>> 16) & 255) / 255 * 56 - 28;
    id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255;
  }
  n.putImageData(id, 0, 0);
}

// ---------- камера: непрерывный dolly-in с дугой и креном ----------
const cam = { cx: 0, cy: 0, cz: -1500, c: 1, s: 0 };
function setCam(t) {
  const u = t / TL.DUR, e = eioS(u);
  cam.cx = lerp(70, -20, e) + 18 * Math.sin(u * Math.PI);
  cam.cy = lerp(90, -10, e);
  cam.cz = lerp(-1720, -1440, 1 - Math.pow(1 - u, 2.2));
  const r = lerp(-1.4, 0.35, e) * Math.PI / 180; cam.c = Math.cos(r); cam.s = Math.sin(r);
}
function project(p) {
  const s = F / (p[2] - cam.cz);
  const x = (p[0] - cam.cx) * s, y = (p[1] - cam.cy) * s;
  return [W / 2 + x * cam.c - y * cam.s, H / 2 + x * cam.s + y * cam.c, s];
}

// ---------- геометрия ----------
const NP = 64, K = 16;
function resample(pts, n) {
  const L = [0];
  for (let i = 1; i < pts.length; i++) L.push(L[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
  const T = L[L.length - 1] || 1, o = []; let j = 0;
  for (let k = 0; k < n; k++) {
    const s = T * k / (n - 1);
    while (j < L.length - 2 && L[j + 1] < s) j++;
    const u = (s - L[j]) / ((L[j + 1] - L[j]) || 1);
    o.push([lerp(pts[j][0], pts[j + 1][0], u), lerp(pts[j][1], pts[j + 1][1], u)]);
  }
  return o;
}
const arc = (cx, cy, r, a0, sw, n = 96) => Array.from({ length: n + 1 }, (_, i) => { const a = a0 + sw * i / n; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; });
const seg = (x0, y0, x1, y1) => [[x0, y0], [x1, y1]];
const bez = (p0, c, p1, n = 40) => Array.from({ length: n + 1 }, (_, i) => { const u = i / n, a = (1 - u) * (1 - u), b = 2 * u * (1 - u), d = u * u; return [a * p0[0] + b * c[0] + d * p1[0], a * p0[1] + b * c[1] + d * p1[1]]; });
const S = (pts, o = {}) => ({ pts: resample(pts, NP), w: o.w || 1, closed: !!o.closed });
const dot = (p) => ({ pts: Array.from({ length: NP }, () => [p[0], p[1]]), w: 1, closed: false, deg: true });
const circ = (cx, cy, r, o = {}) => S(arc(cx, cy, r, -Math.PI / 2, Math.PI * 2), { ...o, closed: true });
function pad(g) {
  const o = g.slice(); let m = 0;
  while (o.length < K) { const src = g[m % g.length]; o.push(dot(src.pts[(m * 23 + 11) % NP])); m++; }
  return o;
}
const strokeLen = (p) => { let l = 0; for (let i = 1; i < p.length; i++) l += Math.hypot(p[i][0] - p[i - 1][0], p[i][1] - p[i - 1][1]); return l; };

// Знаки наград (по иконкам приложения). Единица — внешний радиус медали.
const G = {};
G.mergen = pad([
  circ(0, 0, 0.34), circ(0, 0, 0.07, { w: 2.2 }),
  S(seg(0, -0.54, 0, -0.2)), S(seg(0, 0.2, 0, 0.54)), S(seg(-0.54, 0, -0.2, 0)), S(seg(0.2, 0, 0.54, 0)),
]);
G.kosh = pad([
  S(seg(-0.5, 0.3, 0.5, 0.3)),
  S(seg(-0.4, 0.3, -0.4, 0.02)), S(seg(0.4, 0.3, 0.4, 0.02)),
  S(bez([-0.4, 0.02], [-0.36, -0.28], [-0.07, -0.33])), S(bez([0.4, 0.02], [0.36, -0.28], [0.07, -0.33])),
  circ(0, -0.34, 0.07),
  S([[-0.1, 0.3], [-0.1, 0.1], [0.1, 0.1], [0.1, 0.3]]),
  S(seg(-0.4, 0.3, -0.13, 0.03)), S(seg(-0.4, 0.03, -0.13, 0.3)),
  S(seg(0.4, 0.3, 0.13, 0.03)), S(seg(0.4, 0.03, 0.13, 0.3)),
  S(seg(-0.05, -0.28, -0.24, 0.02)), S(seg(0.05, -0.28, 0.24, 0.02)),
]);
G.book = [
  S(bez([-0.48, 0.06], [-0.24, -0.02], [0, 0.08])), S(bez([0.48, 0.06], [0.24, -0.02], [0, 0.08])),
  S(bez([-0.48, 0.36], [-0.24, 0.28], [0, 0.38])), S(bez([0.48, 0.36], [0.24, 0.28], [0, 0.38])),
  S(seg(-0.48, 0.06, -0.48, 0.36)), S(seg(0.48, 0.06, 0.48, 0.36)), S(seg(0, 0.08, 0, 0.38)),
  S(bez([-0.38, 0.16], [-0.22, 0.11], [-0.08, 0.18])), S(bez([-0.38, 0.25], [-0.22, 0.2], [-0.08, 0.27])),
  S(bez([0.38, 0.16], [0.22, 0.11], [0.08, 0.18])), S(bez([0.38, 0.25], [0.22, 0.2], [0.08, 0.27])),
  S(seg(0, 0.08, 0, -0.14)),
  S(bez([0, -0.14], [-0.02, -0.26], [-0.2, -0.3])), S(bez([0, -0.14], [0.02, -0.26], [0.2, -0.3])),
  S(arc(-0.25, -0.31, 0.05, 0, Math.PI * 2), { closed: true }), S(arc(0.25, -0.31, 0.05, Math.PI, Math.PI * 2), { closed: true }),
];
G.sun = pad([circ(0, 0, 0.2)].concat(Array.from({ length: 7 }, (_, k) => {
  const a = -Math.PI / 2 + k * 2 * Math.PI / 7;
  return S(seg(0.3 * Math.cos(a), 0.3 * Math.sin(a), 0.45 * Math.cos(a), 0.45 * Math.sin(a)));
})));
// исходная форма: круг r=0,5, разрезанный на K дуг — из него морфится любой знак
G.seed = Array.from({ length: K }, (_, k) => S(arc(0, 0, 0.5, -Math.PI / 2 + k * 2 * Math.PI / K, 2 * Math.PI / K * 0.98, 12)));

// Морфинг: каждому штриху A — ближайший штрих B, с выбором направления и сдвига начала.
function cost(a, b) { let s = 0; for (let i = 0; i < NP; i += 4) s += Math.hypot(a[i][0] - b[i][0], a[i][1] - b[i][1]); return s; }
function rot(p, sh) { const r = p.slice(0, NP - 1); const o = r.slice(sh).concat(r.slice(0, sh)); o.push(o[0]); return o; }
function orient(a, b) {
  const rev = b.pts.slice().reverse(); const cand = [b.pts, rev];
  if (b.closed && !b.deg) for (let sh = 3; sh < NP - 1; sh += 3) cand.push(rot(b.pts, sh), rot(rev, sh));
  let best = cand[0], bc = Infinity;
  for (const c of cand) { const v = cost(a.pts, c); if (v < bc) { bc = v; best = c; } }
  return { pts: best, w: b.w, c: bc, deg: b.deg };
}
const cent = (s) => { let x = 0, y = 0; for (const p of s.pts) { x += p[0]; y += p[1]; } return [x / NP, y / NP]; };
const morphCache = new Map();
function pair(an, bn) {
  const key = an + '>' + bn; if (morphCache.has(key)) return morphCache.get(key);
  const A = G[an], B = G[bn], res = new Array(K), costs = [];
  for (let i = 0; i < K; i++) for (let j = 0; j < K; j++) costs.push([orient(A[i], B[j]).c - (B[j].deg ? 0 : 0.8), i, j]);
  costs.sort((x, y) => x[0] - y[0]);
  const doneA = new Set(), used = new Set();
  for (const [, i, j] of costs) { if (doneA.has(i) || used.has(j)) continue; res[i] = orient(A[i], B[j]); doneA.add(i); used.add(j); }
  const ys = A.map((s, i) => -(cent(s)[1] + cent(res[i])[1]) / 2), mn = Math.min(...ys), mx = Math.max(...ys);
  const r = { a: A, b: res, order: ys.map((y) => (y - mn) / ((mx - mn) || 1)) };   // снизу вверх, как скан
  morphCache.set(key, r); return r;
}
function morphAt(an, bn, p, stag = 0.3) {
  const P = pair(an, bn);
  return P.a.map((sa, i) => {
    const sb = P.b[i], e = eio(clamp((p - stag * P.order[i]) / (1 - stag)));
    return { pts: sa.pts.map((q, k) => [lerp(q[0], sb.pts[k][0], e), lerp(q[1], sb.pts[k][1], e)]), w: lerp(sa.w, sb.w, e) };
  });
}

// ---------- медаль ----------
function mWorld(m, lx, ly) {
  const R = 250 * m.scale; let x = lx * R, y = ly * R, z = 0, c, s;
  c = Math.cos(m.rx); s = Math.sin(m.rx); [y, z] = [y * c - z * s, y * s + z * c];
  c = Math.cos(m.ry); s = Math.sin(m.ry); [x, z] = [x * c + z * s, -x * s + z * c];
  return [m.x + x, m.y + y, m.z + z];
}
const mp = (m, p) => project(mWorld(m, p[0], p[1]));
const mScale = (m) => project([m.x, m.y, m.z])[2] * m.scale * 1.19;   // ширина линий: 1 px при R=210
function path(ctx, m, pts, trim = 1) {
  const n = pts.length, end = clamp(trim) * (n - 1), last = Math.floor(end);
  ctx.beginPath(); let q = mp(m, pts[0]); ctx.moveTo(q[0], q[1]);
  for (let i = 1; i <= last; i++) { q = mp(m, pts[i]); ctx.lineTo(q[0], q[1]); }
  if (last < n - 1 && end > last) {
    const u = end - last, a = pts[last], b = pts[last + 1];
    q = mp(m, [lerp(a[0], b[0], u), lerp(a[1], b[1], u)]); ctx.lineTo(q[0], q[1]);
  }
}
function wpath(ctx, pts) { ctx.beginPath(); pts.forEach((p, i) => { const q = project(p); i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]); }); }
function drawStrokes(ctx, m, strokes, o) {
  const sc = mScale(m);
  strokes.forEach((s, i) => {
    const a = (o.alpha ? o.alpha(i) : 1) * clamp(strokeLen(s.pts) / 0.03) * (o.ga ?? 1);
    const tr = o.trim ? o.trim(i) : 1;
    if (a <= 0.003 || tr <= 0.001) return;
    ctx.globalAlpha = a; ctx.strokeStyle = o.color || C.goldBright;
    ctx.lineWidth = o.width * (s.w || 1) * sc;
    path(ctx, m, s.pts, tr); ctx.stroke();
  });
  ctx.globalAlpha = 1;
}
const CIRC = resample(arc(0, 0, 1, Math.PI / 2, Math.PI * 2, 180), 181);
const CIRC_CCW = resample(arc(0, 0, 1, Math.PI / 2, -Math.PI * 2, 180), 181);
const scaled = (pts, r) => pts.map((p) => [p[0] * r, p[1] * r]);
function ring(ctx, m, r, trim, width, color, alpha, ccw) {
  if (trim <= 0.001 || alpha <= 0.003) return;
  ctx.globalAlpha = alpha; ctx.strokeStyle = color; ctx.lineWidth = width * mScale(m);
  path(ctx, m, scaled(ccw ? CIRC_CCW : CIRC, r), trim); ctx.stroke(); ctx.globalAlpha = 1;
}
function disc(ctx, m, r, alpha) {
  if (alpha <= 0.003) return;
  ctx.globalAlpha = alpha; ctx.fillStyle = C.medal; path(ctx, m, scaled(CIRC, r)); ctx.closePath(); ctx.fill(); ctx.globalAlpha = 1;
}
function warmGlow(ctx, m, a) {
  if (a <= 0.003) return;
  const q = mp(m, [0, 0]), R = 250 * project([m.x, m.y, m.z])[2] * 2.4;
  const g = ctx.createRadialGradient(q[0], q[1], 0, q[0], q[1], R);
  g.addColorStop(0, `rgba(241,196,83,${0.16 * a})`); g.addColorStop(0.4, `rgba(241,196,83,${0.055 * a})`); g.addColorStop(1, 'rgba(241,196,83,0)');
  ctx.fillStyle = g; ctx.fillRect(q[0] - R, q[1] - R, 2 * R, 2 * R);
}
function clipLocal(ctx, m, poly) { ctx.beginPath(); poly.forEach((p, i) => { const q = mp(m, p); i ? ctx.lineTo(q[0], q[1]) : ctx.moveTo(q[0], q[1]); }); ctx.closePath(); ctx.clip(); }
// часть круга радиуса r ниже линии y (то, что скан уже прошёл)
function below(r, y) {
  const yy = clamp(y, -r, r), a0 = Math.asin(yy / r), pts = [];
  for (let i = 0; i <= 60; i++) { const a = lerp(a0, Math.PI - a0, i / 60); pts.push([r * Math.cos(a), r * Math.sin(a)]); }
  return pts;
}

// ---------- текст ----------
const FONT = 'Golos';
function textXf(ctx, wx, wy) { const q = project([wx, wy, 0]); ctx.setTransform(q[2] * cam.c, q[2] * cam.s, -q[2] * cam.s, q[2] * cam.c, q[0], q[1]); }
function letters(ctx, str, wx, wy, o) {
  const p = clamp(o.p); if (p <= 0 || (o.alpha ?? 1) <= 0.003) return;
  ctx.save(); textXf(ctx, wx, wy);
  ctx.font = `${o.weight || 800} ${o.size}px ${FONT}`; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = o.color || C.ink;
  const ch = [...str], n = ch.length, tr = lerp(o.track0 ?? 0.3, o.track1 ?? 0.04, eio(p)) * o.size;
  const ws = ch.map((c) => ctx.measureText(c).width), total = ws.reduce((a, b) => a + b, 0) + tr * (n - 1);
  let x = -total / 2;
  ctx.beginPath(); ctx.rect(x - o.size, -o.size * 1.05, total + 2 * o.size, o.size * 1.35); ctx.clip();
  const st = 0.07;
  ch.forEach((c, k) => {
    const pk = eio(clamp(p * (1 + st * (n - 1)) - st * k));
    if (pk > 0) { ctx.globalAlpha = pk * (o.alpha ?? 1); ctx.fillText(c, x, (1 - pk) * o.size * 0.62); }
    x += ws[k] + tr;
  });
  ctx.restore();
}
function wrap(ctx, str, size, weight, maxW) {
  ctx.font = `${weight} ${size}px ${FONT}`; const words = str.split(' '), lines = []; let cur = '';
  for (const w of words) { const t = cur ? cur + ' ' + w : w; if (ctx.measureText(t).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t; }
  if (cur) lines.push(cur); return lines;
}
// строка проявляется бирюзовым сканом слева направо
function wiped(ctx, str, wx, wy, o) {
  const p = clamp(o.p); if (p <= 0) return;
  ctx.save(); textXf(ctx, wx, wy);
  ctx.font = `${o.weight || 400} ${o.size}px ${FONT}`; ctx.textBaseline = 'alphabetic';
  const w = ctx.measureText(str).width, x0 = -w / 2, xe = x0 + w * eio(p);
  ctx.save(); ctx.beginPath(); ctx.rect(x0 - 4, -o.size * 1.1, xe - x0 + 4, o.size * 1.5); ctx.clip();
  ctx.fillStyle = o.color; ctx.fillText(str, x0, 0); ctx.restore();
  const ca = Math.sin(Math.PI * p);
  if (ca > 0.01) { ctx.globalAlpha = ca * 0.9; ctx.fillStyle = C.turqBright; ctx.fillRect(xe, -o.size * 0.95, 2, o.size * 1.25); }
  ctx.restore();
}

// ---------- награды ----------
const AW = [
  { id: 'mergen', name: 'МЕРГЕН', kk: 'Тестте 20 сұрақтың 20-ына дұрыс жауап бердің.', ru: 'Ответил верно на 20 вопросов из 20 в тесте.' },
  { id: 'kosh', name: 'КӨШ БАСТАҒАН', kk: 'Алғашқы серияны аяғына дейін өттің.', ru: 'Прошёл первую серию до конца.' },
  { id: 'book', name: 'ШЕЖІРЕШІ', kk: 'Керей мен Жәнібек туралы барлық сұраққа дұрыс жауап бердің.', ru: 'Верно ответил на все вопросы о Керее и Жанибеке.' },
  { id: 'sun', name: '7 КҮН ҚАТАР', kk: 'Апта бойы күн сайын оқыдың.', ru: 'Занимался каждый день целую неделю.' },
];
const q = new URLSearchParams(location.search);
let award = clamp(parseInt(q.get('award') || '0', 10) || 0, 0, 3);

const MY = -110, HY = MY;   // центр медали и линия горизонта
function medalAt(t) {
  return { x: 0, y: MY, z: 0, scale: 1, ry: 0.1 * Math.sin(t * 2.1 + 0.4) * ep(t, 0.8, 1.6), rx: -0.06 + 0.05 * Math.sin(t * 1.7) };
}

function background(ctx, t) {
  ctx.fillStyle = C.bg; ctx.fillRect(0, 0, W, H);
  const c = project([0, HY, 700]);
  const g = ctx.createRadialGradient(c[0], c[1], 0, c[0], c[1], 1150);
  g.addColorStop(0, 'rgba(58,45,35,1)'); g.addColorStop(0.5, 'rgba(42,32,25,.75)'); g.addColorStop(1, 'rgba(26,20,16,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  // дальний план: концентрические дуги и меридианы, в расфокусе
  const ga = 0.35 + 0.65 * ep(t, 0, 1.2), o = project([0, HY, 1900]), s = o[2];
  ctx.save(); ctx.filter = 'blur(2.4px)'; ctx.lineWidth = 1.5;
  for (let k = 1; k <= 12; k++) {
    ctx.globalAlpha = ga * (k % 3 === 0 ? 0.42 : 0.6); ctx.strokeStyle = k % 3 === 0 ? C.goldDim : C.line;
    ctx.beginPath(); ctx.arc(o[0], o[1], 270 * k * s, 0, Math.PI * 2); ctx.stroke();
  }
  ctx.strokeStyle = C.line; ctx.globalAlpha = ga * 0.5;
  for (let k = 0; k < 24; k++) {
    const a = k * Math.PI / 12 + t * 0.03, p0 = project([270 * Math.cos(a), HY + 270 * Math.sin(a), 1900]), p1 = project([3600 * Math.cos(a), HY + 3600 * Math.sin(a), 1900]);
    ctx.beginPath(); ctx.moveTo(p0[0], p0[1]); ctx.lineTo(p1[0], p1[1]); ctx.stroke();
  }
  ctx.filter = 'blur(1.2px)'; ctx.globalAlpha = ga * 0.7; ctx.strokeStyle = C.goldDim; ctx.lineWidth = 2 * project([0, 0, 520])[2];
  wpath(ctx, [[-4000, HY, 520], [4000, HY, 520]]); ctx.stroke();
  ctx.restore();
}
function foreground(ctx, t) {
  ctx.save(); ctx.filter = 'blur(6px)'; ctx.lineCap = 'round';
  const a = ep(t, 0.2, 1.4);
  ctx.globalAlpha = 0.14 * a; ctx.strokeStyle = C.goldDark; ctx.lineWidth = 3 * project([0, 0, -700])[2];
  wpath(ctx, Array.from({ length: 41 }, (_, i) => { const u = -2.4 + 1.6 * i / 40; return [1500 * Math.cos(u), 2300 + 1500 * Math.sin(u), -700]; })); ctx.stroke();
  ctx.globalAlpha = 0.12 * a; ctx.strokeStyle = C.turq; ctx.lineWidth = 2 * project([0, 0, -700])[2];
  wpath(ctx, [[-900, -1100, -700], [-250, -1330, -700]]); ctx.stroke();
  ctx.restore();
}
function finish(ctx, t) {
  const g = ctx.createRadialGradient(W / 2, H * 0.45, W * 0.4, W / 2, H * 0.45, H * 0.75);
  g.addColorStop(0, 'rgba(14,10,7,0)'); g.addColorStop(1, 'rgba(14,10,7,.6)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  ctx.save(); ctx.globalCompositeOperation = 'overlay'; ctx.globalAlpha = 0.07;
  const f = Math.round(t * 60), ox = (f * 137) % 512, oy = (f * 59) % 512;
  ctx.translate(-ox, -oy); ctx.fillStyle = ctx.createPattern(noiseC, 'repeat'); ctx.fillRect(0, 0, W + 512, H + 512);
  ctx.restore();
}

function scene(ctx, t) {
  setCam(t);
  const A = AW[award], gid = A.id;
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; ctx.filter = 'none';
  gctx.setTransform(1, 0, 0, 1, 0, 0); gctx.clearRect(0, 0, W, H); gctx.lineCap = gctx.lineJoin = 'round'; gctx.filter = 'none'; gctx.globalAlpha = 1;
  ctx.lineCap = ctx.lineJoin = 'round';
  background(ctx, t);

  const m = medalAt(t), g = gctx, hit = pulse(t, TL.hit, 1.0), fill = ep(t, ...TL.fill);
  const sp = prog(t, ...TL.scan), sY = lerp(0.86, -0.86, eioS(sp)), sA = Math.min(ep(t, TL.scan[0] - 0.06, TL.scan[0] + 0.1), 1 - ep(t, TL.scan[1] - 0.08, TL.scan[1] + 0.12));

  // ----- основной холст: тёплый ореол, диск, след скана
  warmGlow(ctx, m, fill * (0.7 + 0.6 * hit));
  disc(ctx, m, 1, fill);
  if (sA > 0) {
    for (let k = 0; k < 14; k++) {
      const y0 = sY + k * 0.012, y1 = sY + (k + 1) * 0.012, r = 0.84;
      const d0 = Math.sqrt(Math.max(0, r * r - y0 * y0)), d1 = Math.sqrt(Math.max(0, r * r - y1 * y1));
      ctx.globalAlpha = sA * 0.16 * Math.pow(1 - k / 14, 1.6); ctx.fillStyle = C.turq;
      ctx.beginPath(); [[-d0, y0], [d0, y0], [d1, y1], [-d1, y1]].forEach((p, i) => { const qq = mp(m, p); i ? ctx.lineTo(qq[0], qq[1]) : ctx.moveTo(qq[0], qq[1]); });
      ctx.closePath(); ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  // ----- линии (холст свечения)
  // горизонт → кольцо: середина поднимается и становится верхом кольца, концы смыкаются внизу
  const cp = prog(t, ...TL.curl);
  if (cp < 1) {
    const hl = 520 * ep(t, ...TL.draw), N = 181, pts = [];
    for (let i = 0; i < N; i++) {
      const u = i / (N - 1), th = Math.PI / 2 + (u - 0.5) * 2 * Math.PI * (1 - 1e-4) + Math.PI;
      const src = [lerp(-hl, hl, u), HY, 0], dst = mWorld(m, Math.cos(th), Math.sin(th));
      const e = eio(clamp((cp - 0.34 * Math.pow((u - 0.5) * 2, 2)) / 0.66));
      pts.push([lerp(src[0], dst[0], e), lerp(src[1], dst[1], e), lerp(src[2], dst[2], e)]);
    }
    if (hl > 1) {
      // концы линии гаснут к краям, пока она прямая
      const a = project(pts[0]), b = project(pts[N - 1]), gr = g.createLinearGradient(a[0], a[1], b[0], b[1]), edge = 1 - ep(t, TL.curl[0], TL.curl[0] + 0.3);
      gr.addColorStop(0, `rgba(217,164,65,${1 - 0.8 * edge})`); gr.addColorStop(0.5, C.gold); gr.addColorStop(1, `rgba(217,164,65,${1 - 0.8 * edge})`);
      g.strokeStyle = cp > 0.3 ? C.gold : gr; g.lineWidth = lerp(2.4, 3, cp) * mScale(m); wpath(g, pts); g.stroke();
    }
  } else ring(g, m, 1, 1, 3, C.gold, 1);
  ring(g, m, 0.86, ep(t, ...TL.inner), 1.4, C.gold, 0.55, true);

  // знак: внутренний круг-зерно морфится в знак; скан снизу вверх доводит его до полного золота
  const seedA = ep(t, TL.inner[0] + 0.05, TL.inner[1]);
  const mp0 = prog(t, ...TL.morph);
  const strokes = mp0 <= 0 ? G.seed : mp0 >= 1 ? G[gid] : morphAt('seed', gid, mp0);
  const opt = { width: 3.2 };
  drawStrokes(g, m, strokes, { ...opt, ga: seedA * 0.4 });
  if (t > TL.scan[0]) {
    g.save(); clipLocal(g, m, sp >= 1 ? scaled(CIRC, 1) : below(0.99, sY)); drawStrokes(g, m, strokes, { ...opt, ga: seedA }); g.restore();
  }
  // скан — линия
  if (sA > 0) {
    const dx = Math.sqrt(Math.max(0, 0.84 * 0.84 - sY * sY));
    g.globalAlpha = sA; g.strokeStyle = C.turqBright; g.lineWidth = 2 * mScale(m); path(g, m, [[-dx, sY], [dx, sY]]); g.stroke(); g.globalAlpha = 1;
  }

  // детали по награде
  const sc = mScale(m), [d0, d1] = TL.detail;
  if (gid === 'mergen') {
    for (let k = 0; k < 20; k++) {
      const a = -Math.PI / 2 + k * Math.PI / 10, tk = lerp(d0, d1 - 0.12, k / 19), l = ep(t, tk - 0.03, tk + 0.1);
      g.globalAlpha = ep(t, d0 - 0.15, d0); g.strokeStyle = l > 0.5 ? C.gold : C.goldDim; g.lineWidth = 2.6 * sc;
      path(g, m, [[1.08 * Math.cos(a), 1.08 * Math.sin(a)], [1.16 * Math.cos(a), 1.16 * Math.sin(a)]]); g.stroke();
      const pk = pulse(t, tk, 0.35); if (pk > 0) { g.globalAlpha = pk; g.strokeStyle = C.goldBright; g.stroke(); }
    }
    ring(g, m, lerp(0.08, 0.62, ep(t, TL.hit, TL.hit + 0.8)), 1, 1.6, C.goldBright, 0.8 * pulse(t, TL.hit, 0.8));
  } else if (gid === 'sun') {
    for (let k = 0; k < 7; k++) {
      const c = -Math.PI / 2 + k * 2 * Math.PI / 7, hw = Math.PI / 7 * 0.72, tk = lerp(d0, d1 - 0.06, k / 6), l = ep(t, tk - 0.04, tk + 0.1);
      const pts = arc(0, 0, 1.11, c - hw, 2 * hw, 24), dr = ep(t, d0 - 0.2 + k * 0.012, d0);
      g.globalAlpha = dr; g.strokeStyle = l > 0.5 ? C.gold : C.goldDim; g.lineWidth = 3 * sc; path(g, m, pts, dr); g.stroke();
      const pk = pulse(t, tk, 0.45); if (pk > 0) { g.globalAlpha = pk; g.strokeStyle = C.goldBright; g.lineWidth = 3.6 * sc; path(g, m, pts); g.stroke(); }
    }
  } else if (gid === 'kosh') {
    const pr = ep(t, d0, d1), a0 = Math.PI * 1.1, a1 = Math.PI * 1.9, n = 15;
    for (let k = 0; k < n; k++) {
      const u = k / (n - 1); if (pr <= 0 || u > pr + 1e-6) break;
      const a = lerp(a0, a1, u), qq = mp(m, [1.13 * Math.cos(a), 1.13 * Math.sin(a)]);
      g.globalAlpha = 0.85; g.fillStyle = C.gold; g.beginPath(); g.arc(qq[0], qq[1], 2.6 * sc, 0, Math.PI * 2); g.fill();
    }
    if (pr > 0 && pr < 1) { const a = lerp(a0, a1, pr), qq = mp(m, [1.13 * Math.cos(a), 1.13 * Math.sin(a)]); g.globalAlpha = 1; g.fillStyle = C.turqBright; g.beginPath(); g.arc(qq[0], qq[1], 4.5 * sc, 0, Math.PI * 2); g.fill(); }
    g.globalAlpha = 1;
  } else if (gid === 'book') {
    // строки страниц сканируются слева направо, узлы древа отвечают импульсом
    for (const nx of [-0.25, 0.25]) {
      const pk = pulse(t, TL.hit, 0.8); if (pk <= 0) continue;
      const c0 = mWorld(m, nx, -0.31), r = lerp(0.05, 0.2, ep(t, TL.hit, TL.hit + 0.8));
      ring(g, { ...m, x: c0[0], y: c0[1], z: c0[2], scale: m.scale * r }, 1, 1, 0.4 / r, C.goldBright, pk * 0.8);
    }
  }
  g.globalAlpha = 1;
  // подтверждение — внешний импульс-кольцо
  ring(g, m, lerp(1.0, 1.42, ep(t, TL.hit, TL.hit + 1.0)), 1, 1.6, C.gold, 0.55 * pulse(t, TL.hit, 1.0));

  // ----- свечение: мягко, через screen, без пересвета
  ctx.save(); ctx.globalCompositeOperation = 'screen';
  ctx.filter = 'blur(26px)'; ctx.globalAlpha = 0.36 + 0.2 * hit; ctx.drawImage(glowC, 0, 0);
  ctx.filter = 'blur(7px)'; ctx.globalAlpha = 0.4 + 0.12 * hit; ctx.drawImage(glowC, 0, 0);
  ctx.restore(); ctx.drawImage(glowC, 0, 0);

  // ----- текст
  letters(ctx, 'ЖАҢА МАРАПАТ', 0, -590, { size: 30, weight: 700, color: C.gold, track0: 0.9, track1: 0.26, p: prog(t, ...TL.header) });
  letters(ctx, A.name, 0, 310, { size: 84, weight: 800, color: C.ink, track0: 0.32, track1: 0.04, p: prog(t, ...TL.name) });
  const kl = wrap(ctx, A.kk, 33, 400, 840), rl = wrap(ctx, A.ru, 26, 400, 840);
  kl.forEach((ln, i) => wiped(ctx, ln, 0, 390 + i * 46, { size: 33, weight: 400, color: C.warm, p: prog(t, TL.kk[0] + i * 0.12, TL.kk[1] + i * 0.12) }));
  const ry = 390 + kl.length * 46 + 14;
  rl.forEach((ln, i) => wiped(ctx, ln, 0, ry + i * 36, { size: 26, weight: 400, color: C.inkSoft, p: prog(t, TL.ru[0] + i * 0.12, TL.ru[1] + i * 0.12) }));
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  foreground(ctx, t);
  finish(ctx, t);
}

// субкадровая выборка (motion blur) там, где есть быстрое движение
function renderAt(t, mb = true) {
  const N = mb && t > 0.25 && t < 1.6 ? 5 : 1, shutter = 0.5 / TL.FPS;
  out.setTransform(1, 0, 0, 1, 0, 0);
  for (let k = 0; k < N; k++) {
    scene(fctx, N === 1 ? t : t + ((k + 0.5) / N - 0.5) * shutter);
    out.globalAlpha = 1 / (k + 1); out.drawImage(frameC, 0, 0);
  }
  out.globalAlpha = 1;
}
globalThis.renderAt = renderAt;
globalThis.setAward = (k) => { award = k; };
globalThis.renderFrame = (i) => { renderAt(i / TL.FPS); return outC.toDataURL('image/png'); };
globalThis.ready = document.fonts.load(`800 40px ${FONT}`).then(() => document.fonts.load(`400 20px ${FONT}`)).then(() => document.fonts.load(`700 20px ${FONT}`)).then(() => true);

// ----- превью: пробел — пауза, ←/→ — кадр, 1–4 — награда -----
if (!q.has('render')) {
  let t = parseFloat(q.get('t') || '0'), playing = !q.has('t'), last = null;
  const tick = (now) => {
    if (playing) { if (last != null) t += (now - last) / 1000; if (t >= TL.DUR + 0.6) t = 0; }
    last = now; renderAt(Math.min(t, TL.DUR - 1 / 60), false); requestAnimationFrame(tick);
  };
  addEventListener('keydown', (e) => {
    if (e.code === 'Space') playing = !playing;
    if (e.code === 'ArrowRight') t = Math.min(TL.DUR, t + 1 / 60);
    if (e.code === 'ArrowLeft') t = Math.max(0, t - 1 / 60);
    if (/^Digit[1-4]$/.test(e.code)) { award = +e.code.slice(5) - 1; t = 0; }
  });
  globalThis.ready.then(() => requestAnimationFrame(tick));
}
})();
