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

  // ---- сюжет: снимок StoryRunner для возобновления
  Map<String, dynamic>? storySnapshot(String ep) => _json('story:$ep');
  Future<void> saveStory(String ep, Map<String, dynamic> snap) => _p.setString('story:$ep', jsonEncode(snap));
  Future<void> clearStory(String ep) => _p.remove('story:$ep');

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
