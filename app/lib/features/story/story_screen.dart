import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/l10n.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/local/progress_repository.dart';
import '../../data/models/episode.dart';
import '../../data/models/question.dart';
import '../../engine/awards.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/scheduler.dart';
import '../../engine/story_runner.dart';
import '../../widgets/art.dart';
import '../../widgets/avatar.dart';
import '../../widgets/ornament.dart';
import '../quiz/quiz_widgets.dart';
import '../readiness/award_screen.dart';
import 'scene_menu.dart';

/// Плеер серии: сцена → выбор → «выбор сделан» → вопросы → разбор → … → итоговый тест.
/// «Назад» листает сюжет по одной реплике; перемотка заблокирована, пока не дочитан текст.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key, required this.episode, required this.questions, required this.services, this.contentHash});
  final Episode episode;
  final List<Question> questions;
  final Services services;
  /// Отпечаток содержимого серии: снимок позиции годен только для той же версии.
  final String? contentHash;
  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> with SingleTickerProviderStateMixin {
  late StoryRunner _story;
  late final Map<String, Question> _bank = {for (final q in widget.questions) q.id: q};
  /// Прочитанные реплики этой сессии. «Артқа» листает их только для чтения:
  /// выбор окончательный и назад не отменяется, развилки в этот список не попадают.
  final _transcript = <_Line>[];
  /// Указатель просмотра: null — живой такт, иначе индекс в [_transcript].
  int? _browse;
  final _runAttempts = <Attempt>[];

  StoryEvent? _event;
  Option? _chosen;               // экран «выбор сделан»
  QuizRunner? _quiz;
  AnswerResult? _result;
  bool _finalTest = false;
  late final AnimationController _lock = AnimationController(vsync: this);

  Services get _s => widget.services;
  String get _l => _s.l;
  String get _id => widget.episode.id;
  bool get _locked => _lock.isAnimating;

  @override
  void initState() {
    super.initState();
    final snap = _s.store.storySnapshot(_id, contentHash: widget.contentHash);
    _story = snap != null ? StoryRunner.restore(widget.episode, snap) : StoryRunner(widget.episode);
    if (snap != null) _restoreLines(snap['lines']);
    _lock.addStatusListener((_) => setState(() {}));
    _advance();
  }

  @override
  void dispose() { _lock.dispose(); super.dispose(); }

  // ---------------------------------------------------------------- сюжет
  void _advance() {
    if (_story.awaitingChoice) return;
    _browse = null;
    final snap = {..._story.snapshot(), 'lines': [for (final l in _transcript) l.toJson()]};
    if (!_story.ended) {
      _s.store.saveStory(_id, snap, contentHash: widget.contentHash);
      _s.store.saveContinueMeta(_id, widget.episode.indexOf(_story.scene.id), widget.episode.scenes.length);
    }
    final e = _story.next();
    if (e is BeatEvent) {
      final b = e.beat;
      if (b is Say) _transcript.add(_Line(scene: e.scene, beat: e.scene.beats.indexOf(b), who: b.who, text: b.text, emo: b.emo ?? 'calm'));
      _startLock(b is Say ? b.text.of(_l) : (b as Choice).prompt.of(_l));
    }
    if (e is QuizBreak) {
      _quiz = QuizRunner([for (final id in e.questionIds) if (_bank[id] != null) _bank[id]!]);
      if (_quiz!.done) { _quiz = null; _advance(); return; }
    }
    if (e is EpisodeEnd && !_finalTest) {
      _finalTest = true;
      _quiz = QuizRunner(QuizRunner.composeFinal(widget.questions,
          single: widget.episode.finalTest.single, context: widget.episode.finalTest.context));
    }
    setState(() { _event = e; _chosen = null; });
    // Обращаться к размеру экрана можно только после первого кадра:
    // _advance вызывается и из initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchNeighbours());
  }

  /// Держим в памяти кадр текущей сцены и следующей; остальные выгружаем.
  void _prefetchNeighbours() {
    if (!mounted) return;
    final scenes = widget.episode.scenes;
    final i = widget.episode.indexOf(_story.scene.id);
    if (i < 0) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = MediaQuery.sizeOf(context).width;
    ImageProvider? provider(int k) {
      if (k < 0 || k >= scenes.length) return null;
      final art = scenes[k].artFor(_story.vars);
      return Art.provider(url: _s.content.mediaUrl(_id, art), file: _s.content.mediaFile(_id, art), logicalWidth: w, dpr: dpr);
    }
    final next = provider(i + 1);
    if (next != null) precacheImage(next, context, onError: (_, __) {});
    for (final k in [i - 2, i + 2]) {
      provider(k)?.evict();
    }
  }

  /// Прочитанные реплики из сохранённого снимка. Сценарий мог измениться —
  /// пропускаем всё, что не находится или перестало быть репликой.
  void _restoreLines(dynamic raw) {
    if (raw is! List) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final sid = item['s'] as String?; final bi = item['b'] as int?;
      if (sid == null || bi == null) continue;
      final si = widget.episode.indexOf(sid);
      if (si < 0) continue;
      final scene = widget.episode.scenes[si];
      if (bi < 0 || bi >= scene.beats.length) continue;
      final b = scene.beats[bi];
      if (b is! Say) continue;
      _transcript.add(_Line(scene: scene, beat: bi, who: b.who, text: b.text, emo: b.emo ?? 'calm'));
    }
  }

  void _startLock(String text) {
    final factor = [1.4, 1.0, 0.65][_s.store.textSpeed.clamp(0, 2)];
    final sec = (0.9 + text.length * 0.018).clamp(1.0, 3.2) * factor;
    _lock.duration = Duration(milliseconds: (sec * 1000).round());
    _lock.forward(from: 0);
  }

  void _tapForward() {
    if (_browse != null) {
      // листаем прочитанное вперёд; дошли до живой реплики — выходим из просмотра
      setState(() { _browse = _browse! + 1 >= _transcript.length - 1 ? null : _browse! + 1; });
      return;
    }
    if (_locked || _story.awaitingChoice) return;
    _advance();
  }

  bool get _canBack => _quiz == null && _chosen == null && (_browse == null ? _transcript.length >= 2 : _browse! > 0);

  /// Назад — только перечитать. Сюжет не откатывается, выбор не отменяется.
  void _back() {
    if (!_canBack) return;
    setState(() { _browse = _browse == null ? _transcript.length - 2 : _browse! - 1; });
  }

  void _choose(Option o) {
    if (_locked) return;
    _story.choose(o);
    setState(() => _chosen = o);
  }

  String get _player {
    final av = widget.episode.characters.entries.where((e) => e.value.avatar || e.key == 'aidar').firstOrNull;
    return _s.playerName(av?.value.defaultName?.of(_l) ?? av?.value.name.of(_l) ?? 'Айдар');
  }

  bool _isAvatar(String who) => (widget.episode.characters[who]?.avatar ?? false) || who == 'aidar';
  String _speakerName(String who) => _isAvatar(who) ? _player : (widget.episode.characters[who]?.name.of(_l) ?? who);

  // ---------------------------------------------------------------- вопросы
  void _answer(String id) {
    final r = _quiz!.answer(id);
    final a = _quiz!.attempts.last;
    _runAttempts.add(a);
    _s.store.addAttempt(a);
    final prev = _s.store.srs()[a.questionId] ?? SrsState.fresh(a.at);
    _s.store.saveSrs(a.questionId, _s.scheduler.review(prev, correct: a.correct, now: a.at));
    setState(() => _result = r);
  }

  Future<void> _afterExplain() async {
    setState(() => _result = null);
    if (!_quiz!.done) return;
    if (_finalTest) { await _complete(); return; }
    _quiz = null;
    _advance();
  }

  Future<void> _complete() async {
    final q = _quiz!;
    final before = _s.store.completions(_id);
    await _s.store.saveResult(_id, q.correctCount, q.total);
    await _s.store.bumpCompletions(_id);
    await _s.store.addTest(TestResult(kind: 'final', correct: q.correctCount, total: q.total, at: DateTime.now(), episode: _id));
    await _s.store.clearStory(_id);
    await _s.store.clearContinueMeta(_id);
    final granted = [
      ..._s.awards.onEpisodeCompleted(completionsBefore: before, runAttempts: _runAttempts),
      ..._s.awards.onTest(correct: q.correctCount, total: q.total),
    ];
    for (final a in granted) { await _s.store.grantAward(a.id); }
    _s.touch();
    setState(() {});
    if (!mounted) return;
    for (final a in granted) {
      await AwardScreen.show(context, _s, a, _s.store.awards()[a.id] ?? 1);
    }
  }

  // ---------------------------------------------------------------- меню
  Future<void> _menu() async {
    final scene = _story.scene;
    final a = await showSceneMenu(context, _s,
        episodeTitle: widget.episode.title.of(_l), sceneTitle: scene.title?.of(_l), era: widget.episode.era ?? '',
        sceneIndex: widget.episode.indexOf(scene.id), sceneCount: widget.episode.scenes.length,
        sourcesCount: widget.questions.map((q) => q.source.split('#').first).toSet().length);
    if (!mounted || a == null) return;
    switch (a) {
      case MenuAction.resume: break;
      case MenuAction.saveExit: Navigator.of(context).pop();
      case MenuAction.restart:
        await _s.store.clearStory(_id); await _s.store.clearContinueMeta(_id);
        setState(() { _story = StoryRunner(widget.episode); _transcript.clear(); _browse = null; _quiz = null; _result = null; _finalTest = false; _chosen = null; });
        _advance();
      case MenuAction.toggleLang: _s.locale.set(_l == 'kk' ? 'ru' : 'kk'); setState(() {});
      case MenuAction.toggleSound: await _s.store.setSound(!_s.store.sound); setState(() {});
      case MenuAction.cycleSpeed: await _s.store.setTextSpeed((_s.store.textSpeed + 1) % 3); setState(() {});
      case MenuAction.transcript: _showTranscript();
      case MenuAction.sources: _showSources();
    }
  }

  void _showTranscript() => showModalBottomSheet(
        context: context, backgroundColor: const Color(0xF21A140F), isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => DraggableScrollableSheet(
          expand: false, initialChildSize: .7,
          builder: (_, ctrl) => ListView.separated(
            controller: ctrl, padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            itemCount: _transcript.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (_, i) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_speakerName(_transcript[i].who).toUpperCase(), style: st(11, w: 700, color: C.gold, spacing: 1)),
              const SizedBox(height: 4),
              Text(_transcript[i].text.ofPlayer(_l, _player), style: st(15, height: 1.45)),
            ]),
          ),
        ),
      );

  void _showSources() {
    final srcs = widget.questions.map((q) => q.source.split('#').first).toSet().toList()..sort();
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xF21A140F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_s.s('sources'), style: st(17, w: 600)),
          const SizedBox(height: 12),
          for (final id in srcs) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
            const Icon(Icons.description_outlined, size: 18, color: C.gold), const SizedBox(width: 10),
            Expanded(child: Text(id.replaceAll('_', ' '), style: st(15))),
          ])),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- вид
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _s.locale,
        builder: (context, _) => Scaffold(backgroundColor: C.ground, body: _body()),
      );

  Widget _body() {
    final s = _s.s;
    if (_result != null) return SafeArea(child: _center(ExplainView(result: _result!, locale: _l, onNext: _afterExplain)));
    if (_quiz != null) {
      if (_quiz!.done && _finalTest) {
        return SafeArea(child: _center(ScoreView(
          title: s('ep.done'), correct: _quiz!.correctCount, total: _quiz!.total, caption: s('ep.done.sub'),
          buttonLabel: s('to.home'), onDone: () => Navigator.of(context).pop())));
      }
      final p = _quiz!.current()!;
      return SafeArea(child: _center(QuestionView(
        presented: p, index: _quiz!.index, total: _quiz!.total, locale: _l,
        label: _finalTest ? s('final.test') : s('check'),
        contextScene: p.question.context == null ? null : widget.episode.sceneById(p.question.context!),
        onAnswer: _answer)));
    }
    final e = _event;
    if (_browse != null && _browse! < _transcript.length) {
      final ln = _transcript[_browse!];
      return _SayView(this, ln.scene, Say(who: ln.who, text: ln.text, emo: ln.emo), browsing: true);
    }
    if (_chosen != null && e is BeatEvent) return _ChoiceMadeView(this, e.scene, _chosen!);
    if (e is BeatEvent) {
      final b = e.beat;
      if (b is Say) return _SayView(this, e.scene, b);
      if (b is Choice) return _ChoiceView(this, e.scene, b);
    }
    return const Center(child: CircularProgressIndicator(color: C.gold));
  }

  Widget _center(Widget w) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: w));

  double get _progress {
    final i = widget.episode.indexOf(_story.scene.id);
    return (i + 1) / widget.episode.scenes.length;
  }
}

