'use strict';
// Анимированные карты s1e01 / s1e02. Управляемый таймлайн: renderAt(t) детерминирован.
// ?map=route|south  ?lang=kk|ru  ?t=секунды (стоп-кадр)  ?render (покадровый экспорт)
(() => {
const W = 1080, H = 1890, FPS = 30, DUR = 3.5, STILL = 3.05;   // после STILL ничего не движется
const q = new URLSearchParams(location.search);
const MAP = q.get('map') === 'south' ? 'south' : 'route', LANG = q.get('lang') === 'ru' ? 'ru' : 'kk';
const GEO = globalThis.GEO;

const C = {
  ground: '#2A2019', paper: '#D7C29A', paperDark: '#BFA678', ink: '#3B2A1E', red: '#B23A2A', redDark: '#8E2F22',
  water: '#9EB0AD', shore: '#6E8486', river: '#7B9396',
};
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, t) => a + (b - a) * t;
const eio = (t) => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
const eoc = (t) => 1 - Math.pow(1 - t, 3);
const prog = (t, a, b) => clamp((t - a) / (b - a));
const ep = (t, a, b, e = eio) => e(prog(t, a, b));

// ---------- проекция: равнопромежуточная с масштабом по широте ----------
const PROJ = {
  route: { lon0: 70.1, lat0: 43.5, k: 96, y0: 800, focus: [580, 780] },
  south: { lon0: 63.9, lat0: 44.0, k: 100, y0: 560, focus: [660, 720] },
}[MAP];
const kx = PROJ.k * Math.cos(PROJ.lat0 * Math.PI / 180);
const P = ([lon, lat]) => [W / 2 + (lon - PROJ.lon0) * kx, PROJ.y0 - (lat - PROJ.lat0) * PROJ.k];

// ---------- холсты ----------
const outC = document.getElementById('c'); outC.width = W; outC.height = H;
const ctx = outC.getContext('2d');
const mk = () => { const c = document.createElement('canvas'); c.width = W; c.height = H; return c; };
let seed = 1465; const rnd = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
// неподвижное зерно бумаги
const grainC = mk();
{
  const g = grainC.getContext('2d'), id = g.createImageData(W, H);
  for (let i = 0; i < id.data.length; i += 4) { const v = 128 + (rnd() - 0.5) * 34; id.data[i] = id.data[i + 1] = id.data[i + 2] = v; id.data[i + 3] = 255; }
  g.putImageData(id, 0, 0);
}
// бумага: основа, пятна, волокна — рисуется один раз
const paperC = mk();
{
  const g = paperC.getContext('2d');
  g.fillStyle = C.paper; g.fillRect(0, 0, W, H);
  for (let i = 0; i < 26; i++) {
    const x = rnd() * W, y = rnd() * H * 0.75, r = 120 + rnd() * 320, dark = rnd() < 0.55;
    const gr = g.createRadialGradient(x, y, 0, x, y, r);
    gr.addColorStop(0, dark ? 'rgba(150,118,72,0.10)' : 'rgba(240,226,196,0.12)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.fillRect(x - r, y - r, 2 * r, 2 * r);
  }
  g.strokeStyle = 'rgba(120,92,58,0.05)'; g.lineWidth = 1;
  for (let i = 0; i < 260; i++) { const x = rnd() * W, y = rnd() * H * 0.7, a = rnd() * Math.PI, l = 10 + rnd() * 40; g.beginPath(); g.moveTo(x, y); g.lineTo(x + Math.cos(a) * l, y + Math.sin(a) * l); g.stroke(); }
  // мягкая виньетка
  const v = g.createRadialGradient(W / 2, H * 0.36, W * 0.35, W / 2, H * 0.36, W * 0.95);
  v.addColorStop(0, 'rgba(90,62,34,0)'); v.addColorStop(1, 'rgba(90,62,34,0.28)');
  g.fillStyle = v; g.fillRect(0, 0, W, H);
}

// ---------- базовые формы ----------
function polyPath(g, pts, close) { g.beginPath(); pts.forEach((p, i) => { const s = P(p); i ? g.lineTo(s[0], s[1]) : g.moveTo(s[0], s[1]); }); if (close) g.closePath(); }
function smoothScreen(pts, n = 16) {          // Catmull-Rom по экранным точкам
  const s = pts.map(P), o = [];
  for (let i = 0; i < s.length - 1; i++) {
    const p0 = s[Math.max(0, i - 1)], p1 = s[i], p2 = s[i + 1], p3 = s[Math.min(s.length - 1, i + 2)];
    for (let k = 0; k < n; k++) {
      const u = k / n, u2 = u * u, u3 = u2 * u;
      o.push([0, 1].map((j) => 0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * u + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * u2 + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * u3)));
    }
  }
  o.push(s[s.length - 1]); return o;
}
const lenOf = (s) => { let L = 0; for (let i = 1; i < s.length; i++) L += Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1]); return L; };
function trimmed(s, frac) {                    // часть экранной линии по длине
  const T = lenOf(s) * clamp(frac), o = [s[0]]; let acc = 0;
  for (let i = 1; i < s.length; i++) {
    const d = Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1]);
    if (acc + d >= T) { const u = (T - acc) / (d || 1); o.push([lerp(s[i - 1][0], s[i][0], u), lerp(s[i - 1][1], s[i][1], u)]); return o; }
    acc += d; o.push(s[i]);
  }
  return o;
}
function strokeScreen(g, s) { g.beginPath(); s.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.stroke(); }

