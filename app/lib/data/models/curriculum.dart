import '../../core/l10n.dart';

/// Плоское дерево тем из build/curriculum.json — только узлы с фактами.
class Topic {
  Topic({required this.id, required this.parent, required this.title, required this.status, required this.facts, this.era});
  final String id;
  final String? parent;
  final L10n title;
  final String? status;
  final String? era;
  final List<Fact> facts;
  Iterable<String> get factIds => facts.map((f) => f.id);
  bool get isPeriod => parent == null;
  bool get planned => status == 'planned';

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        id: j['id'], parent: j['parent'], title: L10n.fromJson(j['title']), status: j['status'], era: j['era'],
        facts: [for (final f in (j['facts'] as List? ?? [])) Fact(id: f['id'], text: L10n({'kk': f['kk'] ?? '', 'ru': f['ru'] ?? ''}))],
      );
}

extension TopicsX on List<Topic> {
  List<Topic> get periods => where((t) => t.isPeriod).toList();
  List<Topic> under(String periodId) => where((t) => t.parent == periodId).toList();
  /// Все факты периода — из его тем.
  Iterable<String> periodFacts(String periodId) => under(periodId).expand((t) => t.factIds);
  /// Период открыт, если сам не помечен planned и в нём есть хоть одна живая тема.
  bool periodActive(String periodId) {
    final p = where((t) => t.id == periodId).firstOrNull;
    if (p == null || p.planned) return false;
    return under(periodId).any((t) => !t.planned);
  }
}

class Fact {
  Fact({required this.id, required this.text});
  final String id;
  final L10n text;
}

class Bundle {
  const Bundle({required this.url, required this.bytes, required this.sha256, required this.contentHash, required this.files});
  final String url; final int bytes; final String sha256; final String contentHash; final int files;
  double get mb => bytes / 1024 / 1024;
  /// Только для тестов: собрать изменённую копию описания бандла.
  Map<String, dynamic> toJsonForTest() =>
      {'url': url, 'bytes': bytes, 'sha256': sha256, 'contentHash': contentHash, 'files': files};

  factory Bundle.fromJson(Map<String, dynamic> j) => Bundle(
        url: j['url'], bytes: (j['bytes'] as num).toInt(), sha256: j['sha256'],
        contentHash: j['contentHash'], files: (j['files'] as num).toInt(),
      );
}

class CatalogEntry {
  CatalogEntry({required this.id, required this.title, required this.era, required this.scenes, required this.questions, required this.approved, required this.topics, this.number = 0, this.planned = false, this.bundle});
  final String id;
  final L10n title;
  final String? era;
  final int scenes;
  final int questions;
  final bool approved;
  final List<String> topics;
  final int number;
  /// Серия объявлена в плане, но ещё не написана — карточка закрыта.
  final bool planned;
  /// Готовый к скачиванию бандл; null у запланированных серий.
  final Bundle? bundle;
  /// Серия принадлежит периоду, если её тема лежит под ним (kz.4.1 → kz.4) или равна ему.
  bool inPeriod(String periodId) => topics.any((t) => t == periodId || t.startsWith('$periodId.'));
  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        id: j['id'], title: L10n.fromJson(j['title']), era: j['era'],
        scenes: j['scenes'], questions: j['questions'], approved: j['approved'] == true,
        topics: (j['topics'] as List? ?? []).cast<String>(),
        number: (j['number'] as num?)?.toInt() ?? 0, planned: j['planned'] == true,
        bundle: j['bundle'] == null ? null : Bundle.fromJson((j['bundle'] as Map).cast<String, dynamic>()),
      );
}


/// Внешность аватара из build/common.json.
class AvatarLook {
  const AvatarLook({required this.look, required this.id, required this.season, required this.emotions});
  final int look; final String id; final String season; final List<String> emotions;
  String bust(String emo) => '${id}_${emotions.contains(emo) ? emo : 'calm'}_bust.png';
  String face(String emo) => '${id}_${emotions.contains(emo) ? emo : 'calm'}.jpg';
  factory AvatarLook.fromJson(Map<String, dynamic> j) => AvatarLook(
        look: (j['look'] as num).toInt(), id: j['id'], season: j['season'],
        emotions: (j['emotions'] as List).cast<String>(),
      );
}

/// Общий для всех серий контент: аватары и общий бандл.
class CommonInfo {
  const CommonInfo({required this.avatars, this.bundle});
  final List<AvatarLook> avatars;
  final Bundle? bundle;
  AvatarLook? byLook(int n) => avatars.where((a) => a.look == n).firstOrNull;
  factory CommonInfo.fromJson(Map<String, dynamic> j) => CommonInfo(
        avatars: [for (final a in (j['avatars'] as List? ?? [])) AvatarLook.fromJson(a)],
        bundle: j['bundle'] == null ? null : Bundle.fromJson((j['bundle'] as Map).cast<String, dynamic>()),
      );
}
