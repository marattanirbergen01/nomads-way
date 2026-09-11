import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nomads_way/core/locale_controller.dart';
import 'package:nomads_way/core/services.dart';
import 'package:nomads_way/data/local/episode_store.dart';
import 'package:nomads_way/data/local/progress_repository.dart';
import 'package:nomads_way/data/remote/content_repository.dart';
import 'package:nomads_way/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Сквозной прогон: вкладки → период → серия → сцена → выбор → вопрос.
/// Контент берётся из build/ (собранного компилятором), сеть подменена.
Future<Services> _boot(Directory tmp) async {
  SharedPreferences.setMockInitialValues({});
  final store = await ProgressRepository.open();
  final client = MockClient((req) async {
    final f = File('../build${req.url.path}');
    if (!f.existsSync()) return http.Response('nf', 404);
    return http.Response.bytes(f.readAsBytesSync(), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  // папку под скачанные серии подменяем: тест не должен зависеть от плагина
  final episodes = EpisodeStore(client: client, baseDir: () async => tmp);
  return Services(
    locale: LocaleController(), store: store,
    content: ContentRepository(baseUrl: 'http://cdn', store: store, client: client, episodes: episodes),
  );
}

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) { await t.pump(const Duration(milliseconds: 300)); }
}

void main() {
  testWidgets('вкладки, период, серия, сцена, выбор, вопрос — без исключений', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final tmp = Directory.systemTemp.createTempSync('nw_flow_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = await _boot(tmp);
    await tester.pumpWidget(NomadsWayApp(services: s));
    await _settle(tester);

    // ---- Жол: действующий период и три закрытых
    expect(find.text('Қазақ хандығы'), findsWidgets);
    expect(find.text('Бағдарлама кезеңдері'), findsOneWidget);
    expect(find.text('Ресей империясы құрамындағы Қазақстан'), findsOneWidget);
    expect(find.text('XX ғасырдағы Қазақстан'), findsOneWidget);
    expect(find.text('Тәуелсіз Қазақстан'), findsOneWidget);
    expect(find.textContaining('жақында'), findsNWidgets(3), reason: 'закрытые периоды помечены');
    // закрытый период не открывается
    await tester.tap(find.text('Тәуелсіз Қазақстан'));
    await _settle(tester, 3);
    expect(find.text('Бағдарлама кезеңдері'), findsOneWidget, reason: 'остались на Жол');

    // ---- прыгаем по вкладкам туда-сюда
    for (final tab in ['Жаттығу', 'Дайындық', 'Профиль', 'Жол', 'Дайындық', 'Жаттығу', 'Жол']) {
      await tester.tap(find.text(tab).last);
      await _settle(tester, 3);
    }
    expect(find.text('Бағдарлама кезеңдері'), findsOneWidget);

    // ---- период: одна живая серия и три закрытых
    await tester.tap(find.text('0 / 4'));
    await _settle(tester);
    expect(find.text('Кезең тесті'), findsOneWidget);
    expect(find.textContaining('Шу бойында'), findsWidgets);
    expect(find.text('2 · Бұрындық хан'), findsOneWidget);
    expect(find.text('3 · Қасым хан'), findsOneWidget);
    expect(find.text('4 · Хақназар хан'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(3), reason: 'замки на закрытых сериях');
    // закрытая серия не запускается
    await tester.tap(find.text('3 · Қасым хан'));
    await _settle(tester, 3);
    expect(find.text('Кезең тесті'), findsOneWidget, reason: 'остались на периоде');

    // ---- заставка серии, затем сюжет (в тесте установка недоступна → поток)
    await tester.tap(find.textContaining('Шу бойында').first);
    await _settle(tester, 6);
    expect(find.text("NOMAD'S WAY"), findsOneWidget, reason: 'заставка серии');
    expect(find.text('1 · Шу бойында'), findsOneWidget);
    expect(find.textContaining('Жүктеу'), findsOneWidget, reason: 'серия ещё не скачана');
    await tester.tap(find.textContaining('Жүктеу'));
    await _settle(tester, 12);
    expect(find.text('Бастау'), findsOneWidget, reason: 'скачалась — можно играть');
    expect(find.text('Жүктелген · интернет қажет емес'), findsOneWidget);
    // вместе с серией встал общий пакет: аватары лежат на диске
    expect(await s.episodes.file('common', 'media/s1/avatars/avatar_01_zhylqyshy_calm_bust.png'), isNotNull, reason: 'общий пакет с аватарами');
    expect(s.content.commonSync?.avatars.length, 3, reason: 'три внешности из common.json');
    await tester.tap(find.text('Бастау'));
    await _settle(tester, 12);
    expect(find.text('1457 жыл. Сығанақ түбі.'), findsOneWidget, reason: 'первая реплика сцены');

    // ---- первая реплика дочитана (таймер истёк за время загрузки) — тап листает
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('1457 жыл. Сығанақ түбі.'), findsNothing);
    final second = find.textContaining('Әбілқайыр ханның әскері ойраттардан');
    expect(second, findsOneWidget, reason: 'вторая реплика');

    // ---- пауза перед перемоткой: сразу второй тап не листает
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 150));
    expect(second, findsOneWidget, reason: 'заблокировано таймером');

    // ---- «Артқа» возвращает первую реплику
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('Артқа'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('1457 жыл. Сығанақ түбі.'), findsOneWidget, reason: 'назад на реплику');

    // ---- листаем 5 реплик первой сцены до вопросов
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 4));
      await tester.tapAt(const Offset(195, 300));
      await tester.pump(const Duration(milliseconds: 200));
    }
    // после сцены — вопросы
    expect(find.text('ТЕКСЕРУ'), findsOneWidget, reason: 'после сцены идёт проверка');

    // ---- отвечаем на первый вопрос: любой вариант
    await tester.tap(find.text('A'));
    await _settle(tester, 2);
    expect(find.text('Жалғастыру'), findsOneWidget, reason: 'экран разбора');
    await tester.tap(find.text('Жалғастыру'));
    await _settle(tester, 2);

    // ---- меню трёх линий открывается и закрывается
    // (после вопросов сцена sc012 — снова сюжет)
    for (var i = 0; i < 3; i++) { await tester.tap(find.text('A')); await _settle(tester, 2); await tester.tap(find.text('Жалғастыру')); await _settle(tester, 2); }
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await _settle(tester, 3);
    expect(find.text('Мәзір'), findsOneWidget);
    await tester.tap(find.text('Сақтап шығу'));
    await _settle(tester, 5);

    // ---- вернулись на период, «продолжить» появилось
    expect(find.text('Кезең тесті'), findsOneWidget);
    expect(find.textContaining('жалғастыру'), findsWidgets);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
