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
  bool periodActive(String periodId) => under(periodId).any((t) => !t.planned);
}

class Fact {
  Fact({required this.id, required this.text});
  final String id;
  final L10n text;
}

class CatalogEntry {
  CatalogEntry({required this.id, required this.title, required this.era, required this.scenes, required this.questions, required this.approved, required this.topics});
  final String id;
  final L10n title;
  final String? era;
  final int scenes;
  final int questions;
  final bool approved;
  final List<String> topics;
  /// Серия принадлежит периоду, если её тема лежит под ним (kz.4.1 → kz.4) или равна ему.
  bool inPeriod(String periodId) => topics.any((t) => t == periodId || t.startsWith('$periodId.'));
  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        id: j['id'], title: L10n.fromJson(j['title']), era: j['era'],
        scenes: j['scenes'], questions: j['questions'], approved: j['approved'] == true,
        topics: (j['topics'] as List? ?? []).cast<String>(),
      );
}
