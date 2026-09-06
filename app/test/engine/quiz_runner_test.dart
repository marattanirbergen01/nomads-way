import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/question.dart';
import 'package:nomads_way/engine/quiz_runner.dart';

Question _q(String id, String fmt) => Question.fromJson({
      'id': id, 'fact': 'f', 'topic': 't', 'format': fmt, 'context': null, 'difficulty': 1,
      'stem': {'kk': '?'}, 'explain': {'kk': '!'}, 'source': 's',
      'options': [
        {'id': 'a', 'text': {'kk': 'a'}, 'correct': false},
        {'id': 'b', 'text': {'kk': 'b'}, 'correct': true},
        {'id': 'c', 'text': {'kk': 'c'}, 'correct': false},
        {'id': 'd', 'text': {'kk': 'd'}, 'correct': false},
      ],
    });

void main() {
  test('варианты перемешаны, ответ фиксируется, неверный не блокирует', () {
    final r = QuizRunner([_q('1', 'single'), _q('2', 'context')], random: Random(1));
    final p = r.current()!;
    expect(p.options.map((o) => o.id).toSet(), {'a', 'b', 'c', 'd'});
    expect(r.answer('a').correct, isFalse);
    expect(r.index, 1);                                // пошли дальше несмотря на ошибку
    expect(r.answer('b').correct, isTrue);
    expect(r.done, isTrue);
    expect(r.correctCount, 1);
    expect(r.attempts.length, 2);
  });

  test('итоговый тест: n single + m context, при малом банке — всё что есть', () {
    final bank = [_q('1', 'single'), _q('2', 'single'), _q('3', 'context')];
    final t = QuizRunner.composeFinal(bank, single: 10, context: 10, random: Random(1));
    expect(t.length, 3);
    expect(t.where((q) => q.format == QFormat.single).length, 2);
  });
}
