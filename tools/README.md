# tools

```
dart pub get
dart run bin/compile.dart            # content/ → build/<episode>/{episode,questions,manifest}.json
dart run bin/compile.dart --check    # только валидация, ничего не пишет
dart run bin/compile.dart --strict   # предупреждения о покрытии становятся ошибками (3 вопроса на факт)
python3 serve.py                     # раздаёт build/ на http://localhost:8787 с CORS — для flutter run -d chrome
```
