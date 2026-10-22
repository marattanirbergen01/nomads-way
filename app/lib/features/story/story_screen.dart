import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/l10n.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/local/progress_repository.dart';
import '../../data/models/episode.dart';
import '../../data/models/question.dart';
import '../../engine/awards.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/scheduler.dart';
import '../../engine/season_vars.dart';
import '../../engine/story_runner.dart';
import '../../widgets/art.dart';
import '../../widgets/avatar.dart';
import '../../widgets/choice_toasts.dart';
import '../games/game_screen.dart';
import '../../widgets/ornament.dart';
import '../../widgets/scene_fx/particles.dart';
import '../../widgets/scene_fx/scene_camera.dart';
import '../../widgets/scene_fx/typewriter.dart';
import '../quiz/quiz_widgets.dart';
import '../readiness/award_screen.dart';
import 'scene_menu.dart';
import '../../widgets/scroll_buttons.dart';

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
  /// Печать текущей реплики: тап по недопечатанной строке допечатывает её, а не листает дальше.
  final _typer = TypewriterController();
  /// Реплики, которые уже допечатаны: после «Артқа» и возврата они показываются сразу целиком.
  final _typed = <int>{};
  /// Когда игрок вошёл в сцену: от этого момента считается фаза камеры, чтобы она не прыгала
  /// при смене экрана реплики на экран выбора.
  final _sceneSince = <String, DateTime>{};
  DateTime _since(Scene s) => _sceneSince.putIfAbsent(s.id, DateTime.now);

  Services get _s => widget.services;
  String get _l => _s.l;
  String get _id => widget.episode.id;
  bool get _locked => _lock.isAnimating;
  /// Выборы прошлых серий этого сезона — с ними серия начинается (и начинается заново).
  late final Map<String, int> _entryVars = SeasonVars.entryFor(_id, _s.store.endVars());

  @override
  void initState() {
    super.initState();
    final snap = _s.store.storySnapshot(_id, contentHash: widget.contentHash);
    _story = snap != null
        ? StoryRunner.restore(widget.episode, snap, entryVars: _entryVars)
        : StoryRunner(widget.episode, vars: _entryVars);
    if (snap != null) _restoreLines(snap['lines']);
    _lock.addStatusListener((_) => setState(() {}));
    _advance();
  }

  @override
  void dispose() { _lock.dispose(); _typer.dispose(); _motion?.dispose(); super.dispose(); }

  // ---------------------------------------------------------------- анимированные карты
  // Ролик кадра играет один раз за заход в серию и замирает на последнем кадре (постер — тот же кадр PNG).
  // Реплики идут поверх как обычно. При перечитывании (Артқа) и повторном входе в сцену — только постер.
  final _motionPlayed = <String>{};
  VideoPlayerController? _motion;
  String? _motionArt;
  bool _motionPlaying = false;

  Widget _sceneArt(Scene scene, String art, {bool browsing = false}) {
    final lang = widget.episode.motionLang(art, _l);
    if (lang == null) return _liveArt(scene, art);
    if (!browsing && _motionPlayed.add(art)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startMotion(art, lang));
    }
    final poster = widget.episode.motionPoster(art, lang);
    return _MotionArt(
      posterUrl: _s.content.mediaNamedUrl(_id, poster), posterFile: _s.content.mediaNamedFile(_id, poster),
      video: _motionArt == art && _motionPlaying ? _motion : null,
    );
  }

  Future<void> _startMotion(String art, String lang) async {
    final old = _motion;
    _motion = null; _motionPlaying = false;
    old?.dispose();
    final name = '${art}_$lang.mp4';
    final file = kIsWeb ? null : _s.content.mediaNamedFile(_id, name);
    final v = file != null
        ? VideoPlayerController.file(file)
        : VideoPlayerController.networkUrl(Uri.parse(_s.content.mediaNamedUrl(_id, name)));
    _motion = v; _motionArt = art;
    try {
      await v.initialize().timeout(const Duration(seconds: 6));
      if (!mounted || _motion != v) return;
      await v.setVolume(0);
      v.addListener(() {
        final x = v.value;
        if (_motionPlaying && x.isInitialized && x.duration > Duration.zero && x.position >= x.duration - const Duration(milliseconds: 50)) {
          // доиграл: остаётся постер — тот же последний кадр, без шва
          if (mounted) setState(() => _motionPlaying = false);
        }
      });
      await v.play();
      if (mounted && _motion == v) setState(() => _motionPlaying = true);
    } catch (_) {
      // нет сети, слабое устройство — просто постер
      if (mounted && _motion == v) setState(() => _motionPlaying = false);
    }
  }

  /// Кадр сцены с живой камерой и частицами (content/fx). Огонь едет вместе с картинкой,
  /// погода висит над кадром.
  Widget _liveArt(Scene scene, String art) {
    final url = _s.content.mediaUrl(_id, art), file = _s.content.mediaFile(_id, art);
    final lw = _artWidth(scene);
    final anchored = scene.fx.where((f) => f.anchored).toList();
    final ambient = scene.fx.where((f) => !f.anchored).toList();
    return Stack(fit: StackFit.expand, children: [
      SceneCamera(
        since: _since(scene), pan: scene.pan, spec: scene.camera,
        provider: Art.provider(url: url, file: file, logicalWidth: lw, dpr: MediaQuery.devicePixelRatioOf(context)),
        image: Art(url: url, file: file, fit: BoxFit.fill, logicalWidth: lw),
        anchored: anchored.isEmpty ? null : ParticleLayer(key: ValueKey('${scene.id}/$art'), fx: anchored, seed: scene.id.hashCode),
      ),
      if (ambient.isNotEmpty) ParticleLayer(key: ValueKey('${scene.id}/air'), fx: ambient, seed: scene.id.hashCode + 1),
    ]);
  }

  /// Под какую ширину декодировать кадр: камера приближает его, без запаса он мылится.
  double _artWidth(Scene scene) => MediaQuery.sizeOf(context).width * scene.camera.maxZoom;

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
    if (e is GameBreak) { _playGame(e); return; }
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
      // сюжет дочитан — выборы окончательны; следующая серия сезона начнётся с ними
      _s.store.saveEndVars(_id, _story.vars);
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
      final lang = widget.episode.motionLang(art, _l);
      if (lang != null) {
        // анимированная карта: заранее нужен её постер, а не старая картинка
        final poster = widget.episode.motionPoster(art, lang);
        return Art.provider(url: _s.content.mediaNamedUrl(_id, poster), file: _s.content.mediaNamedFile(_id, poster), logicalWidth: w, dpr: dpr);
      }
      return Art.provider(url: _s.content.mediaUrl(_id, art), file: _s.content.mediaFile(_id, art), logicalWidth: _artWidth(scenes[k]), dpr: dpr);
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
      final sid = item['s'] as String?;
      if (sid == null) continue;
      final si = widget.episode.indexOf(sid);
      if (si < 0) continue;
      final scene = widget.episode.scenes[si];
      final oid = item['o'] as String?;
      if (oid != null) {
        final opt = scene.beats.whereType<Choice>().expand((c) => c.options).where((o) => o.id == oid).firstOrNull;
        if (opt?.reply == null) continue;
        _transcript.add(_Line(scene: scene, beat: -1, who: _avatarId, text: opt!.reply!, emo: opt.replyEmo ?? 'calm', optionId: oid, art: opt.art));
        continue;
      }
      final bi = item['b'] as int?;
      if (bi == null || bi < 0 || bi >= scene.beats.length) continue;
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
    if (!_typer.isDone) { _typer.complete(); return; }
    if (_locked || _story.awaitingChoice) return;
    _advance();
  }

  bool get _canBack => _quiz == null && (_browse == null ? _transcript.length >= 2 : _browse! > 0);

  /// Назад — только перечитать. Сюжет не откатывается, выбор не отменяется.
  void _back() {
    if (!_canBack) return;
    _typer.complete(); // недопечатанная реплика считается прочитанной — назад и обратно без повторной печати
    setState(() { _browse = _browse == null ? _transcript.length - 2 : _browse! - 1; });
  }

  void _choose(Option o) {
    if (_locked) return;
    _story.choose(o);
    if (o.toasts.isNotEmpty) setState(() { _toasts = o.toasts; _toastKey++; });
    if (o.reply == null) { _advance(); return; }
    // ответ на выбор — обычная реплика аватара: без крупного повтора варианта
    _transcript.add(_Line(scene: _story.scene, beat: -1, who: _avatarId, text: o.reply!, emo: o.replyEmo ?? 'calm', optionId: o.id, art: o.art));
    _startLock(o.reply!.of(_l));
    setState(() => _chosen = o);
  }

  String get _avatarId =>
      widget.episode.characters.entries.where((e) => e.value.avatar).map((e) => e.key).firstOrNull ?? 'aidar';

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
        setState(() { _story = StoryRunner(widget.episode, vars: _entryVars); _transcript.clear(); _browse = null; _quiz = null; _result = null; _finalTest = false; _chosen = null; });
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
        builder: (context, _) => Scaffold(backgroundColor: C.ground, body: Stack(children: [
          Positioned.fill(child: _body()),
          // плашки после выбора поверх всего, тапы не перехватывают
          if (_toasts != null)
            Positioned.fill(child: ChoiceToasts(
              key: ValueKey(_toastKey), toasts: _toasts!, locale: _l,
              onAccent: _toastSound,
              onDone: () { if (mounted) setState(() => _toasts = null); },
            )),
        ])),
      );

  // ---------------------------------------------------------------- мини-игры (эксперимент)
  /// Игра на весь экран; исход ставит переменные (как вариант выбора), даёт плашки и реплику аватара.
  void _playGame(GameBreak e) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final art = e.game.art ?? e.scene.artFor(_story.vars);
      final lang = widget.episode.motionLang(art, _l);
      final name = lang == null ? null : widget.episode.motionPoster(art, lang);
      final outcome = await GameScreen.play(context, e.game, _l,
          artUrl: name == null ? _s.content.mediaUrl(_id, art) : _s.content.mediaNamedUrl(_id, name),
          artFile: name == null ? _s.content.mediaFile(_id, art) : _s.content.mediaNamedFile(_id, name));
      if (!mounted) return;
      _story.finishGame(outcome);
      final out = e.game.outcome(outcome);
      if (out.toasts.isNotEmpty) setState(() { _toasts = out.toasts; _toastKey++; });
      final reply = out.reply;
      if (reply == null || _event is! BeatEvent) { _advance(); return; }
      // ответ аватара — как после выбора: обычная реплика, следующий тап ведёт дальше
      final o = Option(id: 'game:${e.game.id}', text: e.game.title, set: const {}, goto: '', reply: reply);
      _transcript.add(_Line(scene: e.scene, beat: -1, who: _avatarId, text: reply, emo: 'calm', optionId: o.id));
      _startLock(reply.of(_l));
      setState(() => _chosen = o);
    });
  }

  // ---------------------------------------------------------------- плашки после выбора
  List<ChoiceToast>? _toasts;
  int _toastKey = 0;

  /// Звук в начале акцента: черта — тёплый звон, последствие и предмет — далёкий дабыл. По настройке «Дыбыс».
  Future<void> _toastSound(ChoiceToast t) async {
    if (!_s.store.sound) return;
    final v = VideoPlayerController.asset(
        t.kind == ToastKind.trait ? 'assets/toasts/toast_trait.wav' : 'assets/toasts/toast_consequence.wav',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await v.initialize();
      await v.setVolume(.8);
      await v.play();
      await Future<void>.delayed(const Duration(milliseconds: 900));
    } catch (_) {
      // браузер без жеста или без звука — тихо
    } finally {
      await v.dispose();
    }
  }

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
      return _SayView(this, ln.scene, Say(who: ln.who, text: ln.text, emo: ln.emo), browsing: true, artOverride: ln.art);
    }
    if (_chosen != null && e is BeatEvent) {
      final o = _chosen!;
      return _SayView(this, e.scene, Say(who: _avatarId, text: o.reply!, emo: o.replyEmo), artOverride: o.art);
    }
    if (e is BeatEvent) {
      final b = e.beat;
      if (b is Say) return _SayView(this, e.scene, b);
      if (b is Choice) return _ChoiceView(this, e.scene, b);
    }
    return const Center(child: CircularProgressIndicator(color: C.gold));
  }

  Widget _center(Widget w) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
      child: ScrollButtons(key: ValueKey('${_quiz?.index}-${_result != null}'), child: w)));

  double get _progress {
    final i = widget.episode.indexOf(_story.scene.id);
    return (i + 1) / widget.episode.scenes.length;
  }
}

