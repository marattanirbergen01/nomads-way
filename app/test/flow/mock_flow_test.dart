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
import 'package:nomads_way/features/train/mock_screen.dart';
import 'package:nomads_way/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пробник целиком: «Жаттығу» → «Сынақ ҰБТ» → банк качается пакетом → 20 заданий → итог.
/// Контент — настоящий build/ (компилятор + pack.dart), сеть подменена.
Future<Services> _boot(Directory tmp) async {
  SharedPreferences.setMockInitialValues({});
  final store = await ProgressRepository.open();
  final client = MockClient((req) async {
    final f = File('../build${req.url.path}');
    if (!f.existsSync()) return http.Response('nf', 404);
    return http.Response.bytes(f.readAsBytesSync(), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });
  final episodes = EpisodeStore(client: client, baseDir: () async => tmp);
  return Services(
    locale: LocaleController(), store: store,
    content: ContentRepository(baseUrl: 'http://cdn', store: store, client: client, episodes: episodes),
  );
}

Future<void> _settle(WidgetTester t, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) { await t.pump(const Duration(milliseconds: 300)); }
}

/// Длинный текст контекста отодвигает кнопки за пределы построенной части списка — докручиваем.
Future<void> _tapVisible(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
  }
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 100));
  await t.tap(f.first);
  await _settle(t, 2);
}

void main() {
  testWidgets('Сынақ ҰБТ: 10 + 5 + 5, контекст виден на каждом вопросе блока, итог сохраняется', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('nw_mock_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = await _boot(tmp);
    await tester.pumpWidget(NomadsWayApp(services: s));
    await _settle(tester);

    await tester.tap(find.text('Жаттығу').last);
    await _settle(tester);
    expect(find.text('Сынақ ҰБТ'), findsOneWidget);
    expect(find.text('Жылдам жаттығу'), findsOneWidget);

    await tester.tap(find.text('Бастау').first);
    // банк качается пакетом и распаковывается — даём время реальному вводу-выводу
    for (var i = 0; i < 40 && find.text('1 / 20').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('1 / 20'), findsOneWidget);
    expect(File('${tmp.path}/episodes/bank/bank.json').existsSync(), isTrue, reason: 'банк установлен на диск');

    var intros = 0;
    for (var i = 0; i < 20; i++) {
      final block = i < 10 ? null : (i - 10) ~/ 5;
      if (block != null && (i - 10) % 5 == 0) {
        // перед блоком — контекст целиком
        expect(find.text('${i + 1}–${i + 5} тапсырмалар'), findsOneWidget, reason: 'задание ${i + 1}: перед блоком показан контекст');
        expect(find.text('Мәтін ${block + 1}'), findsOneWidget);
        intros++;
        await _tapVisible(tester, find.text('Сұрақтарға өту'));
      }
      expect(find.text('${i + 1} / 20'), findsOneWidget);
      if (block != null) {
        expect(find.text('МӘТІН ${block + 1}'), findsOneWidget, reason: 'задание ${i + 1}: номер текста в шапке');
        final card = find.text('Мәтін ${block + 1}').evaluate().length + find.text('Карта ${block + 1}').evaluate().length;
        expect(card, 1, reason: 'задание ${i + 1}: карточка контекста над вопросом');
        expect(find.text('Жасыру'), findsOneWidget, reason: 'задание ${i + 1}: контекст развёрнут');
      } else {
        expect(find.text('Сұрақтарға өту'), findsNothing);
      }
      await _tapVisible(tester, find.text('A'));
      expect(find.textContaining(RegExp(r'^(Дұрыс|Қате)$')), findsOneWidget, reason: 'вердикт после ответа');
      await _tapVisible(tester, find.text('Жалғастыру'));
    }
    expect(intros, 2);

    // итог: X / 20, части 1–10 и 11–20
    expect(find.textContaining(RegExp(r'^\d+ / 20$')), findsOneWidget);
    expect(find.text('1–10'), findsOneWidget);
    expect(find.text('11–20'), findsOneWidget);
    final t = s.store.tests().single;
    expect(t.kind, 'mock');
    expect(t.total, 20);
    expect(t.questions.length, 20);
    expect(s.store.attempts().every((a) => a.fact.startsWith('ent.')), isTrue, reason: 'банк не пишет факты серий');

    await _tapVisible(tester, find.text('Дайын'));
    await _settle(tester);
    expect(find.textContaining('Соңғысы:', findRichText: true), findsOneWidget, reason: 'последний пробник — только на карточке пробника');
    expect(tester.takeException(), isNull);
  });

  testWidgets('карта открывается на весь экран с увеличением', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final tmp = Directory.systemTemp.createTempSync('nw_zoom_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = await _boot(tmp);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (_) => BankImage(services: s, path: 'media/m_ig_6365.jpg'),
    ))));
    await _settle(tester, 2);
    await tester.tap(find.byType(BankImage));
    await _settle(tester, 3);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _settle(tester, 3);
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
