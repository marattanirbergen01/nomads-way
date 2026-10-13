import 'dart:convert';
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

    // ---- Жол: действующий период и закрытые (названия — из плана в build/, план ещё меняется)
    final planned = [
      for (final t in jsonDecode(File('../build/curriculum.json').readAsStringSync()) as List)
        if ((t as Map)['status'] == 'planned' && !(t['id'] as String).substring(3).contains('.')) (t['title'] as Map)['kk'] as String,
    ];
    expect(planned, isNotEmpty);
    expect(find.text('Қазақ хандығы'), findsWidgets);
    expect(find.text('Бағдарлама кезеңдері'), findsOneWidget);
    expect(find.text(planned.first), findsOneWidget);
    expect(find.textContaining('жақында'), findsWidgets, reason: 'закрытые периоды помечены');
    // закрытый период не открывается
    await tester.tap(find.text(planned.first));
    await _settle(tester, 3);
    expect(find.text('Бағдарлама кезеңдері'), findsOneWidget, reason: 'остались на Жол');

    // ---- прыгаем по вкладкам туда-сюда
    for (final tab in ['Жаттығу', 'Дайындық', 'Профиль', 'Жол', 'Дайындық', 'Жаттығу', 'Жол']) {
      await tester.tap(find.text(tab).last);
      await _settle(tester, 3);
    }
    expect(find.text('Бағдарлама кезеңдері'), findsOneWidget);

    // ---- период: одна живая серия, остальные закрытые (сколько их — по каталогу)
    final s1 = [for (final e in jsonDecode(File('../build/catalog.json').readAsStringSync()) as List) if ((e as Map)['season'] == 's1') e];
    final closed = s1.where((e) => e['planned'] == true).toList();
    await tester.tap(find.text('0 / ${s1.length}'));
    await _settle(tester);
    expect(find.text('Кезең тесті'), findsOneWidget);
    expect(find.textContaining('Шу бойында'), findsWidgets);
    final next = closed.first;
    expect(find.text('${next['number']} · ${(next['title'] as Map)['kk']}'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets, reason: 'замки на закрытых сериях');
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

    // ---- «Артқа» перечитывает первую реплику, вперёд — возвращает к живой
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('Артқа'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('1457 жыл. Сығанақ түбі.'), findsOneWidget, reason: 'перечитываем первую');
    expect(find.text('ҚАЙТА ОҚУ'), findsOneWidget, reason: 'помечено как просмотр');
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(second, findsOneWidget, reason: 'вернулись к живой реплике');
    expect(find.text('ҚАЙТА ОҚУ'), findsNothing);

    // ---- едем по сюжету, что бы ни было на экране: реплика, развилка, вопрос, разбор.
    // Сценарий ещё меняется, поэтому тест не знает порядок сцен — он просто ведёт игру.
    var answered = 0, chosen = 0, said = 0;
    for (var step = 0; step < 90 && (answered < 3 || chosen < 1); step++) {
      if (find.text('Жалғастыру').evaluate().isNotEmpty && find.textContaining('дереккөз').evaluate().isEmpty
          && find.byType(ListView).evaluate().isNotEmpty && find.text('A').evaluate().isEmpty
          && find.text('Дұрыс').evaluate().isNotEmpty || find.text('Қате').evaluate().isNotEmpty) {
        await tester.tap(find.text('Жалғастыру'));            // разбор → дальше
        await _settle(tester, 2);
      } else if (find.text('A').evaluate().isNotEmpty) {
        await tester.tap(find.text('A'));                     // вопрос → любой ответ
        answered++;
        await _settle(tester, 2);
      } else if (find.text('ТАҢДА').evaluate().isNotEmpty) {
        final opts = find.byType(OutlinedButton);
        if (opts.evaluate().isNotEmpty) {
          await tester.pump(const Duration(seconds: 4));       // развилка ждёт таймер
          await tester.tap(opts.first);
        } else {
          await tester.tapAt(const Offset(195, 200));          // развилка двумя кадрами — верхний
        }
        chosen++;
        await _settle(tester, 3);
        // ответ на выбор — обычная реплика аватара, без крупного повтора варианта
        expect(find.text('ТАҢДА'), findsNothing, reason: 'развилка закрылась');
        expect(find.text('СЕНІҢ ТАҢДАУЫҢ'), findsNothing, reason: 'отдельного экрана выбора нет');
        expect(find.byIcon(Icons.menu_rounded), findsOneWidget, reason: 'это обычный экран реплики');
        // назад после выбора — только чтение, развилка не возвращается
        if (find.text('Артқа').evaluate().isNotEmpty) {
          await tester.tap(find.text('Артқа'));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('ТАҢДА'), findsNothing, reason: 'выбор окончательный');
          for (var k = 0; k < 4 && find.text('ҚАЙТА ОҚУ').evaluate().isNotEmpty; k++) {
            await tester.tapAt(const Offset(195, 300));
            await tester.pump(const Duration(milliseconds: 200));
          }
        }
      } else if (find.byIcon(Icons.menu_rounded).evaluate().isNotEmpty) {
        await tester.pump(const Duration(seconds: 4));         // реплика: дочитали
        await tester.tapAt(const Offset(195, 300));
        said++;
        await tester.pump(const Duration(milliseconds: 250));
      } else {
        await _settle(tester, 2);
      }
    }
    expect(answered, greaterThanOrEqualTo(3), reason: 'ответили минимум на три вопроса');
    expect(chosen, greaterThanOrEqualTo(1), reason: 'прошли хотя бы одну развилку');
    expect(said, greaterThan(3), reason: 'листали реплики');

    // ---- меню трёх линий открывается и закрывается
    // дойти до сюжетного экрана
    for (var step = 0; step < 20 && find.byIcon(Icons.menu_rounded).evaluate().isEmpty; step++) {
      if (find.text('A').evaluate().isNotEmpty) { await tester.tap(find.text('A')); await _settle(tester, 2); }
      else if (find.text('Жалғастыру').evaluate().isNotEmpty) { await tester.tap(find.text('Жалғастыру').first); await _settle(tester, 2); }
      else { await _settle(tester, 2); }
    }
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await _settle(tester, 3);
    expect(find.text('Мәзір'), findsOneWidget);
    await tester.tap(find.text('Сақтап шығу'));
    await _settle(tester, 5);

    // ---- вернулись на период, «продолжить» появилось
    expect(find.text('Кезең тесті'), findsOneWidget);
    expect(find.textContaining('жалғастыру'), findsWidgets);

    // ---- снова в серию: позиция та же, а «Артқа» перечитывает прочитанное ДО выхода
    await tester.tap(find.textContaining('Шу бойында').first);
    await _settle(tester, 6);
    await tester.tap(find.textContaining('Жалғастыру').first);
    await _settle(tester, 12);
    // доехать до экрана реплики: позиция могла сохраниться на вопросе или развилке
    for (var step = 0; step < 12 && find.text('Артқа').evaluate().isEmpty; step++) {
      if (find.text('A').evaluate().isNotEmpty) { await tester.tap(find.text('A')); await _settle(tester, 2); }
      else if (find.text('ТАҢДА').evaluate().isNotEmpty) {
        await tester.pump(const Duration(seconds: 4));
        final opts = find.byType(OutlinedButton);
        if (opts.evaluate().isNotEmpty) { await tester.tap(opts.first); } else { await tester.tapAt(const Offset(195, 200)); }
        await _settle(tester, 3);
      }
      else if (find.text('Жалғастыру').evaluate().isNotEmpty) { await tester.tap(find.text('Жалғастыру').first); await _settle(tester, 2); }
      else { await _settle(tester, 2); }
    }
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget, reason: 'снова в сюжете');
    expect(find.text('Артқа'), findsOneWidget);
    await tester.tap(find.text('Артқа'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('ҚАЙТА ОҚУ'), findsOneWidget, reason: 'список прочитанного пережил выход из серии');
    await tester.tapAt(const Offset(195, 300));
    await tester.pump(const Duration(milliseconds: 250));
    // выходим обратно на период — замки на месте
    await tester.tap(find.byIcon(Icons.menu_rounded));
    await _settle(tester, 3);
    await tester.tap(find.text('Сақтап шығу'));
    await _settle(tester, 5);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
