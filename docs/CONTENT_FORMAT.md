# Формат контента (v1)

Все файлы — YAML, UTF-8. Все тексты для игрока — объекты `{kk, ru}`, оба обязательны (ошибка). Английского в игре не будет (DECISIONS 2026-10-13).

## content/curriculum/ent_history.yaml
Дерево тем программы. Узел: `id`, `title`, опционально `children` и `must_know`.
`must_know[]` — проверяемые факты: `{id, kk, ru}`. ID фактов уникальны глобально (`f.<тема>.<буква>`).

## content/episodes/<season>/<episode>.yaml
```
episode: s1e01
title: {kk, ru}
topics: [kz.4.1]                # темы, которые серия покрывает
characters:
  - {id, name: {kk, ru}, fiction: bool, note, avatar: bool?, default_name: {kk, ru}?, portrait: media_id?}
# portrait — портрет в кружке у реплик. Без поля берётся char_<id> из media/manifest.yaml (kind character, approved).
# avatar: true — персонаж-аватар игрока; в его репликах и prompt допустим плейсхолдер {player},
# клиент подставляет имя из профиля (default_name — пока имя не задано). Имя не склонять.
scenes:
  - id: sc010
    art: art_s1e01_010          # id картинки в content/media/<season>/manifest.yaml
    covers: [f.4.1.a, ...]      # факты, которые прозвучали в этой сцене
    title: {kk, ru}          # необязательно: название сцены для шапки плеера
    layer: history | personal    # необязательно: personal — пустой covers и без quiz, history — covers ≥ 1
    pan: 0..100                  # необязательно: горизонтальное панорамирование кадра (50 = центр)
    avatar: left | right         # необязательно: сторона фигуры аватара (по умолчанию left)
    art_when:                    # необязательно: кадр по условию на переменные сюжета; первое совпавшее, иначе art
      - { if: "yurt_river", art: art_s1e01_045_river }
      - { if: "loyalty >= 2 && caution == 0", art: art_s1e01_045_loyal }
    # Условие: flag (> 0), !flag (== 0), var op число (== != < <= > >=), части через &&.
    # Отсутствующая переменная равна 0. Переменные задаются в set у вариантов выбора.
    beats:
      - say: {who, kk, ru, emotion?, when?}
        # emotion: calm | joy | alarm | sorrow | resolve — состояние аватара в этой реплике
        #          (синоним emo). Кадра «resolve» у аватаров пока нет — клиент покажет calm.
        # when: условие на переменные сюжета (тот же синтаксис, что у art_when); реплика без when звучит всегда.
        #       Факты из covers должны звучать в безусловных репликах — компилятор предупредит.
      - choice:
          prompt: {kk, ru}
          options:
            - {id, kk, ru, set: {var: +n}, goto: sc020, art: art_id?, reply: {kk, ru, emotion?}?}
              # art у ОБЕИХ опций → развилка двумя кадрами
              # reply — что произошло после выбора: текст экрана «выбор сделан», emotion — состояние аватара на нём
    quiz: [q_s1e01_001, ...]    # вопросы, задаваемые после сцены
final_test:                     # итоговый мини-тест серии, формат ЕНТ
  single: 10
  context: 10
```
Правила валидатора:
- каждый `goto` существует; нет недостижимых сцен; последняя сцена без `choice` или все её `goto` → `end`
- каждый `fact` у вопроса в `quiz` присутствует в `covers` этой или более ранней сцены серии — иначе ошибка
- каждый факт в `covers` покрыт хотя бы одним вопросом — иначе предупреждение (`--strict`: минимум 3)

## content/fx/<season>.yaml — живой кадр
Камера, частицы и ударные реплики по сценам. Отдельный файл: «Сборка» студии перезаписывает
`content/episodes/`, а этот файл не трогает. Компилятор вливает его в `episode.json`.
Сцена без записи «дышит» — едва заметно приближается и отдаляется.
```
s1e02:                          # id серии
  sc100:                        # id сцены
    camera: push                # still | breathe | push | pull | pan — или объект:
    camera: {move: push, zoom: 1.18, dur: 16, pan_y: 55}
      # zoom 1..1.5 — наибольшее приближение; dur 3..60 — секунд на проход туда (обратно столько же)
      # from, to 0..100 — горизонталь в единицах pan (для pan: откуда и куда едет кадр)
      # pan_y 0..100 — вертикаль кадра (0 — верх, 100 — низ)
    fx: [fog, {type: snow, wind: 1.2, density: 0.8}]
      # type: dust | sand | fog | snow | embers | firelight
      # density 0..3 — множитель количества; wind -3..3 — ветер (1 вправо, -1 влево)
      # embers (искры) и firelight (отсвет огня) ставятся в точку картинки: x, y 0..1 — доли кадра;
      #   r 0.05..1.5 — радиус отсвета в долях ширины. Огонь едет вместе с камерой, погода — нет.
    impact: ["Вперёд!"]         # ударные реплики: кусок текста (kk или ru), должен найтись ровно в одной реплике сцены
      # перед ударной репликой пауза длиннее, печатается медленнее
```
Запись о серии, которой нет, — предупреждение. Ошибка — неизвестная сцена, поле или тип, значение вне диапазона,
кусок текста `impact`, который не нашёлся или нашёлся в двух репликах.