function territory(g, pts, color, blur = 42) {
  g.save(); g.filter = `blur(${blur}px)`; g.fillStyle = color; polyPath(g, pts, true); g.fill(); g.restore();
}
function water(g) {
  for (const k of ['aral', 'balkhash', 'issyk', 'alakol']) for (const ring of GEO[k]) {
    g.save(); g.fillStyle = C.water; polyPath(g, ring, true); g.fill();
    g.clip(); g.filter = 'blur(6px)'; g.strokeStyle = 'rgba(70,96,100,0.35)'; g.lineWidth = 14; polyPath(g, ring, true); g.stroke(); g.restore();
    g.strokeStyle = C.shore; g.lineWidth = 1.6; polyPath(g, ring, true); g.stroke();
  }
}
function rivers(g, list) {
  g.lineCap = g.lineJoin = 'round';
  for (const [k, w] of list) for (const ln of GEO[k]) { g.strokeStyle = C.river; g.lineWidth = w; polyPath(g, ln); g.stroke(); }
}
// горы: тень хребта и штрихи-бергштрихи по обе стороны
function ridge(g, pts, size = 1) {
  const s = smoothScreen(pts, 10);
  g.save(); g.filter = 'blur(8px)'; g.strokeStyle = 'rgba(110,80,48,0.13)'; g.lineWidth = 22 * size; g.lineCap = 'round'; strokeScreen(g, s); g.restore();
  const L = lenOf(s), step = 9; let acc = 0, i = 1, sd = 7 + pts.length * 31;
  const r2 = () => ((sd = (Math.imul(sd, 1103515245) + 12345) >>> 0) / 4294967296);
  g.strokeStyle = 'rgba(92,64,38,0.55)'; g.lineWidth = 1.3; g.lineCap = 'round';
  for (let d = step / 2; d < L; d += step) {
    while (i < s.length - 1 && acc + Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1]) < d) { acc += Math.hypot(s[i][0] - s[i - 1][0], s[i][1] - s[i - 1][1]); i++; }
    const a = s[i - 1], b = s[i], seg = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, u = (d - acc) / seg;
    const x = lerp(a[0], b[0], u), y = lerp(a[1], b[1], u), nx = -(b[1] - a[1]) / seg, ny = (b[0] - a[0]) / seg;
    const taper = Math.sin(Math.PI * d / L) * 0.7 + 0.3;
    for (const side of [-1, 1]) {
      const l = (6 + r2() * 8) * size * taper, off = 2;
      g.globalAlpha = side > 0 ? 0.9 : 0.5;    // южный склон темнее
      g.beginPath(); g.moveTo(x + nx * off * side, y + ny * off * side); g.lineTo(x + nx * (off + l) * side + (r2() - 0.5) * 3, y + ny * (off + l) * side); g.stroke();
    }
  }
  g.globalAlpha = 1;
}

