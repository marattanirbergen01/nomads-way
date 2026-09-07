# Nomad's Way

История Казахстана как сюжетная игра с вопросами формата ЕНТ.

| Зона | Что внутри | Кто трогает |
|---|---|---|
| `app/` | Flutter-клиент | окно «Код» |
| `tools/` | Dart CLI: компилятор, валидатор, сборщик бандлов | окно «Код» |
| `server/` | Supabase: миграции, RLS | окно «Код» |
| `content/` | дерево тем, сценарии, вопросы, источники, медиа | окно «Контент» |
| `docs/` | план, решения, стиль | общее |

Полный план: см. `docs/PLAN.md`.

## Запуск в разработке

Одной командой (собирает контент, поднимает CDN и приложение, открывает Chrome):

```bash
sh scripts/dev.sh
```

Вручную:

```bash
# 1. собрать контент → build/
cd tools && dart pub get && dart run bin/compile.dart

# 2. раздать build/ как CDN (отдельный терминал)
python3 tools/serve.py            # http://localhost:8787

# 3. приложение в Chrome (Xcode / Android Studio не нужны)
cd app && flutter pub get && flutter run -d chrome

# тесты движков
cd app && flutter test
```

Flutter SDK: `~/development/flutter` (добавлен в PATH через `~/.zshrc`).
