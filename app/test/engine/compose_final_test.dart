import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/question.dart';
import 'package:nomads_way/engine/quiz_runner.dart';

Question _q(String id, String fact) => Question.fromJson({
      'id': id, 'fact': fact, 'topic': null, 'format': 'single', 'context': null, 'difficulty': 1,
      'stem': {'kk': id}, 'explain': <String, dynamic>{}, 'source': 's',
      'options': [{'id': 'a', 'text': {'kk': 'a'}, 'correct': true}, {'id': 'b', 'text': {'kk': 'b'}, 'correct': false}],
    });

void main() {
  test('итоговый тест: один вопрос на факт, пока фактов хватает; без повторов', () {
    final pool = [for (var f = 0; f < 6; f++) for (var k = 0; k < 4; k++) _q('f$f-$k', 'fact$f')];
    for (var seed = 0; seed < 200; seed++) {
      final t = QuizRunner.composeFinal(pool, single: 6, context: 0, random: Random(seed));
      expect(t.map((q) => q.fact).toSet().length, 6, reason: 'seed $seed');
      final t2 = QuizRunner.composeFinal(pool, single: 10, context: 0, random: Random(seed));
      expect(t2.length, 10);
      expect(t2.map((q) => q.id).toSet().length, 10, reason: 'без повторов, когда добираем сверх фактов');
    }
  });
}