// ---------- подписи ----------
const SERIF = 'PTSerif';
function label(g, text, lonlat, o) {
  const a = o.alpha ?? 1; if (a <= 0.003) return;
  const [x, y] = o.xy || P(lonlat);
  g.save(); g.translate(x + (o.dx || 0), y + (o.dy || 0)); if (o.rot) g.rotate(o.rot * Math.PI / 180);
  g.font = `${o.italic ? 'italic ' : ''}${o.weight || 400} ${o.size}px ${SERIF}`;
  g.letterSpacing = `${(o.track || 0) * o.size}px`; g.textAlign = o.align || 'center'; g.textBaseline = 'alphabetic';
  g.globalAlpha = a;
  if (o.halo !== false) { g.strokeStyle = 'rgba(222,204,166,0.78)'; g.lineWidth = o.halo || Math.max(5, o.size * 0.16); g.lineJoin = 'round'; g.strokeText(text, 0, 0); }
  g.fillStyle = o.color || C.ink; g.fillText(text, 0, 0);
  if (globalThis.BOXES) {               // рамка подписи в экранных координатах (для проверки полей)
    const m = g.measureText(text), tr = g.getTransform(), al = g.textAlign, x0 = al === 'right' ? -m.width : al === 'center' ? -m.width / 2 : 0;
    const pts = [[x0, -m.actualBoundingBoxAscent], [x0 + m.width, -m.actualBoundingBoxAscent], [x0, m.actualBoundingBoxDescent], [x0 + m.width, m.actualBoundingBoxDescent]].map(([u, v]) => [tr.a * u + tr.c * v + tr.e, tr.b * u + tr.d * v + tr.f]);
    globalThis.BOXES.push({ text, x0: Math.round(Math.min(...pts.map((p) => p[0]))), x1: Math.round(Math.max(...pts.map((p) => p[0]))), y0: Math.round(Math.min(...pts.map((p) => p[1]))), y1: Math.round(Math.max(...pts.map((p) => p[1]))) });
  }
  g.restore();
}
function cityDot(g, lonlat, a, r = 7) {
  if (a <= 0.003) return; const [x, y] = P(lonlat);
  g.globalAlpha = a; g.fillStyle = 'rgba(222,204,166,0.9)'; g.beginPath(); g.arc(x, y, r + 3.5, 0, Math.PI * 2); g.fill();
  g.fillStyle = C.ink; g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill(); g.globalAlpha = 1;
}
function yurt(g, x, y, s, a) {             // маленький значок кочевья, ~26 px
  if (a <= 0.003) return;
  g.save(); g.translate(x, y); g.scale(s / 26, s / 26); g.globalAlpha = a;
  const shape = () => { g.beginPath(); g.moveTo(-13, 9); g.lineTo(-12, -1); g.quadraticCurveTo(-11, -12, 0, -13); g.quadraticCurveTo(11, -12, 12, -1); g.lineTo(13, 9); g.closePath(); };
  g.lineJoin = 'round'; g.strokeStyle = 'rgba(222,204,166,0.9)'; g.lineWidth = 6; shape(); g.stroke();
  g.fillStyle = C.ink; shape(); g.fill();
  g.fillStyle = C.paper; g.fillRect(-3, 1, 6, 8); g.fillRect(-12, -2, 24, 1.6);
  g.restore();
}

