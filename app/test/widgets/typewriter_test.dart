import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/widgets/scene_fx/typewriter.dart';

/// Видимая часть строки: первый отрезок Text.rich, второй — прозрачный хвост.
String _shown(WidgetTester t) {
  final rich = t.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
  return (rich.children!.first as TextSpan).text!;
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('печатает по буквам, на многоточии делает паузу', (t) async {
    final c = TypewriterController();
    await t.pumpWidget(_app(TypewriterText('Ворота… открываются', controller: c, charsPerSecond: 20)));
    expect(_shown(t), 'В', reason: 'первая буква — сразу');
    await t.pump(const Duration(milliseconds: 160)); // ещё 3 буквы по 50 мс
    expect(_shown(t), 'Воро');
    await t.pump(const Duration(milliseconds: 250));
    expect(_shown(t), 'Ворота…', reason: 'до многоточия дошли');
    await t.pump(const Duration(milliseconds: 500));
    expect(_shown(t), 'Ворота…', reason: 'после многоточия — пауза');
    expect(c.isDone, isFalse);
    await t.pump(const Duration(seconds: 3));
    expect(_shown(t), 'Ворота… открываются');
    expect(c.isDone, isTrue);
  });

  testWidgets('complete() сразу показывает всю строку и зовёт onDone', (t) async {
    final c = TypewriterController();
    var done = 0;
    await t.pumpWidget(_app(TypewriterText('Вперёд!', controller: c, onDone: () => done++)));
    await t.pump(const Duration(milliseconds: 30));
    c.complete();
    await t.pump();
    expect(_shown(t), 'Вперёд!');
    expect(c.isDone, isTrue);
    expect(done, 1);
  });

  testWidgets('вёрстка не прыгает: высота текста с первой буквы как у всей строки', (t) async {
    const long = 'Казахи сдержали врага в центре и охватили его крыльями. Знамя Шайбани упало.';
    await t.pumpWidget(_app(const SizedBox(width: 200, child: TypewriterText(long))));
    final h0 = t.getSize(find.byType(Text)).height;
    await t.pump(const Duration(seconds: 10));
    expect(t.getSize(find.byType(Text)).height, h0);
  });

  testWidgets('«Уменьшить движение» — текст сразу целиком', (t) async {
    await t.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: const Scaffold(body: TypewriterText('Ворота открываются изнутри')),
    )));
    expect(_shown(t), 'Ворота открываются изнутри');
  });
}
