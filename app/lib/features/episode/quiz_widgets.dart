import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../data/models/episode.dart';
import '../../data/models/question.dart';
import '../../engine/quiz_runner.dart';

/// Экран вопроса — «экзаменационная» визуальная система: рамка-ярлык, счётчик, варианты A–D.
/// Отличается от сюжетного выбора намеренно (правило продукта №3).
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
    final cs = Theme.of(context).colorScheme;
    const letters = ['A', 'B', 'C', 'D'];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(border: Border.all(color: cs.outline), borderRadius: BorderRadius.circular(4)),
            child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
          ),
          const Spacer(),
          Text('${index + 1} / $total', style: Theme.of(context).textTheme.labelLarge),
        ]),
        const SizedBox(height: 18),
        if (q.format == QFormat.context && contextScene != null)
          Text(t(locale, kk: 'Оқыған сахна бойынша:', ru: 'По прочитанной сцене:'),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(q.stem.of(locale), style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.3)),
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Text(letter, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary)),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ]),
        ),
      ),
    );
  }
}

/// Разбор после ответа. Здесь происходит обучение — объяснение важнее вердикта.
class ExplainView extends StatelessWidget {
  const ExplainView({super.key, required this.result, required this.locale, required this.onNext});
  final AnswerResult result; final String locale; final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = result.correct;
    final q = result.question;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(ok ? t(locale, kk: 'Дұрыс', ru: 'Верно') : t(locale, kk: 'Қате', ru: 'Неверно'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: ok ? cs.primary : cs.error)),
        const SizedBox(height: 8),
        if (!ok) ...[
          Text(t(locale, kk: 'Дұрыс жауап:', ru: 'Правильный ответ:'), style: Theme.of(context).textTheme.labelMedium),
          Text(q.correct.text.of(locale), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainer, borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: cs.primary, width: 3)),
          ),
          child: Text(q.explain.of(locale), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
        ),
        const SizedBox(height: 10),
        Text(q.source, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFamily: 'monospace')),
        const SizedBox(height: 24),
        FilledButton(onPressed: onNext, child: Text(t(locale, kk: 'Жалғастыру', ru: 'Дальше'))),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('$correct / $total', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(caption, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 28),
            FilledButton.tonal(onPressed: onDone, child: Text(buttonLabel)),
          ],
        ),
      );
}