// ---------- карта 1: путь откочёвки ----------
const T1 = {
  route: [[67.35, 44.05], [67.8, 43.75], [68.25, 43.38], [68.95, 42.98], [69.75, 42.62], [70.55, 42.55], [71.35, 42.86], [72.1, 43.12], [72.95, 43.38], [73.78, 43.6]],
  sygnak: [67.35, 44.05], shu: [73.78, 43.6],
  L: {
    kk: { steppe: 'ДЕШТІ ҚЫПШАҚ', syr: 'Сырдария', sygnak: 'Сығанақ', abul: 'Әбілқайыр иелігі', mogul: 'Моғолстан', shu: 'Шу · Қозыбасы', sub: 'Батыс Жетісу, 1465' },
    ru: { steppe: 'ДЕШТ-И-КЫПЧАК', syr: 'Сырдарья', sygnak: 'Сыгнак', abul: 'Владения Абулхаира', mogul: 'Могулистан', shu: 'Шу · Козыбасы', sub: 'Западное Жетысу, 1465' },
  },
};
const RIDGES1 = [
  [[67.6, 44.4], [68.3, 44.0], [69.0, 43.55], [69.6, 43.15], [70.2, 42.75], [70.7, 42.38]],             // Каратау
  [[70.7, 42.18], [71.5, 42.15], [72.3, 42.3], [73.1, 42.35]],                                          // Таласский Алатау
  [[71.5, 42.62], [72.4, 42.68], [73.4, 42.64], [74.4, 42.58], [75.4, 42.5]],                            // Киргизский хребет
  [[75.7, 43.05], [76.6, 43.08], [77.5, 43.05], [78.6, 43.0]],                                          // Заилийский Алатау
  [[76.2, 42.85], [77.2, 42.88], [78.3, 42.9]],                                                         // Кунгей
  [[76.3, 41.95], [77.5, 41.95], [78.7, 42.12]],                                                        // Терскей
  [[69.9, 41.95], [70.6, 41.6], [71.3, 41.35]],                                                         // Чаткал-Угам
];
function drawRoute(g, t) {
  const L = T1.L[LANG];
  const fill = ep(t, 0.1, 0.9);
  territory(g, [[52, 51], [71.6, 51], [71.9, 46.6], [70.8, 45.1], [70.3, 44.3], [69.2, 43.45], [68.3, 43.0], [66.6, 43.35], [64.2, 43.7], [61.4, 43.0], [52, 42.6]], `rgba(104,92,80,${0.36 * fill})`);
  territory(g, [[72.6, 46.4], [76, 46.9], [84, 47.6], [84, 40.2], [76, 40.4], [73.6, 41.1], [72.3, 41.8], [71.9, 42.6], [72.4, 44.0], [72.2, 45.3]], `rgba(116,138,76,${0.34 * fill})`);
  RIDGES1.forEach((r) => ridge(g, r));
  water(g);
  rivers(g, [['syr', 3.2], ['naryn', 2], ['chu', 2.2], ['talas', 2], ['ili', 2.2]]);

  const la = (a, b) => lerp(0.55, 1, ep(t, a, b)) * ep(t, 0.15, 0.75);   // подпись: проявление, затем до полной яркости
  label(g, L.steppe, [68.9, 47.3], { size: 50, weight: 700, track: 0.34, color: 'rgba(59,42,30,0.42)', halo: false, alpha: ep(t, 0.2, 1.0) * lerp(0.7, 1, ep(t, 2.6, 3.0)) });
  label(g, L.abul, [66.0, 46.0], { size: 36, italic: true, color: '#4D4034', alpha: la(2.5, 3.0) });
  label(g, L.mogul, [76.55, 44.95], { size: 38, italic: true, align: 'right', color: '#3F4A26', alpha: la(2.5, 3.0) });
  label(g, L.syr, [64.9, 45.05], { size: 31, italic: true, color: '#4E6668', rot: 27, dy: -14, alpha: la(2.6, 3.0) });
  cityDot(g, T1.sygnak, ep(t, 0.3, 0.7));
  label(g, L.sygnak, T1.sygnak, { size: 34, align: 'left', dx: 14, dy: -16, alpha: la(2.6, 3.0) });

  // маршрут: пунктир с мягким краем, значок кочевья на голове
  const s = smoothScreen(T1.route), p = ep(t, 0.5, 2.4), part = trimmed(s, p);
  if (p > 0) {
    g.save(); g.lineCap = 'round'; g.lineJoin = 'round';
    g.setLineDash([16, 12]);
    g.filter = 'blur(2.5px)'; g.strokeStyle = 'rgba(142,47,34,0.45)'; g.lineWidth = 9; strokeScreen(g, part);
    g.filter = 'none'; g.strokeStyle = C.redDark; g.lineWidth = 5; strokeScreen(g, part);
    g.restore();
    const h = part[part.length - 1];
    yurt(g, h[0], h[1] - 24, 28, ep(t, 0.5, 0.7) * (1 - ep(t, 2.25, 2.45)));
  }
  // прибытие
  const [sx, sy] = P(T1.shu), fl = prog(t, 2.35, 2.95);
  if (fl > 0 && fl < 1) { g.strokeStyle = `rgba(178,58,42,${0.55 * (1 - eoc(fl))})`; g.lineWidth = 3; g.beginPath(); g.arc(sx, sy, lerp(12, 64, eoc(fl)), 0, Math.PI * 2); g.stroke(); }
  const da = ep(t, 2.3, 2.6);
  if (da > 0) {
    g.globalAlpha = da; g.fillStyle = 'rgba(222,204,166,0.9)'; g.beginPath(); g.arc(sx, sy, 15, 0, Math.PI * 2); g.fill();
    g.fillStyle = C.red; g.beginPath(); g.arc(sx, sy, 11, 0, Math.PI * 2); g.fill();
    g.strokeStyle = C.redDark; g.lineWidth = 2; g.stroke(); g.globalAlpha = 1;
  }
  label(g, L.shu, T1.shu, { size: 46, weight: 700, color: C.red, dy: -66, alpha: ep(t, 2.4, 2.9) });
  label(g, L.sub, T1.shu, { size: 30, color: C.ink, dy: -28, alpha: ep(t, 2.55, 3.0) });
}

