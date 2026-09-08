import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/local/progress_repository.dart';
import '../../data/models/question.dart';
import '../../engine/awards.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/scheduler.dart';
import '../quiz/quiz_widgets.dart';
import '../readiness/award_screen.dart';

/// Набор вопросов без сюжета: пробный ЕНТ и работа над ошибками используют один экран.
class DrillScreen extends StatefulWidget {
  const DrillScreen({super.key, required this.services, required this.questions, required this.label, required this.doneTitle, required this.doneCaption, this.recordAsMock = false});
  final Services services; final List<Question> questions; final String label; final String doneTitle; final String doneCaption;
  /// Пробный ЕНТ: записать в историю тестов и проверить награды.
  final bool recordAsMock;
  @override
  State<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends State<DrillScreen> {
  late final QuizRunner _quiz = QuizRunner(widget.questions);
  AnswerResult? _result;
  bool _recorded = false;
  Services get _s => widget.services;

  void _answer(String id) {
    final r = _quiz.answer(id);
    final a = _quiz.attempts.last;
    _s.store.addAttempt(a);
    final prev = _s.store.srs()[a.questionId] ?? SrsState.fresh(a.at);
    _s.store.saveSrs(a.questionId, _s.scheduler.review(prev, correct: a.correct, now: a.at));
    setState(() => _result = r);
  }

  Future<void> _next() async {
    setState(() => _result = null);
    if (!_quiz.done || _recorded) return;
    _recorded = true;
    final granted = <Award>[];
    if (widget.recordAsMock) {
      await _s.store.addTest(TestResult(kind: 'mock', correct: _quiz.correctCount, total: _quiz.total, at: DateTime.now()));
      for (final a in _s.awards.onTest(correct: _quiz.correctCount, total: _quiz.total)) {
        await _s.store.grantAward(a.id);
        granted.add(a);
      }
    }
    final streak = await _s.checkStreakAward();
    if (streak != null) granted.add(streak);
    _s.touch();
    if (!mounted) return;
    for (final a in granted) { await AwardScreen.show(context, _s, a, _s.store.awards()[a.id] ?? 1); }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s.s;
    final Widget body = _result != null
        ? ExplainView(result: _result!, locale: _s.l, onNext: _next)
        : _quiz.done
            ? ScoreView(title: widget.doneTitle, correct: _quiz.correctCount, total: _quiz.total, caption: widget.doneCaption, buttonLabel: s('done'), onDone: () => Navigator.of(context).pop())
            : QuestionView(presented: _quiz.current()!, index: _quiz.index, total: _quiz.total, locale: _s.l, label: widget.label, onAnswer: _answer);
    return Scaffold(
      appBar: AppBar(backgroundColor: C.ground, foregroundColor: C.ink, elevation: 0, scrolledUnderElevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context))),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: body))),
    );
  }
}
