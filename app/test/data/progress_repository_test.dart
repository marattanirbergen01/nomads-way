import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/local/progress_repository.dart';
import 'package:nomads_way/engine/quiz_runner.dart';
import 'package:nomads_way/engine/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProgressRepository r;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    r = await ProgressRepository.open();
  });

  test('снимок сюжета: сохранить / прочитать / очистить', () async {
    expect(r.storySnapshot('e'), isNull);
    await r.saveStory('e', {'scene': 'sc010', 'vars': {'x': 1}});
    expect(r.storySnapshot('e')!['scene'], 'sc010');
    await r.clearStory('e');
    expect(r.storySnapshot('e'), isNull);
  });

  test('попытки копятся и читаются в порядке добавления', () async {
    final now = DateTime(2026, 9, 6);
    await r.addAttempt(Attempt(questionId: 'q1', fact: 'f', correct: true, ms: 500, at: now));
    await r.addAttempt(Attempt(questionId: 'q2', fact: 'f', correct: false, ms: 900, at: now));
    final a = r.attempts();
    expect(a.map((x) => x.questionId), ['q1', 'q2']);
    expect(a[1].correct, isFalse);
  });

  test('srs-состояние переживает сериализацию', () async {
    final s = SrsState(ease: 2.7, intervalDays: 3, reps: 2, due: DateTime(2026, 9, 9));
    await r.saveSrs('q1', s);
    final back = r.srs()['q1']!;
    expect(back.ease, 2.7);
    expect(back.intervalDays, 3);
    expect(back.due, DateTime(2026, 9, 9));
  });

  test('результат серии', () async {
    await r.saveResult('e', 15, 20);
    expect(r.result('e')!.correct, 15);
  });
}
