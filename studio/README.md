# Студия — конструктор серий

Веб-приложение для команды: сезоны → серии → сцены → реплики. Несколько человек правят
одновременно, комментируют каждую сцену и реплику, задают эмоцию аватара, утверждают кадры
и собирают серию в `content/` одной кнопкой. Агенты (окна Claude Code) работают через CLI.

## Как устроено

- **База студии — источник правды для черновика.** `content/` в репозитории — источник правды
  для утверждённого. Между ними одна ручка: «Сборка» (см. ниже). YAML руками после этого не правят.
- Один процесс Node (Hono + WebSocket) + SQLite-файл `data/studio.db` + React-фронтенд.
  Никаких внешних сервисов. Бэкап = копия `data/`.
- Гранулярность правок — **реплика**. У каждой записи `version`; сохранение с устаревшей версией
  показывает обе версии, пользователь выбирает. Все изменения прилетают всем открытым вкладкам.
- Картинки берутся прямо из `content/media/<season>/out/` (и из `data/uploads/`, если загружены через студию).

## Запуск локально

```bash
cd studio
npm install
cp .env.example .env         # при необходимости поправить REPO_DIR
npm run dev                  # сервер :8795 + vite :8796 → http://localhost:8796
```

Первый запуск: импортирует все серии из `content/episodes/` и создаёт пользователя `admin`
(пароль `admin` или `ADMIN_PASSWORD` из окружения). Пользователей заводит админ на странице «Команда».

Продакшен: `npm run build && npm start` — один процесс на :8795 отдаёт и API, и фронтенд.

## Роли

| Роль | Правит | Утверждает |
|---|---|---|
| Сценарист | сцены, реплики, развилки, персонажи, статусы сцен | — |
| Историк | covers, quiz, вопросы | «Текст утверждён» у сцены, виза серии (`approved_by`) |
| Медиа | кадры, промпты, seed, загрузка файлов | кадр approved |
| Админ | всё | всё + сборка + команда |
| Агент-сценарий / Агент-медиа | как сценарист / медиа, правки помечены «предложено агентом» | — |
| Наблюдатель | ничего | — |

Комментировать могут все.

## Статусы

Сцена: `черновик → на вычитке → текст утверждён → медиа готово → готова`.
Серия: `черновик → на утверждении → утверждена → собрана`.

## Сборка серии

Кнопка «Сборка» в серии (право `episode.build`). Что происходит:

1. Проверки студии: виза историка, все сцены `готова`, у каждой сцены утверждённый кадр с записью
   источника, тексты kk/ru не пустые, развилки ведут в существующие сцены. Ошибка — ничего не пишется.
2. Запись в репозиторий: `content/episodes/<s>/<slug>.yaml`, `content/questions/<s>/<eNN>.yaml`,
   `content/media/<s>/manifest.yaml` (слияние по id), `content/sources/media.yaml` (слияние),
   файлы и промпты медиа, загруженных через студию.
3. Упаковка новых медиа в `out/` (те же правила, что `tools/pack_media.sh`, но через sharp — работает на Linux).
4. `dart run bin/compile.dart --check` → при ошибке откат записанных файлов и лог в интерфейсе.
5. `compile.dart` + `pack.dart` → `build/`.
6. `git commit` только этих файлов; `git push`, если включён (`GIT_PUSH=1` или галочка).
7. В базе фиксируется редакция N со снимком серии; статус серии — «собрана».

## CLI для агентов и терминала

```bash
node studio/bin/studio.mjs status                 # серии
node studio/bin/studio.mjs status s1e02           # готовность одной серии
node studio/bin/studio.mjs pull s1e02             # → studio/work/s1e02/{episode,questions}.yaml
node studio/bin/studio.mjs push s1e02             # правки из YAML → студия (помечаются «от агента»)
node studio/bin/studio.mjs comments s1e02         # открытые комментарии — контекст, не задание
node studio/bin/studio.mjs media list s1
node studio/bin/studio.mjs media upload s1 art_s1e02_010 kadr.png --seed 123 --prompt prompt.md --brief "…"
```

Токен: админ → «Команда» → у пользователя-агента «API-токен» → в `studio/.env`: `STUDIO_TOKEN=…`
(и `STUDIO_URL=https://…`, если студия на сервере). Удобный алиас: `alias studio='node ~/nomads-way/studio/bin/studio.mjs'`.

`push` ничего не удаляет: реплики, которых нет в присланном YAML, остаются в конце сцены с пометкой;
`--replace` удаляет их.

У каждого агента свой токен. Сценарий — `STUDIO_TOKEN` в `studio/.env`; медиа — `studio/.env.media`,
вызов `STUDIO_ENV=.env.media node studio/bin/studio.mjs media upload …`. `studio whoami` показывает, чей токен в ходу. Сцены, отсутствующие в YAML, не трогаются.

## Сервер (Hetzner)

См. `deploy/`: `setup.sh` ставит Docker, создаёт deploy-ключ, клонирует репозиторий в `/srv/nomads-way`,
поднимает студию за Caddy с HTTPS по адресу `<ip>.sslip.io`. Обновление — `deploy/update.sh`,
бэкап — `deploy/backup.sh` (cron).

## Структура

```
src/server/   index (HTTP+WS), routes, service (правки), importer (YAML→БД), exporter (БД→YAML),
              push (YAML от агентов), build (сборка), media, auth, ws, db
src/client/   React: pages/ (Episodes, Episode, Media, Users, Login), components/ (SceneEditor, BeatCard,
              ChoiceCard, SidePanel: превью/комментарии/кадр/история, Build…)
bin/          studio.mjs — CLI
deploy/       Dockerfile, docker-compose, Caddyfile, setup/update/backup
data/         база, загрузки (в git не идёт)
```