/// Прочитанная реплика — для «Артқа» и списка «Оқылған мәтін».
class _Line {
  const _Line({required this.scene, required this.beat, required this.who, required this.text, required this.emo});
  final Scene scene; final int beat; final String who; final L10n text; final String emo;
  Map<String, Object> toJson() => {'s': scene.id, 'b': beat};
}

// ---------------------------------------------------------------- общие части сюжета
class _Art extends StatelessWidget {
  const _Art({required this.url, required this.pan, this.file});
  final String url; final int pan; final File? file;
  @override
  Widget build(BuildContext context) => Art(url: url, file: file, pan: pan, fit: BoxFit.cover, width: double.infinity, height: double.infinity, logicalWidth: MediaQuery.sizeOf(context).width);
}

class _TopBar extends StatelessWidget {
  const _TopBar(this.st_, this.scene, {this.progress});
  final _StoryScreenState st_; final Scene scene; final double? progress;
  @override
  Widget build(BuildContext context) {
    final l = st_._l;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Row(children: [
          _IconBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.of(context).pop()),
          Expanded(child: Column(children: [
            Text(st_.widget.episode.title.of(l).toUpperCase(), style: st(11, w: 600, color: const Color(0xD9E8D9BD), spacing: 1.1).copyWith(shadows: _sh)),
            if (scene.title != null) Text(scene.title!.of(l), style: st(15, w: 600).copyWith(shadows: _sh)),
          ])),
          _IconBtn(Icons.menu_rounded, st_._menu),
        ]),
      ),
      if (progress != null) Padding(padding: const EdgeInsets.only(top: 10), child: OrnamentLine(progress: progress!)),
    ]);
  }
}

