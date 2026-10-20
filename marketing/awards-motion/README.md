# Анимация наград

Готовые ролики: `out/award-*.mp4` (1080×1920, 2,6 с, 60 fps, H.264 + AAC). Раскадровка: `STORYBOARD.md`.

Превью в браузере: открыть `index.html` (пробел — пауза, ←/→ — кадр, 1–4 — награда, `?award=2&t=1.5` — стоп-кадр).

Пересборка (нужны Chrome, node, swiftc):

```bash
node audio.mjs out                                    # звук → out/award0..3.wav
node render.mjs /tmp/frames0 0                        # кадры награды 0 (0..3)
swiftc -O encode.swift -o encodebin && ./encodebin /tmp/frames0 out/award0.wav out/award-mergen.mp4
swiftc -O probe.swift -o probebin && ./probebin out/award-mergen.mp4 /tmp/check 0.5,1.45,2.58
```

Тайминги общие для картинки и звука — `timeline.js`.
