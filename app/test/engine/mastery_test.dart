import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/engine/mastery.dart';
import 'package:nomads_way/engine/quiz_runner.dart';

Attempt _a(String f, bool ok, int minutesAgo) =>
    Attempt(questionId: 'q', fact: f, correct: ok, ms: 1000, at: DateTime(2026, 9, 6).subtract(Duration(minutes: minutesAgo)));

void main() {
  const m = Mastery();
  test('факт без попыток = 0, тема учитывает его', () {
    expect(m.fact('f1', []), 0);
    expect(m.topic(['f1', 'f2'], [_a('f1', true, 1)]), 0.5);
  });
  test('свежая ошибка весит больше старых успехов', () {
    final att = [_a('f', true, 30), _a('f', true, 20), _a('f', false, 1)];
    expect(m.fact('f', att), closeTo(0.5, 1e-9));   // 0.3+0.2 из 1.0
  });
  test('три верных подряд = 1.0', () {
    expect(m.fact('f', [_a('f', true, 3), _a('f', true, 2), _a('f', true, 1)]), 1.0);
  });
}