const _sh = [Shadow(color: Color(0xB3000000), blurRadius: 8, offset: Offset(0, 2))];

class _IconBtn extends StatelessWidget {
  const _IconBtn(this.icon, this.onTap);
  final IconData icon; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(width: 44, height: 44, child: IconButton(onPressed: onTap, icon: Icon(icon, color: C.ink, size: 22, shadows: _sh)));
}

/// Нижняя панель управления: «Артқа» и «Жалғастыру» с приглушённым таймером.
class _Controls extends StatelessWidget {
  const _Controls(this.st_, {this.browsing = false});
  final _StoryScreenState st_; final bool browsing;
  @override
  Widget build(BuildContext context) {
    final s = st_._s.s;
    final canBack = st_._canBack;
    final locked = !browsing && st_._locked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Opacity(
          opacity: canBack ? 1 : .35,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF5A4A3B)), shape: const StadiumBorder(), padding: const EdgeInsets.fromLTRB(10, 0, 14, 0), minimumSize: const Size(0, 40)),
            onPressed: canBack ? st_._back : null,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: C.inkSoft),
            label: Text(s('back'), style: st(13, color: C.inkSoft)),
          ),
        ),
        AnimatedBuilder(
          animation: st_._lock,
          builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Opacity(
              opacity: locked ? .5 : 1,
              child: Row(children: [
                Text(s('next'), style: st(15, w: 600)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: C.ink),
              ]),
            ),
            const SizedBox(height: 7),
            SizedBox(width: 118, height: 2, child: LinearProgressIndicator(value: locked ? st_._lock.value : 1, backgroundColor: const Color(0xFF332720), color: C.goldDim)),
          ]),
        ),
      ]),
    );
  }
}

