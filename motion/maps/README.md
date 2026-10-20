# Анимированные карты сезона 1

Задание — `docs/TZ_motion_maps.md`, раскадровка — `content/media/s1/prompts/maps/motion_maps_e01_e02.md`.
Сдача — `content/media/s1/maps/<id>_{kk,ru}.{mp4,png}`, где `<id>` = `map_s1e01_route` (`?map=route`) и
`map_s1e02_south` (`?map=south`).

## Файлы
- `maps.js` — карта рисуется по времени (`renderAt(t)`), слоями на Canvas; после 3,05 с кадр неподвижен.
- `index.html` — превью: `index.html?map=south&lang=ru&t=2.5` (стоп-кадр); без `t` — проигрывание, пробел — пауза, ←/→ — кадр.
- `render.mjs` — кадры в headless Chrome; `BOXES=1` печатает рамки подписей и проверяет поля
  (≥ 64 px по бокам, не выше 8 % и не ниже 60 % высоты).
- `encode.swift` — MP4 (H.264, sRGB, faststart, без звука) + PNG последнего кадра.
- `probe.swift` — проверки ТЗ: размер, поток, faststart, PNG против последнего кадра, неподвижность конца, стоп-кадры.
- `geo/build_geo.py` → `geo/geo.js` — упрощённая география (lon/lat).

## Пересборка
```bash
node render.mjs /tmp/fr route kk                       # 105 кадров
swiftc -O encode.swift -o encodebin && ./encodebin /tmp/fr ../../content/media/s1/maps/map_s1e01_route_kk.mp4 ../../content/media/s1/maps/map_s1e01_route_kk.png 30 9000000
swiftc -O probe.swift -o probebin && ./probebin ../../content/media/s1/maps/map_s1e01_route_kk.mp4 ../../content/media/s1/maps/map_s1e01_route_kk.png /tmp/check
```
Исходные данные для `geo/build_geo.py` (папка `raw/`, в git не кладётся):
Natural Earth `ne_10m_lakes`, `ne_10m_lakes_historic`, `ne_10m_rivers_lake_centerlines` (GeoJSON из
github.com/nvkelso/natural-earth-vector) и `osm_rivers.json` — Overpass:
`rel[waterway=river][name~"^(Шу|Чүй|Чуй|Талас)$"](40,66,46,78);out geom;`.

## Права
- География: Natural Earth — public domain; реки Шу и Талас — © OpenStreetMap contributors, ODbL 1.0.
  Хребты расставлены вручную по координатам. Карты учебника — только референс расположения, не обводились.
- Шрифт: PT Serif (ParaType), SIL Open Font License 1.1 — `fonts/OFL.txt`.
