import 'dart:convert';
import 'dart:io' show File;

import 'package:http/http.dart' as http;
import '../local/episode_store.dart';
import '../local/progress_repository.dart';
import '../models/curriculum.dart';
import '../models/episode.dart';
import '../models/question.dart';

/// Контент: сначала сеть, при успехе — в кэш; без сети — из кэша.
/// Позже: проверка хэшей из manifest.json, фоновая докачка.
class ContentRepository {
  ContentRepository({required this.baseUrl, required this.store, EpisodeStore? episodes, http.Client? client})
      : episodes = episodes ?? EpisodeStore(client: client),
        _client = client ?? http.Client();
  String baseUrl;
  final ProgressRepository store;
  final EpisodeStore episodes;
  final http.Client _client;

  Future<List<CatalogEntry>> catalog() async =>
      [for (final e in await _get('catalog.json') as List) CatalogEntry.fromJson(e)];

  Future<List<Topic>> curriculum() async =>
      [for (final t in await _get('curriculum.json') as List) Topic.fromJson(t)];

  CommonInfo? _common;
  /// Аватары и общий бандл. Кэшируется на сессию; пока не загружено — пусто.
  CommonInfo? get commonSync => _common;
  Future<CommonInfo> common() async {
    await episodes.warm('common');
    final c = CommonInfo.fromJson((await _get('common.json') as Map).cast<String, dynamic>());
    _common = c;
    return c;
  }

  /// Кадр аватара: файл из общего пакета, если он установлен; иначе адрес на CDN.
  String avatarUrl(AvatarLook a, String name) => '$baseUrl/media/${a.season}/avatars/$name';
  File? avatarFile(AvatarLook a, String name) => episodes.fileSync('common', 'media/${a.season}/avatars/$name');

  /// Установленная серия читается с диска; иначе из сети (и в браузере всегда из сети).
  Future<(Episode, List<Question>)> episode(String id) async {
    await episodes.warm(id);
    final local = await episodes.file(id, 'episode.json');
    if (local != null) {
      final qf = await episodes.file(id, 'questions.json');
      if (qf != null) {
        final ep = jsonDecode(local.readAsStringSync());
        final qs = jsonDecode(qf.readAsStringSync()) as List;
        await store.cache('$id/questions.json', qf.readAsStringSync());
        final e = Episode.fromJson(ep);
        _ext[id] = e.mediaExt;
        return (e, [for (final q in qs) Question.fromJson(q)]);
      }
    }
    final ep = await _get('$id/episode.json');
    final qs = await _get('$id/questions.json');
    final e = Episode.fromJson(ep);
    _ext[id] = e.mediaExt;
    return (e, [for (final q in qs as List) Question.fromJson(q)]);
  }

  /// Вопросы всех когда-либо загруженных серий — из кэша, синхронно. Для режима повторения.
  List<Question> cachedQuestions(Iterable<String> episodeIds) => [
        for (final id in episodeIds)
          if (store.cached('$id/questions.json') case final s?)
            for (final q in jsonDecode(s) as List) Question.fromJson(q),
      ];

  /// Адрес картинки: build/media/`<season>`/`<id>`.jpg. Сезон выводится из id серии (s1e01 → s1).
  /// Расширения медиа по сериям, отличные от jpg (карта — png). Заполняется при загрузке серии.
  final _ext = <String, Map<String, String>>{};
  String _extOf(String episodeId, String artId) => _ext[episodeId]?[artId] ?? 'jpg';

  /// Адрес картинки: build/media/`<season>`/`<id>`.`<ext>`. Сезон выводится из id серии (s1e01 → s1).
  String mediaUrl(String episodeId, String artId) => '$baseUrl/media/${_season(episodeId)}/$artId.${_extOf(episodeId, artId)}';
  static String _season(String episodeId) => RegExp(r'^(s\d+)').firstMatch(episodeId)?.group(1) ?? 's1';

  /// Кадр из установленной серии, если она скачана. Виджеты предпочитают файл сети.
  File? mediaFile(String episodeId, String artId) => episodes.fileSync(episodeId, 'media/$artId.${_extOf(episodeId, artId)}');

  /// Портрет исторического лица из общего пакета.
  String characterUrl(CharacterPortrait c) => '$baseUrl/media/${c.season}/characters/${c.id}.jpg';
  File? characterFile(CharacterPortrait c) => episodes.fileSync('common', 'media/${c.season}/characters/${c.id}.jpg');

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
