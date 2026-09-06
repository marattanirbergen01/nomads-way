/// Интервальное повторение — упрощённый SM-2.
/// Состояние на вопрос: лёгкость, интервал в днях, дата следующего показа.
class SrsState {
  const SrsState({this.ease = 2.5, this.intervalDays = 0, this.reps = 0, required this.due});
  final double ease;
  final int intervalDays;
  final int reps;
  final DateTime due;

  factory SrsState.fresh(DateTime now) => SrsState(due: now);

  Map<String, dynamic> toJson() => {'ease': ease, 'interval': intervalDays, 'reps': reps, 'due': due.toIso8601String()};
  factory SrsState.fromJson(Map<String, dynamic> j) =>
      SrsState(ease: (j['ease'] as num).toDouble(), intervalDays: j['interval'], reps: j['reps'], due: DateTime.parse(j['due']));
}

class Scheduler {
  const Scheduler();

  /// Ошибка: сброс, вопрос вернётся завтра, лёгкость падает.
  /// Верно: 1 день → 3 дня → интервал × лёгкость. Лёгкость растёт до 3.0.
  SrsState review(SrsState s, {required bool correct, required DateTime now}) {
    if (!correct) {
      return SrsState(
        ease: (s.ease - 0.2).clamp(1.3, 3.0),
        intervalDays: 1,
        reps: 0,
        due: _day(now).add(const Duration(days: 1)),
      );
    }
    final reps = s.reps + 1;
    final interval = switch (reps) { 1 => 1, 2 => 3, _ => (s.intervalDays * s.ease).round().clamp(4, 365) };
    return SrsState(
      ease: (s.ease + 0.1).clamp(1.3, 3.0),
      intervalDays: interval,
      reps: reps,
      due: _day(now).add(Duration(days: interval)),
    );
  }

  /// Вопросы, которые пора повторить, — самые просроченные первыми.
  List<String> due(Map<String, SrsState> states, DateTime now) {
    final d = states.entries.where((e) => !e.value.due.isAfter(now)).toList()
      ..sort((a, b) => a.value.due.compareTo(b.value.due));
    return [for (final e in d) e.key];
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
}
