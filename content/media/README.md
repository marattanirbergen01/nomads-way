# Медиа

## Раскладка

```
content/media/<season>/
  manifest.yaml     статусы, seed, брифы. В сборку идёт только status: approved
  scenes/           сюжетные кадры серий          art_*
  backgrounds/      обложки, баннеры, фоны экранов cover_*
  avatars/          аватары игрока                 avatar_*
  characters/       портреты исторических лиц      char_*
  maps/             карты                          map_*
  app/              графика приложения             app_icon
  prompts/<то же деление>/<id>.md
  out/              ПЛОСКО — результат tools/pack_media.sh
  raw/              сырые итерации, в git не идут
```

## Что здесь нельзя менять

`out/` остаётся плоским: `compile.dart` копирует `content/media/<season>/out/*.jpg`
в `build/media/<season>/`, а клиент просит файл по имени. Подпапки внутри `out/`
сломают сборку.

Имя файла = `id` из `manifest.yaml`. Подпапка нужна только людям: компилятор
сверяет `art:` сцены с `id`, а не с путём, поэтому id остаётся плоским и
уникальным на весь сезон.

## Правила

- Исходник кладётся в свою папку по типу: `s1/avatars/<id>.png`.
- У аватаров два файла на id: `<id>.png` с фоном — для `AvatarCircle` (кружок клипует сам),
  и `<id>_bust.png` с прозрачным фоном — для `AvatarBust` поверх сцены. Вырез делается
  из утверждённого кадра: `shortcuts run RemoveBG -i <id>.png -o <id>_bust.png --output-type public.png`.
  `_bust` — производная, отдельной записи в манифесте не имеет; seed и виза те же, что у `<id>`.
- Промпт — зеркально: `s1/prompts/avatars/<id>.md`.
- Seed и статус — в `manifest.yaml` после утверждения кадра.
- Происхождение и лицензия — `content/sources/media.yaml`. Нет записи — нет в сборке.
- Инструмент по умолчанию — Draw Things локально, обёртка `tools/dt_gen.py`.
- Юрты в сценах: гладкий купол, шанырак вровень с войлоком, **никаких жердей над крышей**
  (правило с 2026-09-12). В промптах — `smooth shallow domed roof ... small flat wooden ring
  that lies flush with the felt`; слова `crowns`, `poles` в описании крыши не употреблять.
- Лица в широких сценах промптом не берутся (бороды по умолчанию) — снимаются правкой
  готового кадра в ChatGPT/Gemini, происхождение записывается как гибридное.