/// Прочитанная реплика — для «Артқа» и списка «Оқылған мәтін».
class _Line {
  const _Line({required this.scene, required this.beat, required this.who, required this.text, required this.emo, this.optionId, this.art});
  final Scene scene; final int beat; final String who; final L10n text; final String emo;
  /// Реплика-ответ на выбор: хранится как id варианта, а не индекс бита.
  final String? optionId;
  /// Кадр, на фоне которого звучала реплика (выбранный вариант развилки).
  final String? art;
  Map<String, Object> toJson() => optionId != null ? {'s': scene.id, 'o': optionId!} : {'s': scene.id, 'b': beat};
}

// ---------------------------------------------------------------- общие части сюжета
class _Art extends StatelessWidget {
  const _Art({required this.url, required this.pan, this.file, this.alignment});
  final String url; final int pan; final File? file; final Alignment? alignment;
  @override
  Widget build(BuildContext context) => Art(url: url, file: file, pan: pan, alignment: alignment, fit: BoxFit.cover, width: double.infinity, height: double.infinity, logicalWidth: MediaQuery.sizeOf(context).width);
}

/// Анимированная карта: постер (последний кадр) вписан целиком, поверх — ролик, пока играет.
/// Целиком, а не «обрезать по экрану»: подписи у краёв карты не должны пропадать; поля — цвета фона
/// плеера, края кадра карт нарисованы в тот же цвет.
class _MotionArt extends StatelessWidget {
  const _MotionArt({required this.posterUrl, this.posterFile, this.video});
  final String posterUrl; final File? posterFile; final VideoPlayerController? video;
  static const _ground = Color(0xFF2A2019);
  @override
  Widget build(BuildContext context) {
    final v = video;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: _ground),
      Art(url: posterUrl, file: posterFile, fit: BoxFit.contain, width: double.infinity, height: double.infinity,
          logicalWidth: MediaQuery.sizeOf(context).width, fallback: const ColoredBox(color: _ground)),
      if (v != null && v.value.isInitialized)
        FittedBox(fit: BoxFit.contain, child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v))),
    ]);
  }
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
  const _SayView(this.st_, this.scene, this.say, {this.browsing = false, this.artOverride});
  final _StoryScreenState st_; final Scene scene; final Say say; final bool browsing;
  /// Кадр вместо кадра сцены — выбранный вариант развилки.
  final String? artOverride;
  @override
  Widget build(BuildContext context) {
    final avatar = st_._isAvatar(say.who);
    final isNarrator = say.who == 'narrator';
    final name = st_._speakerName(say.who);
    final look = st_._s.store.look;
    final who = st_.widget.episode.characters[say.who];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: st_._tapForward,
      child: Stack(fit: StackFit.expand, children: [
        if (artOverride != null)
          st_._liveArt(scene, artOverride!)
        else
          st_._sceneArt(scene, scene.artFor(st_._story.vars), browsing: browsing),
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
                    if (!avatar) CharacterCircle(size: 46, services: st_._s, portraitId: who?.portrait, fallbackLetter: name.isEmpty ? '·' : name[0]),
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
              child: Align(alignment: Alignment.centerLeft, child: _line(context)),
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

extension on _SayView {
  /// Живая реплика печатается по буквам; перечитываемая (Артқа) — сразу целиком.
  Widget _line(BuildContext context) {
    final text = say.text.ofPlayer(st_._l, st_._player);
    final style = st(19, w: 500, height: 1.45)
        .copyWith(fontStyle: say.who == 'narrator' ? FontStyle.italic : FontStyle.normal, shadows: _sh);
    final id = Object.hash(scene.id, text, st_._transcript.length);
    if (browsing || st_._typed.contains(id)) return Text(text, style: style);
    final cps = const [28.0, 40.0, 60.0][st_._s.store.textSpeed.clamp(0, 2)];
    return TypewriterText(
      text,
      key: ValueKey(id),
      style: style,
      controller: st_._typer,
      charsPerSecond: cps * (say.impact ? .7 : 1),
      delay: Duration(milliseconds: say.impact ? 450 : 0),
      onDone: () => st_._typed.add(id),
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
              // кадры 9:16 с небом сверху; в широкой половине показываем нижнюю часть, где юрта
              _Art(url: st_._s.content.mediaUrl(st_._id, o.art!), file: st_._s.content.mediaFile(st_._id, o.art!), pan: 50, alignment: const Alignment(0, .55)),
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
      st_._sceneArt(scene, scene.artFor(st_._story.vars)),
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

