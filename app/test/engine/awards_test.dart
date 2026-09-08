import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/engine/awards.dart';
import 'package:nomads_way/engine/quiz_runner.dart';

Attempt _a(String f, bool ok, DateTime at) => Attempt(questionId: 'q', fact: f, correct: ok, ms: 1, at: at);

void main() {
  const e = AwardsEngine();
  final d = DateTime(2026, 9, 9, 12);

  test('Мерген — только 20 из 20', () {
    expect(e.onTest(correct: 20, total: 20), [Award.mergen]);
    expect(e.onTest(correct: 19, total: 20), isEmpty);
    expect(e.onTest(correct: 12, total: 12), isEmpty);
  });

  test('Көш бастаған — первая серия; Шежіреші — все ответы про основателей верны', () {
    final run = [_a('f.4.1.b', true, d), _a('f.4.1.b', true, d), _a('f.4.1.a', false, d)];
    expect(e.onEpisodeCompleted(completionsBefore: 0, runAttempts: run), [Award.koshBastagan, Award.shezhireshi]);
    expect(e.onEpisodeCompleted(completionsBefore: 1, runAttempts: run), [Award.shezhireshi]);
    expect(e.onEpisodeCompleted(completionsBefore: 1, runAttempts: [_a('f.4.1.b', true, d), _a('f.4.1.b', false, d)]), isEmpty);
    expect(e.onEpisodeCompleted(completionsBefore: 1, runAttempts: [_a('f.4.1.b', true, d)]), isEmpty, reason: 'одного ответа мало');
  });

  test('стрик считает дни подряд, вчера продолжает, разрыв обнуляет', () {
    final days = [d, d.subtract(const Duration(days: 1)), d.subtract(const Duration(days: 2))];
    expect(AwardsEngine.streakDays(days, d), 3);
    expect(AwardsEngine.streakDays(days.skip(1), d), 2, reason: 'сегодня ещё не отвечал, вчера — да');
    expect(AwardsEngine.streakDays([d.subtract(const Duration(days: 2))], d), 0);
    expect(AwardsEngine.streakDays([], d), 0);
  });

  test('награда за 7 дней — на кратных семи, не чаще раза в день', () {
    expect(e.streakAwardDue(7, d, null), isTrue);
    expect(e.streakAwardDue(6, d, null), isFalse);
    expect(e.streakAwardDue(7, d, d.subtract(const Duration(hours: 2))), isFalse);
    expect(e.streakAwardDue(14, d, d.subtract(const Duration(days: 7))), isTrue);
  });
}
