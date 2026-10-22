import '../data/models/episode.dart';
import 'games/game_spec.dart';

/// Исполняет граф сцен серии. Чистая машина состояний, без Flutter.
///
/// Порядок внутри сцены: биты → (выбор ждёт [choose]) → [QuizBreak] с вопросами сцены → переход.
/// Вопросы всегда между сценами — правило продукта №1 зашито здесь, а не в UI.
class StoryRunner {
  StoryRunner(this.episode, {Map<String, int>? vars})
      : _sceneIdx = 0,
        vars = Map.of(vars ?? {});

  final Episode episode;
  final Map<String, int> vars;

  int _sceneIdx;
  int _beatIdx = 0;
  bool _quizEmitted = false;
  String? _pendingGoto;
  bool _awaitingChoice = false;
  bool _ended = false;
  int _gameIdx = 0;
  GameSpec? _awaitingGame;

  Scene get scene => episode.scenes[_sceneIdx];
  bool get awaitingChoice => _awaitingChoice;
  bool get ended => _ended;
  GameSpec? get awaitingGame => _awaitingGame;

  /// Игра сыграна (или пропущена — тогда partial): исход ставит переменные, как set варианта.
  void finishGame(GameOutcome o) {
    final g = _awaitingGame;
    if (g == null) throw StateError('Сейчас нет игры');
    for (final e in g.outcome(o).set.entries) { vars[e.key] = (vars[e.key] ?? 0) + e.value; }
    _awaitingGame = null;
  }

  StoryEvent next() {
    if (_ended) return const EpisodeEnd();
    if (_awaitingChoice) throw StateError('Сначала choose()');
    if (_awaitingGame != null) throw StateError('Сначала finishGame()');

    while (_beatIdx < scene.beats.length) {
      final b = scene.beats[_beatIdx++];
      if (b is Say && !b.visible(vars)) continue;   // реплика не для этой ветки
      if (b is Choice) _awaitingChoice = true;
      return BeatEvent(b, scene);
    }
    // мини-игры сцены — после реплик, до вопросов; условие when как у реплик
    while (_gameIdx < scene.games.length) {
      final g = scene.games[_gameIdx++];
      if (!g.visible(vars)) continue;
      _awaitingGame = g;
      return GameBreak(g, scene);
    }
    if (!_quizEmitted) {
      _quizEmitted = true;
      if (scene.quiz.isNotEmpty) return QuizBreak(scene.quiz, scene);
    }
    return _advance();
  }

  void choose(Option o) {
    if (!_awaitingChoice) throw StateError('Сейчас нет выбора');
    for (final e in o.set.entries) {
      vars[e.key] = (vars[e.key] ?? 0) + e.value;
    }
    _pendingGoto = o.goto;
    _awaitingChoice = false;
  }

  StoryEvent _advance() {
    final goto = _pendingGoto;
    _pendingGoto = null;
    if (goto == 'end' || (goto == null && _sceneIdx == episode.scenes.length - 1)) {
      _ended = true;
      return const EpisodeEnd();
    }
    _sceneIdx = goto == null ? _sceneIdx + 1 : episode.indexOf(goto);
    if (_sceneIdx < 0) throw StateError('goto $goto: сцена не найдена');
    _beatIdx = 0;
    _quizEmitted = false;
    _gameIdx = 0;
    return next();
  }

  /// Снимок для сохранения. Восстановление — [StoryRunner.restore].
  Map<String, dynamic> snapshot() => {
        'scene': scene.id, 'beat': _beatIdx, 'quiz': _quizEmitted,
        'goto': _pendingGoto, 'awaiting': _awaitingChoice, 'ended': _ended, 'vars': vars,
        'game': _gameIdx, if (_awaitingGame != null) 'awaitingGame': _awaitingGame!.id,
      };

  /// Восстановление терпимо к изменившемуся сценарию: если сцены больше нет
  /// или бит вне диапазона, начинаем серию заново вместо падения.
  /// [entryVars] — с чем серия начинается заново, если снимок не подошёл (перенос из прошлой серии сезона).
  factory StoryRunner.restore(Episode ep, Map<String, dynamic> s, {Map<String, int>? entryVars}) {
    final idx = ep.indexOf(s['scene'] as String? ?? '');
    if (idx < 0) return StoryRunner(ep, vars: entryVars);
    final r = StoryRunner(ep, vars: (s['vars'] as Map).cast<String, int>());
    r._sceneIdx = idx;
    r._beatIdx = (s['beat'] as int? ?? 0).clamp(0, ep.scenes[idx].beats.length);
    r._quizEmitted = s['quiz'] == true;
    final goto = s['goto'] as String?;
    r._pendingGoto = (goto == null || goto == 'end' || ep.indexOf(goto) >= 0) ? goto : null;
    r._awaitingChoice = s['awaiting'] == true;
    r._ended = s['ended'] == true;
    final games = ep.scenes[idx].games;
    r._gameIdx = (s['game'] as int? ?? 0).clamp(0, games.length);
    // ушли посреди игры — она начнётся заново с того же места
    final ag = s['awaitingGame'] as String?;
    if (ag != null) {
      final gi = games.indexWhere((g) => g.id == ag);
      if (gi >= 0) r._gameIdx = gi;
    }
    return r;
  }
}

sealed class StoryEvent { const StoryEvent(); }
class BeatEvent extends StoryEvent { const BeatEvent(this.beat, this.scene); final Beat beat; final Scene scene; }
class QuizBreak extends StoryEvent { const QuizBreak(this.questionIds, this.scene); final List<String> questionIds; final Scene scene; }
class EpisodeEnd extends StoryEvent { const EpisodeEnd(); }
class GameBreak extends StoryEvent { const GameBreak(this.game, this.scene); final GameSpec game; final Scene scene; }
