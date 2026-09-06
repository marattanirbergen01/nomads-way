# Первый запрос для окна «Контент» (скопировать в новую сессию)

Ты работаешь в окне «Контент» репозитория Nomad's Way. Прочитай CLAUDE.md в корне и content/CLAUDE.md — они задают границы: ты редактируешь только content/, не трогаешь app/, tools/, server/.

Задача на сегодня — довести банк вопросов серии s1e01 до трёх вопросов на каждый факт.

1. Прочитай content/curriculum/ent_history.yaml (факты f.4.1.a … f.4.1.i), content/episodes/s1/e01_shu_boyynda.yaml (что прозвучало в каких сценах — поле covers) и content/questions/s1/e01.yaml (12 существующих вопросов).
2. Запусти `cd tools && dart run bin/compile.dart --check` и посмотри предупреждения «факт …: N вопрос(а), цель — 3».
3. Допиши недостающие вопросы по правилам content/CLAUDE.md: другая формулировка того же факта, format чередуй single/context, неправильные варианты — типичные ошибки (записать в distractor_note), explain — 2–3 фразы с причиной, source — из sources/registry.yaml. Сначала kk, потом ru.
4. Добавь новые id в поле quiz нужной сцены (той, где факт прозвучал, или более поздней).
5. Снова запусти компилятор с --check. Цель: ноль предупреждений про покрытие. Затем `dart run bin/compile.dart` без флага, чтобы обновить build/.
6. Не коммить — покажи итог, коммит делает человек.

Flutter/Dart лежат в ~/development/flutter/bin (в PATH через ~/.zshrc).
