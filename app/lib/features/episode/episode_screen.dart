import 'package:flutter/material.dart';
import '../../core/locale_controller.dart';
import '../../data/models/episode.dart';
import '../../data/models/question.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/story_runner.dart';

/// Плеер серии: сцена → выбор → вопросы → разбор → … → итог.
/// Три визуально разных режима — сюжет, выбор, экзамен — правило продукта №3.
class EpisodeScreen extends StatefulWidget {
  const EpisodeScreen({super.key, required this.episode, required this.questions, required this.locale});
  final Episode episode;
  final List<Question> questions;
  final LocaleController locale;
  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  late final StoryRunner _story = StoryRunner(widget.episode);
  late final Map<String, Question> _bank = {for (final q in widget.questions) q.id: q};
  final _allAttempts = <Attempt>[];

  StoryEvent? _event;      // текущий сюжетный такт
  QuizRunner? _quiz;       // активный набор вопросов
  AnswerResult? _result;   // разбор после ответа
  bool _finalTest = false;

  String get _l => widget.locale.code;

  @override
  void initState() {
    super.initState();
    _event = _story.next();
  }

  void _advance() {
    if (_story.awaitingChoice) return;
    final e = _story.next();
    if (e is QuizBreak) {
      _quiz = QuizRunner([for (final id in e.questionIds) if (_bank[id] != null) _bank[id]!]);
      if (_quiz!.done) { _quiz = null; _advance(); return; }
    }
    if (e is EpisodeEnd && !_finalTest) {
      _finalTest = true;
      _quiz = QuizRunner(QuizRunner.composeFinal(widget.questions,
          single: widget.episode.finalTest.single, context: widget.episode.finalTest.context));
    }
    setState(() => _event = e);
  }

  void _choose(Option o) { _story.choose(o); _advance(); }

  void _answer(String id) => setState(() => _result = _quiz!.answer(id));

  void _afterExplain() {
    _allAttempts.add(_quiz!.attempts.last);
    setState(() => _result = null);
    if (_quiz!.done) {
      if (_finalTest) { setState(() {}); return; }   // остаёмся на экране итога
      _quiz = null;
      _advance();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.locale,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(widget.episode.title.of(_l)),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: Text(_l.toUpperCase(), style: Theme.of(context).textTheme.labelLarge)),
              ),
            ],
          ),
          body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _body(context)))),
        ),
      );

  Widget _body(BuildContext context) {
    if (_result != null) return _ExplainView(result: _result!, locale: _l, onNext: _afterExplain);
    if (_quiz != null) {
      if (_quiz!.done && _finalTest) return _FinalView(correct: _quiz!.correctCount, total: _quiz!.total, locale: _l);
      final p = _quiz!.current()!;
      return _QuestionView(
        presented: p, index: _quiz!.index, total: _quiz!.total, locale: _l,
        isFinal: _finalTest,
        contextScene: p.question.context == null ? null : widget.episode.sceneById(p.question.context!),
        onAnswer: _answer,
      );
    }
    final e = _event;
    if (e is BeatEvent) {
      final b = e.beat;
      if (b is Say) return _SceneView(scene: e.scene, say: b, episode: widget.episode, locale: _l, onTap: _advance);
      if (b is Choice) return _ChoiceView(scene: e.scene, choice: b, locale: _l, onChoose: _choose);
    }
    return const Center(child: CircularProgressIndicator());
  }
}

// ---------------------------------------------------------------- сюжет
class _SceneView extends StatelessWidget {
  const _SceneView({required this.scene, required this.say, required this.episode, required this.locale, required this.onTap});
  final Scene scene; final Say say; final Episode episode; final String locale; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = episode.characters[say.who];
    final isNarrator = say.who == 'narrator';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Expanded(child: _ArtPlaceholder(id: scene.art)),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            color: cs.surfaceContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isNarrator && who != null)
                  Text(who.name.of(locale).toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(say.text.of(locale),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontStyle: isNarrator ? FontStyle.italic : FontStyle.normal, height: 1.45)),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight,
                    child: Text(locale == 'kk' ? 'жалғастыру ▸' : 'дальше ▸', style: Theme.of(context).textTheme.labelSmall)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceView extends StatelessWidget {
  const _ChoiceView({required this.scene, required this.choice, required this.locale, required this.onChoose});
  final Scene scene; final Choice choice; final String locale; final void Function(Option) onChoose;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(child: _ArtPlaceholder(id: scene.art)),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(choice.prompt.of(locale), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                for (final o in choice.options) ...[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18), alignment: Alignment.centerLeft),
                    onPressed: () => onChoose(o),
                    child: Text(o.text.of(locale)),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      );
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.id});
  final String id;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(id, style: TextStyle(color: cs.onSurfaceVariant, fontFamily: 'monospace')),
    );
  }
}

// ---------------------------------------------------------------- экзамен
class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.presented, required this.index, required this.total, required this.locale,
    required this.isFinal, required this.contextScene, required this.onAnswer,
  });
  final Presented presented; final int index; final int total; final String locale;
  final bool isFinal; final Scene? contextScene; final void Function(String) onAnswer;

  @override
  Widget build(BuildContext context) {
    final q = presented.question;
    final cs = Theme.of(context).colorScheme;
    final letters = ['A', 'B', 'C', 'D'];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(border: Border.all(color: cs.outline), borderRadius: BorderRadius.circular(4)),
            child: Text(isFinal ? (locale == 'kk' ? 'ҚОРЫТЫНДЫ ТЕСТ' : 'ИТОГОВЫЙ ТЕСТ') : (locale == 'kk' ? 'ТЕКСЕРУ' : 'ПРОВЕРКА'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
          ),
          const Spacer(),
          Text('${index + 1} / $total', style: Theme.of(context).textTheme.labelLarge),
        ]),
        const SizedBox(height: 18),
        if (q.format == QFormat.context && contextScene != null)
          Text(locale == 'kk' ? 'Оқыған сахна бойынша:' : 'По прочитанной сцене:',
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

class _ExplainView extends StatelessWidget {
  const _ExplainView({required this.result, required this.locale, required this.onNext});
  final AnswerResult result; final String locale; final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ok = result.correct;
    final q = result.question;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(ok ? (locale == 'kk' ? 'Дұрыс' : 'Верно') : (locale == 'kk' ? 'Қате' : 'Неверно'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: ok ? cs.primary : cs.error)),
        const SizedBox(height: 8),
        if (!ok) ...[
          Text(locale == 'kk' ? 'Дұрыс жауап:' : 'Правильный ответ:', style: Theme.of(context).textTheme.labelMedium),
          Text(q.correct.text.of(locale), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: cs.primary, width: 3))),
          child: Text(q.explain.of(locale), style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
        ),
        const SizedBox(height: 10),
        Text(q.source, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontFamily: 'monospace')),
        const SizedBox(height: 24),
        FilledButton(onPressed: onNext, child: Text(locale == 'kk' ? 'Жалғастыру' : 'Дальше')),
      ],
    );
  }
}

class _FinalView extends StatelessWidget {
  const _FinalView({required this.correct, required this.total, required this.locale});
  final int correct; final int total; final String locale;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(locale == 'kk' ? 'Серия аяқталды' : 'Серия пройдена', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('$correct / $total', style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(locale == 'kk' ? 'ҰБТ форматындағы қорытынды тест' : 'Итоговый тест в формате ЕНТ',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 28),
            FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: Text(locale == 'kk' ? 'Басты бетке' : 'На главную')),
          ],
        ),
      );
}