// ---------- карта 2: Шайбани на юг ----------
const T2 = {
  sygnak: [67.35, 44.05], split: [66.55, 42.75], samarkand: [66.96, 39.65], bukhara: [64.42, 39.77],
  L: {
    kk: { steppe: 'ДЕШТІ ҚЫПШАҚ', maver: 'МӘУЕРЕННАХР', syr: 'Сырдария', amu: 'Әмудария', sygnak: 'Сығанақ', bukhara: 'Бұхара', samarkand: 'Самарқанд', shaybani: 'Шайбани, 1500', left: 'ӨЗБЕК', right: 'ҚАЗАҚ', leftFinal: 'ӨЗБЕК', rightFinal: 'ҚАЗАҚ' },
    ru: { steppe: 'ДЕШТ-И-КЫПЧАК', maver: 'МАВЕРАННАХР', syr: 'Сырдарья', amu: 'Амударья', sygnak: 'Сыгнак', bukhara: 'Бухара', samarkand: 'Самарканд', shaybani: 'Шайбани, 1500', left: 'УЗБЕК', right: 'КАЗАХИ', leftFinal: 'УЗБЕКИ', rightFinal: 'КАЗАХИ' },
  },
};
const RIDGES2 = [
  [[67.6, 44.4], [68.3, 44.0], [69.0, 43.55], [69.6, 43.15], [70.2, 42.75], [70.7, 42.38]],             // Каратау
  [[65.6, 40.52], [66.4, 40.6], [67.3, 40.66]],                                                         // Нуратау
  [[67.4, 39.28], [68.4, 39.32], [69.5, 39.38]],                                                        // Зеравшанский хребет
  [[67.9, 39.78], [68.9, 39.82], [70.0, 39.92]],                                                        // Туркестанский хребет
  [[69.9, 41.95], [70.6, 41.6], [71.3, 41.35]],                                                         // Чаткал-Угам
];
// толстая стрела с сужением, рисуется по длине; голова — когда дошла
function arrow(g, pts, p, w0, w1, headA) {
  const s = smoothScreen(pts, 20), part = trimmed(s, p); if (part.length < 2 || p <= 0) return null;
  const n = part.length, Ltot = lenOf(s); let acc = 0;
  g.fillStyle = C.red;
  for (let i = 1; i < n; i++) {
    const a = part[i - 1], b = part[i], d = Math.hypot(b[0] - a[0], b[1] - a[1]); acc += d;
    const w = lerp(w0, w1, acc / Ltot);
    g.lineWidth = w; g.strokeStyle = C.red; g.lineCap = 'round'; g.beginPath(); g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]); g.stroke();
  }
  const tip = part[n - 1], prev = part[Math.max(0, n - 4)], ang = Math.atan2(tip[1] - prev[1], tip[0] - prev[0]);
  if (headA > 0) {
    const hl = 30, hw = 19;
    g.save(); g.globalAlpha = headA; g.translate(tip[0], tip[1]); g.rotate(ang);
    g.beginPath(); g.moveTo(8, 0); g.lineTo(-hl, -hw); g.lineTo(-hl * 0.72, 0); g.lineTo(-hl, hw); g.closePath(); g.fill(); g.restore();
  }
  return { tip, ang };
}
function drawSouth(g, t) {
  const L = T2.L[LANG];
  territory(g, [[62.6, 40.6], [64.4, 41.35], [66.8, 41.7], [68.6, 41.3], [70.6, 41.0], [71.6, 40.4], [70.2, 39.1], [67.6, 38.5], [65.4, 38.5], [63.4, 39.0]], `rgba(196,138,56,${0.3 * ep(t, 0.05, 0.7)})`, 38);
  RIDGES2.forEach((r) => ridge(g, r));
  water(g);
  rivers(g, [['syr', 3.4], ['amu', 3.4], ['zeravshan', 2.2], ['naryn', 2], ['talas', 1.8], ['chu', 1.8]]);

  const la = (a, b) => lerp(0.55, 1, ep(t, a, b)) * ep(t, 0.15, 0.75);
  label(g, L.steppe, [64.6, 47.35], { size: 50, weight: 700, track: 0.34, color: 'rgba(59,42,30,0.42)', halo: false, alpha: ep(t, 0.2, 1.0) * lerp(0.7, 1, ep(t, 2.6, 3.0)) });
  label(g, L.maver, [65.7, 38.92], { size: 44, weight: 700, track: 0.3, color: 'rgba(84,56,24,0.5)', halo: false, alpha: la(2.6, 3.0) });
  label(g, L.syr, [63.6, 45.38], { size: 31, italic: true, color: '#4E6668', rot: 17, dy: 30, alpha: la(2.6, 3.0) });
  label(g, L.amu, [61.65, 40.75], { size: 31, italic: true, color: '#4E6668', rot: -52, dx: 30, dy: 10, alpha: la(2.6, 3.0) });
  cityDot(g, T2.sygnak, ep(t, 0.25, 0.6));
  label(g, L.sygnak, T2.sygnak, { size: 34, align: 'left', dx: 18, dy: -12, alpha: la(2.6, 3.0) });

  // стрела: ствол до развилки, затем две ветви
  const trunkP = ep(t, 0.5, 1.25), brP = ep(t, 1.2, 1.8);
  const trunk = [T2.sygnak, [67.1, 43.45], T2.split];
  const toS = [T2.split, [67.75, 41.75], [67.45, 40.45], [67.02, 39.86]], toB = [T2.split, [65.0, 41.95], [64.45, 40.6], [64.4, 39.95]];
  g.save();
  arrow(g, trunk, trunkP, 13, 11, 0);
  if (brP > 0) { arrow(g, toS, brP, 10, 8, ep(t, 1.6, 1.8)); arrow(g, toB, brP, 10, 8, ep(t, 1.6, 1.8)); }
  g.restore();
  // города проявляются в момент касания
  const touch = ep(t, 1.72, 2.05);
  cityDot(g, T2.samarkand, touch); cityDot(g, T2.bukhara, touch);
  label(g, L.samarkand, T2.samarkand, { size: 34, align: 'left', dx: 18, dy: 12, alpha: touch * lerp(0.85, 1, ep(t, 2.6, 3.0)) });
  label(g, L.bukhara, T2.bukhara, { size: 34, align: 'right', dx: -18, dy: 12, alpha: touch * lerp(0.85, 1, ep(t, 2.6, 3.0)) });
  label(g, L.shaybani, [67.0, 43.15], { size: 29, italic: true, align: 'left', dx: 22, alpha: ep(t, 1.0, 1.5) });

  // раскол имени: «ӨЗБЕК-ҚАЗАҚ» трескается по дефису
  const size0 = 54, sizeR = 62, sizeL = 42;
  g.save(); g.font = `700 ${size0}px ${SERIF}`; g.letterSpacing = `${0.06 * size0}px`;
  const wl = g.measureText(L.left).width, wd = g.measureText('-').width, wr = g.measureText(L.right).width; g.restore();
  const [cx0, cy0] = P([66.2, 45.05]), total = wl + wd + wr, xl0 = cx0 - total / 2, xr0 = xl0 + wl + wd;
  const gap = ep(t, 1.78, 1.98) * 10, mv = ep(t, 1.92, 2.85);
  // левая часть уезжает вдоль стрелы к Мавераннахру
  const [lx1, ly1] = P([65.95, 40.68]), ctl = P([66.9, 42.9]);
  const u = mv, bx = (1 - u) * (1 - u) * (xl0 + wl / 2 - gap) + 2 * u * (1 - u) * ctl[0] + u * u * lx1, by = (1 - u) * (1 - u) * cy0 + 2 * u * (1 - u) * ctl[1] + u * u * ly1;
  const inA = ep(t, 0.15, 0.55);
  const leftText = LANG === 'ru' && mv > 0.5 ? L.leftFinal : L.left;
  label(g, L.left, null, { xy: [bx, by], size: lerp(size0, sizeL, mv), weight: 700, track: 0.06, color: C.ink, alpha: inA * (LANG === 'ru' ? 1 - ep(t, 2.5, 2.85) * 0 : 1) });
  if (LANG === 'ru') {   // «УЗБЕК» → «УЗБЕКИ»: буква «И» проявляется на месте
    g.save(); g.font = `700 ${sizeL}px ${SERIF}`; g.letterSpacing = `${0.06 * sizeL}px`;
    const wL = g.measureText(L.left).width, wI = g.measureText('И').width; g.restore();
    label(g, 'И', null, { xy: [bx + wL / 2 + wI / 2 + 0.06 * sizeL * 0.5, by], size: sizeL, weight: 700, color: C.ink, alpha: ep(t, 2.55, 2.95) * (mv >= 1 ? 1 : ep(t, 2.55, 2.95)) });
  }
  // дефис гаснет, трещина — тонкая линия, без осколков
  const crack = prog(t, 1.6, 1.85), crackOut = 1 - ep(t, 1.85, 2.1);
  label(g, '-', null, { xy: [xl0 + wl + wd / 2, cy0], size: size0, weight: 700, color: C.ink, alpha: inA * (1 - ep(t, 1.65, 1.85)) });
  if (crack > 0 && crackOut > 0) {
    const xm = xl0 + wl + wd / 2;
    g.save(); g.strokeStyle = `rgba(59,42,30,${0.8 * crackOut})`; g.lineWidth = 1.6; g.beginPath();
    const pts = [[xm + 2, cy0 - 50], [xm - 3, cy0 - 30], [xm + 3, cy0 - 14], [xm - 2, cy0 + 2], [xm + 2, cy0 + 14]];
    const ct = trimmed(pts, eio(crack)); ct.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.stroke(); g.restore();
  }
  // правая часть остаётся в степи, смещается к центру и краснеет
  const [rx1, ry1] = P([66.25, 45.55]);
  const rx = lerp(xr0 + wr / 2 + gap, rx1, mv), ry = lerp(cy0, ry1, mv);
  const red = ep(t, 2.0, 2.7);
  const col = `rgb(${Math.round(lerp(59, 178, red))},${Math.round(lerp(42, 58, red))},${Math.round(lerp(30, 42, red))})`;
  label(g, L.right, null, { xy: [rx, ry], size: lerp(size0, sizeR, mv), weight: 700, track: 0.06, color: col, alpha: inA });
}

