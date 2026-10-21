import 'dart:math';
import '../data/models/question.dart';

/// Ведёт набор вопросов: перемешивает варианты, принимает ответ, отдаёт разбор, копит попытки.
/// Неверный ответ ничего не блокирует — правило продукта №2.
class QuizRunner {
  QuizRunner(List<Question> questions, {Random? random})
      : _qs = List.of(questions),
        _rnd = random ?? Random();

  final List<Question> _qs;
  final Random _rnd;
  int _i = 0;
  final attempts = <Attempt>[];
  List<AnswerOption>? _shuffled;
  DateTime? _shownAt;

  bool get done => _i >= _qs.length;
  int get index => _i;
  int get total => _qs.length;
  int get correctCount => attempts.where((a) => a.correct).length;
  /// Ответы по порядку: какой вариант выбран у каждого вопроса — для итогового разбора.
  final picks = <AnswerOption>[];
  List<Question> get questions => List.unmodifiable(_qs);

  /// Текущий вопрос с перемешанными вариантами. Порядок фиксируется до ответа.
  /// `shuffle: false` — варианты ссылаются друг на друга («оба ответа верны»), порядок как в файле.
  Presented? current() {
    if (done) return null;
    final q = _qs[_i];
    _shuffled ??= q.shuffle ? (List.of(q.options)..shuffle(_rnd)) : List.of(q.options);
    _shownAt ??= DateTime.now();
    return Presented(q, _shuffled!);
  }

  AnswerResult answer(String optionId) {
    final q = _qs[_i];
    final chosen = q.options.firstWhere((o) => o.id == optionId);
    final ms = DateTime.now().difference(_shownAt ?? DateTime.now()).inMilliseconds;
    final a = Attempt(questionId: q.id, fact: q.fact, correct: chosen.correct, ms: ms, at: DateTime.now());
    attempts.add(a);
    picks.add(chosen);
    _i++;
    _shuffled = null;
    _shownAt = null;
    return AnswerResult(question: q, chosen: chosen, correct: chosen.correct);
  }

  /// Итоговый тест серии в формате ЕНТ: n одиночных + m контекстных из банка.
  /// Если банк меньше — берём всё, что есть.
  /// Один факт (у вопросов банка школы — одна тема ЕНТ) — один вопрос за тест: одинаковые по смыслу
  /// формулировки не встречаются в одном тесте. Не хватает разных фактов — добираем без ограничения.
  static List<Question> composeFinal(List<Question> bank, {required int single, required int context, Random? random}) {
    final r = random ?? Random();
    List<Question> pick(QFormat f, int n) {
      final pool = bank.where((q) => q.format == f).toList()..shuffle(r);
      final out = <Question>[]; final facts = <String>{};
      for (final q in pool) {
        if (out.length == n) break;
        if (q.fact.isNotEmpty && !facts.add(q.fact)) continue;
        out.add(q);
      }
      for (final q in pool) {
        if (out.length == n) break;
        if (!out.contains(q)) out.add(q);
      }
      return out;
    }
    return [...pick(QFormat.single, single), ...pick(QFormat.context, context)];
  }
}

class Presented {
  const Presented(this.question, this.options);
  final Question question;
  final List<AnswerOption> options;
}

class AnswerResult {
  const AnswerResult({required this.question, required this.chosen, required this.correct});
  final Question question;
  final AnswerOption chosen;
  final bool correct;
}

class Attempt {
  const Attempt({required this.questionId, required this.fact, required this.correct, required this.ms, required this.at});
  final String questionId;
  final String fact;
  final bool correct;
  final int ms;
  final DateTime at;

  Map<String, dynamic> toJson() => {'q': questionId, 'f': fact, 'ok': correct, 'ms': ms, 'at': at.toIso8601String()};
  factory Attempt.fromJson(Map<String, dynamic> j) =>
      Attempt(questionId: j['q'], fact: j['f'], correct: j['ok'] == true, ms: j['ms'], at: DateTime.parse(j['at']));
}
