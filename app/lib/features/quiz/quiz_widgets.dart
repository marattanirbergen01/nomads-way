import 'package:flutter/material.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/models/episode.dart';
import '../../data/models/question.dart';
import '../../engine/quiz_runner.dart';

/// Экран вопроса — экзаменационная подача: ярлык, счётчик, варианты A–D. Структура не менялась.
class QuestionView extends StatelessWidget {
  const QuestionView({
    super.key, required this.presented, required this.index, required this.total, required this.locale,
    required this.label, this.contextScene, required this.onAnswer,
  });
  final Presented presented; final int index; final int total; final String locale;
  final String label; final Scene? contextScene; final void Function(String) onAnswer;

  @override
  Widget build(BuildContext context) {
    final q = presented.question;
    final s = Str.of(locale);
    const letters = ['A', 'B', 'C', 'D'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(border: Border.all(color: C.gold), borderRadius: BorderRadius.circular(4)),
            child: Text(label, style: st(11, w: 600, color: C.gold, spacing: 1.2)),
          ),
          const Spacer(),
          Text('${index + 1} / $total', style: st(14, w: 600, color: C.inkSoft)),
        ]),
        const SizedBox(height: 18),
        if (q.format == QFormat.context && contextScene != null)
          Text(s('by.scene'), style: st(13, color: C.inkSoft)),
        const SizedBox(height: 6),
        Text(q.stem.of(locale), style: st(21, w: 600, height: 1.3)),
        const SizedBox(height: 20),
        for (var i = 0; i < presented.options.length; i++) ...[
          _AnswerTile(letter: letters[i], text: presented.options[i].text.of(locale), onTap: () => onAnswer(presented.options[i].id)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({required this.letter, required this.text, required this.onTap});
  final String letter; final String text; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: C.card,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Text(letter, style: st(15, w: 700, color: C.gold)),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: st(16, height: 1.35))),
            ]),
          ),
        ),
      );
}

/// Разбор после ответа. Здесь происходит обучение — объяснение важнее вердикта.
class ExplainView extends StatelessWidget {
  const ExplainView({super.key, required this.result, required this.locale, required this.onNext});
  final AnswerResult result; final String locale; final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final ok = result.correct;
    final q = result.question;
    final s = Str.of(locale);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(ok ? s('correct') : s('wrong'), style: st(26, w: 700, color: ok ? C.gold : C.ember)),
        const SizedBox(height: 8),
        if (!ok) ...[
          Text(s('right.answer'), style: st(13, color: C.inkSoft)),
          const SizedBox(height: 4),
          Text(q.correct.text.of(locale), style: st(17, w: 600)),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(8)),
          child: Text(q.explain.of(locale), style: st(16, height: 1.5)),
        ),
        const SizedBox(height: 10),
        Text(q.source, style: st(11.5, color: C.inkFaint)),
        const SizedBox(height: 24),
        GoldButton(label: s('next'), onTap: onNext),
      ],
    );
  }
}

class ScoreView extends StatelessWidget {
  const ScoreView({super.key, required this.title, required this.correct, required this.total, required this.caption, required this.buttonLabel, required this.onDone});
  final String title; final int correct; final int total; final String caption; final String buttonLabel; final VoidCallback onDone;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(title, style: st(22, w: 600)),
          const SizedBox(height: 12),
          Text('$correct / $total', style: st(56, w: 800, color: C.gold)),
          const SizedBox(height: 8),
          Text(caption, style: st(14, color: C.inkSoft), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          GoldButton(label: buttonLabel, onTap: onDone),
        ]),
      );
}
