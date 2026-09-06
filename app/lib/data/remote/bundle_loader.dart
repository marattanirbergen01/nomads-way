import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/episode.dart';
import '../models/question.dart';

/// Загружает скомпилированную серию с CDN. В разработке — tools/serve.py на localhost:8787.
/// Позже здесь появится кэш на диске и проверка хэшей из manifest.json.
class BundleLoader {
  BundleLoader({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  Future<(Episode, List<Question>)> load(String episodeId) async {
    final ep = await _json('$episodeId/episode.json');
    final qs = await _json('$episodeId/questions.json');
    return (Episode.fromJson(ep as Map<String, dynamic>), [for (final q in qs as List) Question.fromJson(q)]);
  }

  Future<dynamic> _json(String path) async {
    final r = await _client.get(Uri.parse('$baseUrl/$path'));
    if (r.statusCode != 200) throw Exception('GET $path → ${r.statusCode}');
    return jsonDecode(utf8.decode(r.bodyBytes));
  }
}
