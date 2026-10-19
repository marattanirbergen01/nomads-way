import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../engine/quiz_runner.dart';
import '../../engine/scheduler.dart';

/// Единственная точка чтения/записи прогресса. Сейчас — shared_preferences (см. DECISIONS.md);
/// замена на SQLite не должна выйти за пределы этого файла.
class ProgressRepository {
  ProgressRepository(this._p);
  final SharedPreferences _p;

  static Future<ProgressRepository> open() async => ProgressRepository(await SharedPreferences.getInstance());

  // ---- сюжет: снимок StoryRunner для возобновления.
  // Снимок хранит отпечаток контента: если сценарий изменился, старая позиция
  // указывает на сцену, которой больше нет, поэтому такой снимок отбрасывается.
  Map<String, dynamic>? storySnapshot(String ep, {String? contentHash}) {
    final j = _json('story:$ep');
    if (j == null) return null;
    if (contentHash != null && j['hash'] != null && j['hash'] != contentHash) return null;
    return j;
  }
  Future<void> saveStory(String ep, Map<String, dynamic> snap, {String? contentHash}) =>
      _p.setString('story:$ep', jsonEncode({...snap, if (contentHash != null) 'hash': contentHash}));
  Future<void> clearStory(String ep) => _p.remove('story:$ep');

  // ---- переменные сюжета на конце серии: следующая серия сезона стартует с ними
  Map<String, Map<String, int>> endVars() => {
        for (final e in (_json('vars.end') ?? {}).entries)
          e.key: {for (final v in (e.value as Map).entries) v.key as String: (v.value as num).toInt()},
      };
  Future<void> saveEndVars(String ep, Map<String, int> vars) async {
    final j = _json('vars.end') ?? {};
    j[ep] = vars;
    await _p.setString('vars.end', jsonEncode(j));
  }

  // ---- результат серии
  EpisodeResult? result(String ep) {
    final j = _json('done:$ep');
    return j == null ? null : EpisodeResult(correct: j['c'], total: j['t'], at: DateTime.parse(j['at']));
  }
  Future<void> saveResult(String ep, int correct, int total) =>
      _p.setString('done:$ep', jsonEncode({'c': correct, 't': total, 'at': DateTime.now().toIso8601String()}));

  // ---- попытки (append-only)
  List<Attempt> attempts() =>
      [for (final a in (_list('attempts') ?? [])) Attempt.fromJson(a as Map<String, dynamic>)];
  Future<void> addAttempt(Attempt a) async {
    final l = _list('attempts') ?? [];
    l.add(a.toJson());
    await _p.setString('attempts', jsonEncode(l));
  }

  // ---- интервальное повторение
  Map<String, SrsState> srs() {
    final j = _json('srs') ?? {};
    return {for (final e in j.entries) e.key: SrsState.fromJson(e.value as Map<String, dynamic>)};
  }
  Future<void> saveSrs(String qid, SrsState s) async {
    final j = _json('srs') ?? {};
    j[qid] = s.toJson();
    await _p.setString('srs', jsonEncode(j));
  }

  // ---- продолжение серии: лёгкая мета, чтобы главный экран не грузил бандл
  ContinueMeta? continueMeta(String ep) {
    final j = _json('cont:$ep');
    return j == null ? null : ContinueMeta(ep: ep, sceneIndex: j['i'], sceneCount: j['n'], at: DateTime.parse(j['at']));
  }
  Future<void> saveContinueMeta(String ep, int sceneIndex, int sceneCount) =>
      _p.setString('cont:$ep', jsonEncode({'i': sceneIndex, 'n': sceneCount, 'at': DateTime.now().toIso8601String()}));
  Future<void> clearContinueMeta(String ep) => _p.remove('cont:$ep');

  // ---- сколько раз серия пройдена целиком
  int completions(String ep) => _p.getInt('done.n:$ep') ?? 0;
  Future<void> bumpCompletions(String ep) => _p.setInt('done.n:$ep', completions(ep) + 1);

  // ---- сынақ тестер и қорытынды тестер: история результатов
  List<TestResult> tests() =>
      [for (final t in (_list('tests') ?? [])) TestResult.fromJson(t as Map<String, dynamic>)];
  Future<void> addTest(TestResult t) async {
    final l = _list('tests') ?? [];
    l.add(t.toJson());
    await _p.setString('tests', jsonEncode(l));
  }

