import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/core/l10n.dart';
import 'package:nomads_way/data/models/episode.dart';
import 'package:nomads_way/widgets/choice_toasts.dart';

void main() {
  testWidgets('стопка из трёх: черта «+N», потом последствия; акцент у каждой; уходит за 3,06 с', (t) async {
    final toasts = [
      const ChoiceToast(kind: ToastKind.trait, n: 2, text: L10n({'kk': 'Әділдік', 'ru': 'Справедливость'})),
      const ChoiceToast(kind: ToastKind.item, text: L10n({'kk': 'Қасым ханның белгісі', 'ru': 'Знак Касым-хана'})),
      const ChoiceToast(kind: ToastKind.memory, text: L10n({'kk': 'Құдайберген мұны ұмытпайды', 'ru': 'Кудайберген этого не забудет'})),
    ];
    final accents = <ToastKind>[];
    var done = false;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ChoiceToasts(
      toasts: toasts, locale: 'kk', onAccent: (x) => accents.add(x.kind), onDone: () => done = true,
    ))));
    expect(ChoiceToasts.lifeMs(3), 3060);
    await t.pump(const Duration(milliseconds: 900));
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('Әділдік'), findsOneWidget);
    expect(find.text('Құдайберген мұны ұмытпайды'), findsOneWidget);
    expect(accents, [ToastKind.trait, ToastKind.item, ToastKind.memory]);
    await t.pump(const Duration(milliseconds: 2200));
    expect(done, isTrue);
    expect(t.takeException(), isNull);
  });
}
