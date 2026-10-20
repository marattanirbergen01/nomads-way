# Собирает geo.js (lon/lat, упрощено) из Natural Earth 10m (public domain) и OSM (ODbL).
# Скачать исходники — см. README. Запуск: python3 -I build_geo.py
import json, math, os
here = os.path.dirname(os.path.abspath(__file__))
BOX = (55.0, 36.0, 82.0, 50.0)

def flat_lines(g):
    t, c = g['type'], g['coordinates']
    if t == 'LineString': return [c]
    if t == 'MultiLineString': return c
    if t == 'Polygon': return [c[0]]
    if t == 'MultiPolygon': return [p[0] for p in c]
    return []

def dp(pts, eps):
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; dx, dy = b[0] - a[0], b[1] - a[1]; L = math.hypot(dx, dy) or 1e-12
    best, bi = -1, 0
    for i in range(1, len(pts) - 1):
        p = pts[i]; d = abs(dy * (p[0] - a[0]) - dx * (p[1] - a[1])) / L
        if d > best: best, bi = d, i
    if best <= eps: return [a, b]
    return dp(pts[:bi + 1], eps)[:-1] + dp(pts[bi:], eps)

def inside(p): return BOX[0] <= p[0] <= BOX[2] and BOX[1] <= p[1] <= BOX[3]
def r(p): return [round(p[0], 3), round(p[1], 3)]

def ne(name, file, eps=0.01):
    d = json.load(open(os.path.join(here, '..', 'raw', file)))
    out = []
    for ft in d['features']:
        g = ft['geometry']
        if not g or ft['properties'].get('name') != name or ft['properties'].get('featurecla') == 'Lake Centerline': continue
        for ln in flat_lines(g):
            if not any(inside(p) for p in ln): continue
            if ln[0] == ln[-1]:   # замкнутый контур: упрощать двумя половинами
                h = len(ln) // 2; s = dp(ln[:h + 1], eps)[:-1] + dp(ln[h:], eps)
            else: s = dp(ln, eps)
            out.append([r(p) for p in s])
    return out

def osm(name):
    d = json.load(open(os.path.join(here, '..', 'raw', 'osm_rivers.json')))
    out = []
    for e in d['elements']:
        if e['tags'].get('name:en') != name: continue
        for m in e['members']:
            if m.get('type') == 'way' and 'geometry' in m and m.get('role', '') in ('', 'main_stream'):
                out.append([r(p) for p in dp([[q['lon'], q['lat']] for q in m['geometry']], 0.008)])
    return out

def chain(lines):
    # склеить отрезки реки в длинные линии по совпадающим концам
    lines = [l[:] for l in lines if len(l) > 1]; res = []
    while lines:
        cur = lines.pop(0); grew = True
        while grew:
            grew = False
            for i, l in enumerate(lines):
                if l[0] == cur[-1]: cur += l[1:]
                elif l[-1] == cur[-1]: cur += l[::-1][1:]
                elif l[-1] == cur[0]: cur = l[:-1] + cur
                elif l[0] == cur[0]: cur = l[::-1][:-1] + cur
                else: continue
                lines.pop(i); grew = True; break
        res.append(cur)
    return res

G = {
    'aral': ne('Aral Sea', 'ne_10m_lakes_historic.geojson', 0.008),     # историческая береговая линия
    'balkhash': ne('Lake Balkhash', 'ne_10m_lakes.geojson', 0.008),
    'issyk': ne('Issyk-Kul', 'ne_10m_lakes.geojson', 0.006),
    'alakol': ne('Alakol', 'ne_10m_lakes.geojson', 0.008),
    'syr': chain(ne('Syr  Darya', 'ne_10m_rivers_lake_centerlines.geojson')),
    'naryn': chain(ne('Naryn', 'ne_10m_rivers_lake_centerlines.geojson')),
    'amu': chain(ne('Amu  Darya', 'ne_10m_rivers_lake_centerlines.geojson')),
    'zeravshan': chain(ne('Zarafshon', 'ne_10m_rivers_lake_centerlines.geojson')),
    'ili': chain(ne('Ile', 'ne_10m_rivers_lake_centerlines.geojson')),
    'chu': chain(osm('Chu')),
    'talas': chain(osm('Talas')),
}
with open(os.path.join(here, 'geo.js'), 'w') as f:
    f.write('// Сгенерировано build_geo.py. Natural Earth 10m (public domain); Шу и Талас — © OpenStreetMap contributors, ODbL.\n')
    f.write('globalThis.GEO = ' + json.dumps(G, separators=(',', ':')) + ';\n')
for k, v in G.items(): print(k, len(v), sum(len(x) for x in v))
