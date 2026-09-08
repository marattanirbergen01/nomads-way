import 'quiz_runner.dart';

/// Награды сезона 1 — только то, что материал позволяет проверить.
/// Батыр Ордабасы и подобные придут вместе с периодом Джунгарского нашествия.
enum Award { mergen, koshBastagan, shezhireshi, streak7 }

extension AwardId on Award {
  String get id => name;
  static Award? parse(String id) => Award.values.where((a) => a.name == id).firstOrNull;
}

class AwardsEngine {
  const AwardsEngine();

  /// Итоговый или пробный тест закончен.
  List<Award> onTest({required int correct, required int total}) =>
      (total == 20 && correct == 20) ? const [Award.mergen] : const [];

  /// Серия пройдена целиком. [runAttempts] — ответы этого прохождения.
  List<Award> onEpisodeCompleted({required int completionsBefore, required List<Attempt> runAttempts}) {
    final out = <Award>[];
    if (completionsBefore == 0) out.add(Award.koshBastagan);
    final founders = runAttempts.where((a) => a.fact == 'f.4.1.b').toList();
    if (founders.length >= 2 && founders.every((a) => a.correct)) out.add(Award.shezhireshi);
    return out;
  }

  /// Дней подряд с хотя бы одним ответом; вчера без сегодня — стрик ещё жив.
  static int streakDays(Iterable<DateTime> attemptDays, DateTime now) {
    final days = {for (final d in attemptDays) DateTime(d.year, d.month, d.day)};
    if (days.isEmpty) return 0;
    var cur = DateTime(now.year, now.month, now.day);
    if (!days.contains(cur)) {
      cur = cur.subtract(const Duration(days: 1));
      if (!days.contains(cur)) return 0;
    }
    var n = 0;
    while (days.contains(cur)) { n++; cur = cur.subtract(const Duration(days: 1)); }
    return n;
  }

  /// Награда за 7 дней подряд — раз на каждую семёрку, не чаще раза в день.
  bool streakAwardDue(int streak, DateTime now, DateTime? lastGrant) {
    if (streak == 0 || streak % 7 != 0) return false;
    if (lastGrant == null) return true;
    return DateTime(now.year, now.month, now.day).isAfter(DateTime(lastGrant.year, lastGrant.month, lastGrant.day));
  }
}
