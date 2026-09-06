import '../../core/l10n.dart';

/// Плоское дерево тем из build/curriculum.json — только узлы с фактами.
class Topic {
  Topic({required this.id, required this.parent, required this.title, required this.status, required this.facts});
  final String id;
  final String? parent;
  final L10n title;
  final String? status;
  final List<Fact> facts;
  Iterable<String> get factIds => facts.map((f) => f.id);

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        id: j['id'], parent: j['parent'], title: L10n.fromJson(j['title']), status: j['status'],
        facts: [for (final f in j['facts']) Fact(id: f['id'], text: L10n({'kk': f['kk'] ?? '', 'ru': f['ru'] ?? ''}))],
      );
}

class Fact {
  Fact({required this.id, required this.text});
  final String id;
  final L10n text;
}

class CatalogEntry {
  CatalogEntry({required this.id, required this.title, required this.era, required this.scenes, required this.questions, required this.approved});
  final String id;
  final L10n title;
  final String? era;
  final int scenes;
  final int questions;
  final bool approved;
  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        id: j['id'], title: L10n.fromJson(j['title']), era: j['era'],
        scenes: j['scenes'], questions: j['questions'], approved: j['approved'] == true,
      );
}
