import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';
import 'package:nomads_way/engine/games/game_spec.dart';
import 'package:nomads_way/features/games/game_screen.dart';

GameSpec _g(String ep, String id) => Episode.fromJson(jsonDecode(File('../build/$ep/episode.json').readAsStringSync()) as Map<String, dynamic>)
    .scenes.expand((s) => s.games).firstWhere((g) => g.id == id);

Future<GameOutcome?> _run(WidgetTester t, GameSpec spec, Future<void> Function() play) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  GameOutcome? got;
  await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: Center(child: ElevatedButton(
    onPressed: () async => got = await GameScreen.play(ctx, spec, 'kk', sound: false), child: const Text('go')))))));
  await t.tap(find.text('go'));
  // у залпа шкала крутится постоянно — «успокоения» экрана не будет, шагаем явно
  for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
  await play();
  for (var i = 0; i < 10; i++) { await t.pump(const Duration(milliseconds: 200)); }
  await t.tap(find.text('Жалғастыру'));
  for (var i = 0; i < 6; i++) { await t.pump(const Duration(milliseconds: 200)); }
  return got;
}

void main() {
  testWidgets('базар: купить нужное → «Келістік» → победа', (t) async {
    final got = await _run(t, _g('s1e02', 'bazaar_syganaq'), () async {
      Future<void> plus(String label) async {
        final row = find.ancestor(of: find.text(label).last, matching: find.byType(Row)).first; // .last — товар, не строка нужд
        final btn = find.descendant(of: row, matching: find.byIcon(Icons.add_circle_outline));
        await t.ensureVisible(btn); await t.tap(btn); await t.pump();
      }
      for (final x in ['Бидай қабы', 'Мата', 'Жебе ұштары', 'Тұз', 'Тұз']) { await plus(x); }
      await t.ensureVisible(find.text('Келістік'));
      await t.tap(find.text('Келістік'));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Жеңіс'), findsOneWidget);
    });
    expect(got, GameOutcome.win);
  });

  testWidgets('тактика: «в лоб» → поражение, сюжет идёт дальше', (t) async {
    final got = await _run(t, _g('s1e02', 'battle_syganaq_1510'), () async {
      await t.tap(find.text('Бәрі бірге қарсы шабу'));
      for (var i = 0; i < 8; i++) { await t.pump(const Duration(milliseconds: 200)); }
      expect(find.text('Сәтсіз'), findsOneWidget);
    });
    expect(got, GameOutcome.lose);
  });

  testWidgets('путь кочевья: «Өткізу» — наполовину, без блокировки', (t) async {
    final got = await _run(t, _g('s1e01', 'route_shu'), () async {
      await t.tap(find.text('Өткізу'));
    });
    expect(got, GameOutcome.partial);
  });

  testWidgets('залп: три выстрела → итог', (t) async {
    final got = await _run(t, _g('s1e02', 'volley_syganaq'), () async {
      for (var i = 0; i < 3; i++) { await t.tap(find.text('Ат!')); for (var k = 0; k < 4; k++) { await t.pump(const Duration(milliseconds: 200)); } }
    });
    expect(got, isNotNull);
  });
}