## content/questions/<season>/<episode>.yaml
```
- id: q_s1e01_001
  fact: f.4.1.a
  format: single | context      # как на ЕНТ
  context: sc010                # обязателен для format: context
  difficulty: 1..3
  stem: {kk, ru}
  options: [{id: a|b|c|d, kk, ru, correct: true?}]   # ровно один correct
  explain: {kk, ru}         # где происходит обучение
  source: <source_id>#<locator>
  distractor_note: строка       # какую типичную ошибку ловят неправильные варианты
```

## content/bank/<name>.yaml — банк пробника ЕНТ
Вопросы для пробного ЕНТ вне серий. Не привязаны к сюжету: правило `fact` ↔ `covers` к ним не
применяется, `explain` и `distractor_note` нет. Тексты — только `kk` (так в исходных тестах школы).
Первый банк — `school_tests.yaml`, генерируется скриптом, руками не правится. Картинки — `content/bank/media/`.
```
source: <source_id>                 # одна запись в registry.yaml на весь банк
contexts:
  - id: c20252-1
    text: {kk}                      # текст контекста; необязателен, если есть image
    image: media/m_ig_6365.jpg      # необязательно: карта/схема, путь от content/bank/
    caption: {kk}                   # необязательно: подпись к картинке
    src: строка                     # файл и вариант, откуда текст
    questions: [b5cefcbc, ...]      # вопросы этого текста, в исходном порядке
questions:
  - id: b5cefcbc                    # префикс b — банк; уникален во всём build
    format: single | context
    context: c20252-1               # только у context; вопрос обязан быть в questions этого контекста
    stem: {kk}
    options: [{kk}, ...]            # 3–6 вариантов, обычно 4
    answer: 0                       # индекс правильного варианта в options
    shuffle: false                  # необязательно: варианты ссылаются друг на друга, не перемешивать
    image: media/m_ig_159.jpg       # необязательно: своя картинка у вопроса
    topic: 51                       # тема спецификации ЕНТ (1–55), может быть null
    season: 4                       # сезон и серия плана v2
    episode: s4e01
    check: true                     # необязательно: ответ под сомнением — в пробник не брать
    image_missing: true             # необязательно: карта/схема была, но в файле её нет — в пробник не брать
    note: строка                    # необязательно: пометка редактора
    src: [строка, ...]              # где вопрос встречался в исходных файлах
```

Поле `source` вопроса серии может перечислять несколько ссылок через `;`: `bank:school_tests_2026; tb06_ru#§30,с.126`
(вопрос взят из банка школы и подтверждён учебником). Каждая ссылка — `<id из registry>[#место]`, префикс `bank:` — пометка
«сборник тестов». Компилятор проверяет каждую.

## content/sources/registry.yaml
`{id, type: primary|academic|textbook|spec|tests, title, author, year, note}`. `tests` — сборники тестов (источник банка пробника, не фактов).
Любой `source:` в вопросах и `covers` фактах должен ссылаться на существующий `id`.

## content/media/<season>/ — раскладка
```
scenes/<id>.png|jpg        кадры сцен и вариантов       → out/<id>.jpg (1920)
backgrounds/<id>.*         обложки, баннер              → out/<id>.jpg (1600)
maps/<id>.png              карты, без сжатия            → out/<id>.png (как есть)
maps/<id>_<lang>.mp4|.png   анимированная карта (kk, ru) + её последний кадр → out/ как есть; 1080×1890, 3,5 с (docs/TZ_motion_maps.md)
avatars/<id>.png           портрет аватара для кружка   → out/avatars/<id>.jpg (512)
avatars/<id>_bust.png      фигура по пояс, альфа        → out/avatars/<id>_bust.png (960)
characters/<id>.png        портреты исторических лиц    → out/characters/<id>.jpg (512)
```
`sh tools/pack_media.sh` пересобирает out/ с нуля. Аватары и портреты уходят в общий пакет
`common.zip`, остальное — в бандл серии. Расширение не-jpg кадра (карта) клиент узнаёт из episode.json.

## content/media/<season>/manifest.yaml
`{id, file, kind: scene|card|cover, license, origin, author, seed, prompt_ref, approved_by}`.

## content/scripts/<season>/yaml/bank_map.yaml — вопросы банка школы в сценах
`<серия>: {<сцена>: [id вопросов банка]}`. Компилятор кладёт их в вопросы серии для итогового теста (в `quiz` сцены не ставит — сюжет не прерывается); сцена — где прозвучал ответ, проверяется.
Правила серий (`fact` ↔ `covers`, `explain`, `distractor_note`) к ним не применяются; `ru` — из перевода банка.
Пропускаются с предупреждением: `check`, `image_missing`, контекстные (без текста не решаются), повторы.
Ошибка: сцены нет, вопроса нет в банке, сцена `personal`. Файл отдельно от серий: «Сборка» студии перезаписывает
`content/episodes/`. Ключи `skipped`, `duplicates` — пометки редактора, компилятор их не читает.
