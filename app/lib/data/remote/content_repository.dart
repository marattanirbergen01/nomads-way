import 'dart:convert';
import 'package:http/http.dart' as http;
import '../local/progress_repository.dart';
import '../models/curriculum.dart';
import '../models/episode.dart';
import '../models/question.dart';

/// Контент: сначала сеть, при успехе — в кэш; без сети — из кэша.
/// Позже: проверка хэшей из manifest.json, фоновая докачка.
class ContentRepository {
  ContentRepository({required this.baseUrl, required this.store, http.Client? client}) : _client = client ?? http.Client();
  String baseUrl;
  final ProgressRepository store;
  final http.Client _client;

  Future<List<CatalogEntry>> catalog() async =>
      [for (final e in await _get('catalog.json') as List) CatalogEntry.fromJson(e)];

  Future<List<Topic>> curriculum() async =>
      [for (final t in await _get('curriculum.json') as List) Topic.fromJson(t)];

  Future<(Episode, List<Question>)> episode(String id) async {
    final ep = await _get('$id/episode.json');
    final qs = await _get('$id/questions.json');
    return (Episode.fromJson(ep), [for (final q in qs as List) Question.fromJson(q)]);
  }

  /// Вопросы всех когда-либо загруженных серий — из кэша, синхронно. Для режима повторения.
  List<Question> cachedQuestions(Iterable<String> episodeIds) => [
        for (final id in episodeIds)
          if (store.cached('$id/questions.json') case final s?)
            for (final q in jsonDecode(s) as List) Question.fromJson(q),
      ];

  /// Адрес картинки: build/media/`<season>`/`<id>`.jpg. Сезон выводится из id серии (s1e01 → s1).
  String mediaUrl(String episodeId, String artId) => '$baseUrl/media/${_season(episodeId)}/$artId.jpg';
  static String _season(String episodeId) => RegExp(r'^(s\d+)').firstMatch(episodeId)?.group(1) ?? 's1';

  Future<dynamic> _get(String path) async {
    try {
      final r = await _client.get(Uri.parse('$baseUrl/$path')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception('GET $path → ${r.statusCode}');
      final text = utf8.decode(r.bodyBytes);
      await store.cache(path, text);
      return jsonDecode(text);
    } catch (e) {
      final c = store.cached(path);
      if (c != null) return jsonDecode(c);
      rethrow;
    }
  }
}