/// Панель текста: прозрачная сверху, плотная книзу — сквозь неё видно кадр.
BoxDecoration _panelDeco() => const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0x00221A14), Color(0x8C221A14), Color(0xD1221A14), Color(0xF0221A14), Color(0xFA221A14)],
      stops: [0, .12, .32, .62, 1]));

// ---------------------------------------------------------------- реплика
class _SayView extends StatelessWidget {
  const _SayView(this.st_, this.scene, this.say, {this.browsing = false});
  final _StoryScreenState st_; final Scene scene; final Say say; final bool browsing;
  @override
  Widget build(BuildContext context) {
    final l = st_._l;
    final avatar = st_._isAvatar(say.who);
    final isNarrator = say.who == 'narrator';
    final name = st_._speakerName(say.who);
    final look = st_._s.store.look;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: st_._tapForward,
      child: Stack(fit: StackFit.expand, children: [
        _Art(url: st_._s.content.mediaUrl(st_._id, scene.artFor(st_._story.vars)), file: st_._s.content.mediaFile(st_._id, scene.artFor(st_._story.vars)), pan: scene.pan),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x99141010), Color(0x00141010), Color(0x00141010), Color(0x40221A14)], stops: [0, .24, .5, .75]))),
        if (avatar)
          Positioned(
            left: scene.avatarRight ? null : -18, right: scene.avatarRight ? -18 : null, top: 300, width: 267, height: 400,
            child: AvatarBust(look: look, mirror: scene.avatarRight, services: st_._s, emo: say.emo ?? 'calm'),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          decoration: _panelDeco(),
          padding: EdgeInsets.only(top: 22, bottom: 26 + MediaQuery.of(context).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!avatar) const HorizonLine(),
            if (!isNarrator)
              Padding(
                padding: EdgeInsets.fromLTRB(20, avatar ? 0 : 0, 20, 0),
                child: Transform.translate(
                  offset: Offset(0, avatar ? 0 : -18),
                  child: Row(children: [
                    if (!avatar) AvatarCircle(size: 46, look: look, services: st_._s),
                    if (!avatar) const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: C.gold, borderRadius: BorderRadius.circular(999)),
                      child: Text(name.toUpperCase(), style: st(12.5, w: 700, color: C.ground, spacing: .5)),
                    ),
                  ]),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(22, isNarrator ? 0 : (avatar ? 14 : 0), 22, 0),
              child: Align(alignment: Alignment.centerLeft, child: Text(
                say.text.ofPlayer(l, st_._player),
                style: st(19, w: 500, height: 1.45).copyWith(fontStyle: isNarrator ? FontStyle.italic : FontStyle.normal, shadows: _sh),
              )),
            ),
            _Controls(st_, browsing: browsing),
          ]),
        )),
        Positioned(left: 0, right: 0, top: MediaQuery.of(context).padding.top, child: _TopBar(st_, scene, progress: st_._progress)),
        if (browsing)
          Positioned(
            left: 0, right: 0, top: MediaQuery.of(context).padding.top + 108,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: const Color(0xB3221A14), borderRadius: BorderRadius.circular(999)),
              child: Text(st_._s.s('rereading'), style: st(11.5, w: 600, color: const Color(0xFFE8D9BD), spacing: 1)),
            )),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- развилка
