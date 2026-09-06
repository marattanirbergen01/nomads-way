import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/engine/scheduler.dart';

void main() {
  final s = const Scheduler();
  final now = DateTime(2026, 9, 6, 15);

  test('верно: 1 → 3 → растущий интервал', () {
    var st = SrsState.fresh(now);
    st = s.review(st, correct: true, now: now);
    expect(st.intervalDays, 1);
    st = s.review(st, correct: true, now: now);
    expect(st.intervalDays, 3);
    st = s.review(st, correct: true, now: now);
    expect(st.intervalDays, greaterThan(3));
    expect(st.due.isAfter(now), isTrue);
  });

  test('ошибка сбрасывает и снижает лёгкость', () {
    var st = SrsState.fresh(now);
    st = s.review(st, correct: true, now: now);
    st = s.review(st, correct: true, now: now);
    final before = st.ease;
    st = s.review(st, correct: false, now: now);
    expect(st.reps, 0);
    expect(st.intervalDays, 1);
    expect(st.ease, lessThan(before));
  });

  test('due отдаёт просроченные, самые старые первыми', () {
    final states = {
      'late': SrsState(due: now.subtract(const Duration(days: 3))),
      'today': SrsState(due: now),
      'future': SrsState(due: now.add(const Duration(days: 1))),
    };
    expect(s.due(states, now), ['late', 'today']);
  });
}
