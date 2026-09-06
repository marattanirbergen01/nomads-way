import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../data/models/episode.dart';
import '../../data/models/question.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/scheduler.dart';
import '../../engine/story_runner.dart';
import 'quiz_widgets.dart';

/// Плеер серии: сцена → выбор → вопросы → разбор → … → итоговый тест.
/// Прогресс сохраняется перед каждым сюжетным тактом, попытки и SRS — после каждого ответа.
class EpisodeScreen extends StatefulWidget {
  const EpisodeScreen({super.key, required this.episode, required this.questions, required this.services});
  final Episode episode;
  final List<Question> questions;
  final Services services;
  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  late StoryRunner _story;
  late final Map<String, Question> _bank = {for (final q in widget.questions) q.id: q};

  StoryEvent? _event;
  QuizRunner? _quiz;
  AnswerResult? _result;
  bool _finalTest = false;

  Services get _s => widget.services;
  String get _l => _s.locale.code;
  String get _id => widget.episode.id;

  @override
  void initState() {
    super.initState();
    final snap = _s.store.storySnapshot(_id);
    _story = snap != null ? StoryRunner.restore(widget.episode, snap) : StoryRunner(widget.episode);
    _advance();
  }

  /// Снимок берётся ДО next(): при восстановлении next() воспроизведёт тот же такт,
  /// включая QuizBreak, если игрок вышел посреди вопросов.
  void _advance() {
    if (_story.awaitingChoice) return;
    if (!_story.ended) _s.store.saveStory(_id, _story.snapshot());
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

  void _answer(String id) {
    final r = _quiz!.answer(id);
    final a = _quiz!.attempts.last;
    _s.store.addAttempt(a);
    final prev = _s.store.srs()[a.questionId] ?? SrsState.fresh(a.at);
    _s.store.saveSrs(a.questionId, _s.scheduler.review(prev, correct: a.correct, now: a.at));
    setState(() => _result = r);
  }

  void _afterExplain() {
    setState(() => _result = null);
    if (!_quiz!.done) return;
    if (_finalTest) {
      _s.store.saveResult(_id, _quiz!.correctCount, _quiz!.total);
      _s.store.clearStory(_id);
      setState(() {});
      return;
    }
    _quiz = null;
    _advance();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _s.locale,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(widget.episode.title.of(_l))),
          body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _body()))),
        ),
      );

  Widget _body() {
    if (_result != null) return ExplainView(result: _result!, locale: _l, onNext: _afterExplain);
    if (_quiz != null) {
      if (_quiz!.done && _finalTest) {
        return ScoreView(
          title: t(_l, kk: 'Серия аяқталды', ru: 'Серия пройдена'),
          correct: _quiz!.correctCount, total: _quiz!.total,
          caption: t(_l, kk: 'ҰБТ форматындағы қорытынды тест', ru: 'Итоговый тест в формате ЕНТ'),
          buttonLabel: t(_l, kk: 'Басты бетке', ru: 'На главную'),
          onDone: () => Navigator.of(context).pop(),
        );
      }
      final p = _quiz!.current()!;
      return QuestionView(
        presented: p, index: _quiz!.index, total: _quiz!.total, locale: _l,
        label: _finalTest ? t(_l, kk: 'ҚОРЫТЫНДЫ ТЕСТ', ru: 'ИТОГОВЫЙ ТЕСТ') : t(_l, kk: 'ТЕКСЕРУ', ru: 'ПРОВЕРКА'),
        contextScene: p.question.context == null ? null : widget.episode.sceneById(p.question.context!),
        onAnswer: _answer,
      );
    }
    final e = _event;
    if (e is BeatEvent) {
      final b = e.beat;
      final art = _s.content.mediaUrl(_id, e.scene.art);
      if (b is Say) return _SceneView(scene: e.scene, say: b, episode: widget.episode, locale: _l, artUrl: art, onTap: _advance);
      if (b is Choice) return _ChoiceView(scene: e.scene, choice: b, locale: _l, artUrl: art, onChoose: _choose);
    }
    return const Center(child: CircularProgressIndicator());
  }
}

// ---------------------------------------------------------------- сюжет: своя визуальная система
class _SceneView extends StatelessWidget {
  const _SceneView({required this.scene, required this.say, required this.episode, required this.locale, required this.artUrl, required this.onTap});
  final Scene scene; final Say say; final Episode episode; final String locale; final String artUrl; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = episode.characters[say.who];
    final isNarrator = say.who == 'narrator';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(children: [
        Expanded(child: _ArtPlaceholder(id: scene.art, url: artUrl)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          color: cs.surfaceContainer,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!isNarrator && who != null)
              Text(who.name.of(locale).toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.primary, letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Text(say.text.of(locale),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontStyle: isNarrator ? FontStyle.italic : FontStyle.normal, height: 1.45)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight,
                child: Text(t(locale, kk: 'жалғастыру ▸', ru: 'дальше ▸'), style: Theme.of(context).textTheme.labelSmall)),
          ]),
        ),
      ]),
    );
  }
}

class _ChoiceView extends StatelessWidget {
  const _ChoiceView({required this.scene, required this.choice, required this.locale, required this.artUrl, required this.onChoose});
  final Scene scene; final Choice choice; final String locale; final String artUrl; final void Function(Option) onChoose;
  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(child: _ArtPlaceholder(id: scene.art, url: artUrl)),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          ]),
        ),
      ]);
}

/// Иллюстрация сцены с CDN: build/media/`<season>`/`<id>`.jpg. Нет файла — серая заглушка с id,
/// чтобы сценарист видел, какой кадр ещё не сделан.
class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder({required this.id, required this.url});
  final String id;
  final String url;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      color: cs.surfaceContainerHighest, alignment: Alignment.center,
      child: Text(id, style: TextStyle(color: cs.onSurfaceVariant, fontFamily: 'monospace')),
    );
    return Image.network(
      url, fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
    );
  }
}