// ---------- кадр ----------
function renderAt(t) {
  t = Math.min(t, STILL);                      // после STILL кадр неподвижен
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.filter = 'none'; ctx.setLineDash([]);
  ctx.fillStyle = C.ground; ctx.fillRect(0, 0, W, H);
  const z = 1.04 - 0.04 * eoc(prog(t, 0, STILL)), [fx, fy] = PROJ.focus;
  ctx.save(); ctx.setTransform(z, 0, 0, z, fx * (1 - z), fy * (1 - z));
  ctx.drawImage(paperC, -40, -40, W + 80, H + 80);
  (MAP === 'route' ? drawRoute : drawSouth)(ctx, t);
  ctx.restore();
  ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.globalAlpha = 1; ctx.filter = 'none';
  // зерно (неподвижное)
  ctx.save(); ctx.globalCompositeOperation = 'overlay'; ctx.globalAlpha = 0.16; ctx.drawImage(grainC, 0, 0); ctx.restore();
  // края и низ уходят в #2A2019
  const edge = (x0, y0, x1, y1, a0, a1) => { const g = ctx.createLinearGradient(x0, y0, x1, y1); g.addColorStop(0, `rgba(42,32,25,${a0})`); g.addColorStop(1, `rgba(42,32,25,${a1})`); return g; };
  ctx.fillStyle = edge(0, 0, 0, 90, 1, 0); ctx.fillRect(0, 0, W, 90);
  ctx.fillStyle = edge(0, 0, 64, 0, 1, 0); ctx.fillRect(0, 0, 64, H);
  ctx.fillStyle = edge(W, 0, W - 64, 0, 1, 0); ctx.fillRect(W - 64, 0, 64, H);
  ctx.fillStyle = edge(0, H * 0.6, 0, H * 0.7, 0, 1); ctx.fillRect(0, H * 0.6, W, H * 0.1 + 1);
  ctx.fillStyle = C.ground; ctx.fillRect(0, H * 0.7, W, H * 0.3);
  // проявление из тёмного
  const f = 1 - ep(t, 0, 0.4);
  if (f > 0) { ctx.fillStyle = `rgba(42,32,25,${f})`; ctx.fillRect(0, 0, W, H); }
}
globalThis.TL = { DUR, FPS };
globalThis.renderAt = renderAt;
globalThis.renderFrame = (i) => { renderAt(i / FPS); return outC.toDataURL('image/png'); };
globalThis.ready = Promise.all([`400 30px ${SERIF}`, `700 30px ${SERIF}`, `italic 400 30px ${SERIF}`].map((f) => document.fonts.load(f, 'ӘҒҚҢӨҰҮҺІ'))).then(() => true);

if (!q.has('render')) {
  let t = parseFloat(q.get('t') || '0'), playing = !q.has('t'), last = null;
  const tick = (now) => { if (playing) { if (last != null) t += (now - last) / 1000; if (t > DUR + 1) t = 0; } last = now; renderAt(Math.min(t, DUR)); requestAnimationFrame(tick); };
  addEventListener('keydown', (e) => { if (e.code === 'Space') playing = !playing; if (e.code === 'ArrowRight') t += 1 / FPS; if (e.code === 'ArrowLeft') t = Math.max(0, t - 1 / FPS); });
  globalThis.ready.then(() => requestAnimationFrame(tick));
}
})();
