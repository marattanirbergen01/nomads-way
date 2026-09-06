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

  /// Текущий вопрос с перемешанными вариантами. Порядок фиксируется до ответа.
  Presented? current() {
    if (done) return null;
    _shuffled ??= List.of(_qs[_i].options)..shuffle(_rnd);
    _shownAt ??= DateTime.now();
    return Presented(_qs[_i], _shuffled!);
  }

  AnswerResult answer(String optionId) {
    final q = _qs[_i];
    final chosen = q.options.firstWhere((o) => o.id == optionId);
    final ms = DateTime.now().difference(_shownAt ?? DateTime.now()).inMilliseconds;
    final a = Attempt(questionId: q.id, fact: q.fact, correct: chosen.correct, ms: ms, at: DateTime.now());
    attempts.add(a);
    _i++;
    _shuffled = null;
    _shownAt = null;
    return AnswerResult(question: q, chosen: chosen, correct: chosen.correct);
  }

  /// Итоговый тест серии в формате ЕНТ: n одиночных + m контекстных из банка.
  /// Если банк меньше — берём всё, что есть.
  static List<Question> composeFinal(List<Question> bank, {required int single, required int context, Random? random}) {
    final r = random ?? Random();
    final s = bank.where((q) => q.format == QFormat.single).toList()..shuffle(r);
    final c = bank.where((q) => q.format == QFormat.context).toList()..shuffle(r);
    return [...s.take(single), ...c.take(context)];
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
}
