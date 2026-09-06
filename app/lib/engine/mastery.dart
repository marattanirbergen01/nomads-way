import 'quiz_runner.dart';

/// Готовность по темам: 0..1. Единственное число, которое откроет родитель, — оно должно быть честным.
///
/// Факт = взвешенное среднее последних трёх попыток по его вопросам (свежие весят больше).
/// Тема = среднее по всем её фактам; факт без попыток = 0, а не «пропускается» —
/// иначе одна удачная тема даст 100% при пустой программе.
class Mastery {
  const Mastery();
  static const _w = [0.5, 0.3, 0.2];

  double fact(String factId, List<Attempt> attempts) {
    final mine = attempts.where((a) => a.fact == factId).toList()..sort((a, b) => b.at.compareTo(a.at));
    if (mine.isEmpty) return 0;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < mine.length && i < _w.length; i++) {
      num += _w[i] * (mine[i].correct ? 1 : 0);
      den += _w[i];
    }
    return num / den;
  }

  double topic(Iterable<String> factIds, List<Attempt> attempts) {
    if (factIds.isEmpty) return 0;
    final vals = [for (final f in factIds) fact(f, attempts)];
    return vals.reduce((a, b) => a + b) / vals.length;
  }
}