  /// Вопросы последних [n] вариантов на банке (пробник и быстрая тренировка).
  Set<String> recentBankQuestions({int n = 3}) => {
        for (final t in tests().where((t) => t.kind == 'mock' || t.kind == 'quick').toList().reversed.take(n)) ...t.questions,
      };

  // ---- марапаттар: id → сколько раз получено
  Map<String, int> awards() => {for (final e in (_json('awards') ?? {}).entries) e.key: (e.value as num).toInt()};
  Future<void> grantAward(String id) async {
    final a = awards();
    a[id] = (a[id] ?? 0) + 1;
    await _p.setString('awards', jsonEncode(a));
  }
  DateTime? lastStreakGrant() { final s = _p.getString('award.streak.at'); return s == null ? null : DateTime.parse(s); }
  Future<void> markStreakGrant(DateTime d) => _p.setString('award.streak.at', d.toIso8601String());

  // ---- профиль: имя аватара, внешность, язык, настройки
  String get playerName => _p.getString('pf.name') ?? '';
  Future<void> setPlayerName(String v) => _p.setString('pf.name', v.trim());
  int get look => _p.getInt('pf.look') ?? 1;
  Future<void> setLook(int v) => _p.setInt('pf.look', v);
  String get locale => _p.getString('pf.locale') ?? 'kk';
  Future<void> setLocale(String v) => _p.setString('pf.locale', v);
  bool get sound => _p.getBool('pf.sound') ?? true;
  Future<void> setSound(bool v) => _p.setBool('pf.sound', v);
  int get textSpeed => _p.getInt('pf.speed') ?? 1; // 0 медленно · 1 средне · 2 быстро
  Future<void> setTextSpeed(int v) => _p.setInt('pf.speed', v);
  bool get notifications => _p.getBool('pf.notif') ?? false;
  Future<void> setNotifications(bool v) => _p.setBool('pf.notif', v);
  String get realName => _p.getString('pf.real') ?? '';
  Future<void> setRealName(String v) => _p.setString('pf.real', v.trim());
  String get surname => _p.getString('pf.surname') ?? '';
  Future<void> setSurname(String v) => _p.setString('pf.surname', v.trim());
  String get grade => _p.getString('pf.grade') ?? '';
  Future<void> setGrade(String v) => _p.setString('pf.grade', v.trim());
  String get email => _p.getString('pf.email') ?? '';
  Future<void> setEmail(String v) => _p.setString('pf.email', v.trim());

  /// Размер кэша контента в байтах — для строки «Жүктелген сериялар».
  int cacheBytes() => _p.getKeys().where((k) => k.startsWith('cache:')).fold(0, (n, k) => n + (_p.getString(k)?.length ?? 0));

  // ---- кэш контента (сырой JSON бандлов), чтобы работать офлайн и повторять без сети
  String? cached(String key) => _p.getString('cache:$key');
  Future<void> cache(String key, String json) => _p.setString('cache:$key', json);

  Future<void> wipe() => _p.clear();

  Map<String, dynamic>? _json(String k) { final s = _p.getString(k); return s == null ? null : jsonDecode(s) as Map<String, dynamic>; }
  List<dynamic>? _list(String k) { final s = _p.getString(k); return s == null ? null : jsonDecode(s) as List; }
}

class EpisodeResult {
  const EpisodeResult({required this.correct, required this.total, required this.at});
  final int correct; final int total; final DateTime at;
}

class ContinueMeta {
  const ContinueMeta({required this.ep, required this.sceneIndex, required this.sceneCount, required this.at});
  final String ep; final int sceneIndex; final int sceneCount; final DateTime at;
  double get fraction => sceneCount == 0 ? 0 : sceneIndex / sceneCount;
}

class TestResult {
  const TestResult({required this.kind, required this.correct, required this.total, required this.at, this.episode, this.questions = const []});
  final String kind; // 'final' | 'mock' | 'quick'
  final int correct; final int total; final DateTime at; final String? episode;
  /// Вопросы варианта — чтобы следующий пробник не повторял их, пока в банке хватает других.
  final List<String> questions;
  Map<String, dynamic> toJson() => {
        'k': kind, 'c': correct, 't': total, 'at': at.toIso8601String(), if (episode != null) 'ep': episode,
        if (questions.isNotEmpty) 'q': questions,
      };
  factory TestResult.fromJson(Map<String, dynamic> j) => TestResult(
        kind: j['k'], correct: j['c'], total: j['t'], at: DateTime.parse(j['at']), episode: j['ep'],
        questions: (j['q'] as List?)?.cast<String>() ?? const [],
      );
}
