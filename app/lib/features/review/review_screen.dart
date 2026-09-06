import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/scheduler.dart';
import '../episode/quiz_widgets.dart';

/// «Повторить слабое»: вопросы, у которых наступила дата по SRS, без сюжета.
/// Вход для школьника, которому перед экзаменом нужно решать, а не читать.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.services, required this.catalogIds});
  final Services services;
  final List<String> catalogIds;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const _cap = 20;
  late final QuizRunner _quiz;
  AnswerResult? _result;

  Services get _s => widget.services;
  String get _l => _s.locale.code;

  @override
  void initState() {
    super.initState();
    final bank = {for (final q in _s.content.cachedQuestions(widget.catalogIds)) q.id: q};
    final due = _s.scheduler.due(_s.store.srs(), DateTime.now());
    _quiz = QuizRunner([for (final id in due) if (bank[id] != null) bank[id]!].take(_cap).toList());
  }

  void _answer(String id) {
    final r = _quiz.answer(id);
    final a = _quiz.attempts.last;
    _s.store.addAttempt(a);
    final prev = _s.store.srs()[a.questionId] ?? SrsState.fresh(a.at);
    _s.store.saveSrs(a.questionId, _s.scheduler.review(prev, correct: a.correct, now: a.at));
    setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(t(_l, kk: 'Қайталау', ru: 'Повторение'))),
        body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _body()))),
      );

  Widget _body() {
    if (_result != null) return ExplainView(result: _result!, locale: _l, onNext: () => setState(() => _result = null));
    if (_quiz.done) {
      return ScoreView(
        title: t(_l, kk: 'Қайталау аяқталды', ru: 'Повторение завершено'),
        correct: _quiz.correctCount, total: _quiz.total,
        caption: t(_l, kk: 'Қателер ертең қайта келеді', ru: 'Ошибки вернутся завтра'),
        buttonLabel: t(_l, kk: 'Дайын', ru: 'Готово'),
        onDone: () => Navigator.of(context).pop(),
      );
    }
    return QuestionView(
      presented: _quiz.current()!, index: _quiz.index, total: _quiz.total, locale: _l,
      label: t(_l, kk: 'ҚАЙТАЛАУ', ru: 'ПОВТОРЕНИЕ'),
      onAnswer: _answer,
    );
  }
}
