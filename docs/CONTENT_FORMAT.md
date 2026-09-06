# Формат контента (v1)

Все файлы — YAML, UTF-8. Все тексты для игрока — объекты `{kk, ru, en}`; на этапе черновика `en` может отсутствовать (валидатор — предупреждение), `kk` и `ru` обязательны (ошибка).

## content/curriculum/ent_history.yaml
Дерево тем программы. Узел: `id`, `title`, опционально `children` и `must_know`.
`must_know[]` — проверяемые факты: `{id, kk, ru}`. ID фактов уникальны глобально (`f.<тема>.<буква>`).

## content/episodes/<season>/<episode>.yaml
```
episode: s1e01
title: {kk, ru, en}
topics: [kz.4.1]                # темы, которые серия покрывает
characters:
  - {id, name: {kk, ru}, fiction: bool, note}
scenes:
  - id: sc010
    art: art_s1e01_010          # id картинки в content/media/<season>/manifest.yaml
    covers: [f.4.1.a, ...]      # факты, которые прозвучали в этой сцене
    beats:
      - say: {who, kk, ru, en}
      - choice:
          prompt: {kk, ru, en}
          options:
            - {id, kk, ru, en, set: {var: +n}, goto: sc020}
    quiz: [q_s1e01_001, ...]    # вопросы, задаваемые после сцены
final_test:                     # итоговый мини-тест серии, формат ЕНТ
  single: 10
  context: 10
```
Правила валидатора:
- каждый `goto` существует; нет недостижимых сцен; последняя сцена без `choice` или все её `goto` → `end`
- каждый `fact` у вопроса в `quiz` присутствует в `covers` этой или более ранней сцены серии — иначе ошибка
- каждый факт в `covers` покрыт хотя бы одним вопросом — иначе предупреждение (`--strict`: минимум 3)

## content/questions/<season>/<episode>.yaml
```
- id: q_s1e01_001
  fact: f.4.1.a
  format: single | context      # как на ЕНТ
  context: sc010                # обязателен для format: context
  difficulty: 1..3
  stem: {kk, ru, en}
  options: [{id: a|b|c|d, kk, ru, en, correct: true?}]   # ровно один correct
  explain: {kk, ru, en}         # где происходит обучение
  source: <source_id>#<locator>
  distractor_note: строка       # какую типичную ошибку ловят неправильные варианты
```

## content/sources/registry.yaml
`{id, type: primary|academic|textbook|spec, title, author, year, note}`.
Любой `source:` в вопросах и `covers` фактах должен ссылаться на существующий `id`.

## content/media/<season>/manifest.yaml
`{id, file, kind: scene|card|cover, license, origin, author, seed, prompt_ref, approved_by}`.