class _ChoiceView extends StatelessWidget {
  const _ChoiceView(this.st_, this.scene, this.choice);
  final _StoryScreenState st_; final Scene scene; final Choice choice;
  @override
  Widget build(BuildContext context) {
    final l = st_._l; final s = st_._s.s;
    final two = choice.options.length == 2 && choice.options.every((o) => o.art != null);
    final prompt = Container(
      color: C.ground, width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(children: [
        Text(s('choose'), style: st(11, w: 600, color: C.gold, spacing: 1.4)),
        const SizedBox(height: 6),
        Text(choice.prompt.ofPlayer(l, st_._player), style: st(20, w: 700, height: 1.25), textAlign: TextAlign.center),
      ]),
    );
    final top = MediaQuery.of(context).padding.top;
    if (two) {
      Widget half(Option o, {required bool first}) => Expanded(child: GestureDetector(
            onTap: () => st_._choose(o),
            child: Stack(fit: StackFit.expand, children: [
              _Art(url: st_._s.content.mediaUrl(st_._id, o.art!), file: st_._s.content.mediaFile(st_._id, o.art!), pan: 50),
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [first ? const Color(0x9E141010) : const Color(0xD9221A14), const Color(0x00141010), const Color(0x00141010), const Color(0xEB221A14)], stops: const [0, .34, .58, 1]))),
              Positioned(left: 20, right: 20, bottom: first ? 16 : 22 + MediaQuery.of(context).padding.bottom,
                  child: Text(o.text.ofPlayer(l, st_._player), style: st(19, w: 600, height: 1.3).copyWith(shadows: _sh))),
            ]),
          ));
      return Stack(children: [
        Column(children: [
          half(choice.options[0], first: true),
          const OrnamentLine(),
          prompt,
          const OrnamentLine(),
          half(choice.options[1], first: false),
        ]),
        Positioned(left: 0, right: 0, top: top, child: _TopBar(st_, scene)),
      ]);
    }
    return Stack(fit: StackFit.expand, children: [
      _Art(url: st_._s.content.mediaUrl(st_._id, scene.artFor(st_._story.vars)), file: st_._s.content.mediaFile(st_._id, scene.artFor(st_._story.vars)), pan: scene.pan),
      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x99141010), Color(0x00141010), Color(0x00141010), Color(0x66221A14)], stops: [0, .24, .5, .8]))),
      Positioned(left: 0, right: 0, bottom: 0, child: Container(
        decoration: _panelDeco(),
        padding: EdgeInsets.only(top: 26, bottom: 26 + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const OrnamentLine(),
          const SizedBox(height: 14),
          Text(s('choose'), style: st(11, w: 600, color: C.gold, spacing: 1.4)),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 22), child: Text(choice.prompt.ofPlayer(l, st_._player), style: st(19, w: 600, height: 1.3).copyWith(shadows: _sh), textAlign: TextAlign.center)),
          const SizedBox(height: 16),
          AnimatedBuilder(animation: st_._lock, builder: (_, __) => Opacity(opacity: st_._locked ? .55 : 1, child: Column(children: [
            for (final o in choice.options) Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: SizedBox(width: double.infinity, height: 50, child: OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: C.gold), shape: const StadiumBorder(), alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 18)),
                onPressed: () => st_._choose(o),
                child: Text(o.text.ofPlayer(l, st_._player), style: st(15, w: 500)),
              )),
            ),
          ]))),
        ]),
      )),
      Positioned(left: 0, right: 0, top: top, child: _TopBar(st_, scene, progress: st_._progress)),
    ]);
  }
}

