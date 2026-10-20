import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/widgets/scroll_buttons.dart';

Widget _app(int rows) => MaterialApp(home: Scaffold(body: ScrollButtons(
      child: ListView(children: [for (var i = 0; i < rows; i++) SizedBox(height: 100, child: Text('row $i'))]),
    )));

void main() {
  testWidgets('короткий список — кнопок нет', (t) async {
    await t.pumpWidget(_app(2));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('scroll-down')), findsNothing);
    expect(find.byKey(const ValueKey('scroll-up')), findsNothing);
  });

  testWidgets('длинный список: ↓ листает на экран, появляется ↑, ↑ возвращает', (t) async {
    await t.pumpWidget(_app(50));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('scroll-up')), findsNothing, reason: 'вверху листать вверх некуда');
    final pos = t.state<ScrollableState>(find.byType(Scrollable)).position;
    await t.tap(find.byKey(const ValueKey('scroll-down')));
    await t.pumpAndSettle();
    expect(pos.pixels, closeTo(pos.viewportDimension * .8, 1));
    expect(find.byKey(const ValueKey('scroll-up')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('scroll-up')));
    await t.pumpAndSettle();
    expect(pos.pixels, 0);
    // до самого конца
    for (var i = 0; i < 20; i++) {
      if (find.byKey(const ValueKey('scroll-down')).evaluate().isEmpty) break;
      await t.tap(find.byKey(const ValueKey('scroll-down')));
      await t.pumpAndSettle();
    }
    expect(pos.pixels, pos.maxScrollExtent);
    expect(find.byKey(const ValueKey('scroll-down')), findsNothing, reason: 'внизу кнопка ↓ пропадает');
  });
}