// ---------------------------------------------------------------- выбор сделан
class _ChoiceMadeView extends StatelessWidget {
  const _ChoiceMadeView(this.st_, this.scene, this.option);
  final _StoryScreenState st_; final Scene scene; final Option option;
  @override
  Widget build(BuildContext context) {
    final l = st_._l; final s = st_._s.s;
    return Stack(fit: StackFit.expand, children: [
      _Art(url: st_._s.content.mediaUrl(st_._id, option.art ?? scene.artFor(st_._story.vars)), file: st_._s.content.mediaFile(st_._id, option.art ?? scene.artFor(st_._story.vars)), pan: option.art == null ? max(scene.pan, 62) : 62),
      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0x80141010), Color(0x0D141010), Color(0x00141010), Color(0x40221A14), Color(0x80221A14)], stops: [0, .26, .46, .66, 1]))),
      Positioned(left: -18, top: 250, width: 267, height: 400, child: AvatarBust(look: st_._s.store.look, services: st_._s)),
      Positioned(left: 0, right: 0, bottom: 0, child: Container(
        decoration: _panelDeco(),
        padding: EdgeInsets.fromLTRB(24, 26, 24, 34 + MediaQuery.of(context).padding.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const OrnamentLine(),
          const SizedBox(height: 18),
          Text(s('your.choice'), style: st(11, w: 600, color: C.gold, spacing: 1.4).copyWith(shadows: _sh)),
          const SizedBox(height: 8),
          Text(option.text.ofPlayer(l, st_._player), style: st(27, w: 700, height: 1.2).copyWith(shadows: _sh)),
          const SizedBox(height: 20),
          Align(alignment: Alignment.centerRight, child: GoldButton(label: s('next'), trailingArrow: true, onTap: () => st_._advance())),
        ]),
      )),
      Positioned(left: 0, right: 0, top: MediaQuery.of(context).padding.top + 4, child: Column(children: [
        Text("NOMAD'S WAY", style: st(14, w: 800, spacing: 2.2).copyWith(shadows: _sh)),
        Text(st_.widget.episode.era ?? '', style: st(12.5, color: const Color(0xFFE8D9BD)).copyWith(shadows: _sh)),
      ])),
    ]);
  }
}
