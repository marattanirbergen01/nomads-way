import 'package:flutter/painting.dart' show Alignment;

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
  const AvatarLook({required this.look, required this.id, required this.season, required this.emotions, this.faceY = 0.33, this.aspect = 0.78});
  final int look; final String id; final String season; final List<String> emotions;
  /// Где лицо по вертикали, доля высоты кадра (0 — верх). Компилятор находит по альфе.
  final double faceY;
  /// Ширина / высота кадра.
  final double aspect;
  String bust(String emo) => '${id}_${emotions.contains(emo) ? emo : 'calm'}_bust.png';
  String face(String emo) => '${id}_${emotions.contains(emo) ? emo : 'calm'}.jpg';

  /// Выравнивание для квадратного кружка при BoxFit.cover: лицо садится на [target] высоты кружка.
  /// 0.40 выбрано так, чтобы все три готовые внешности сошлись: у самой «высокой» из них
  /// лицо даже при верхнем окне не опускается ниже 0.39.
  /// Портрет уже, чем квадрат, поэтому обрезается по вертикали; окно двигаем так, чтобы лицо
  /// у всех внешностей оказалось на одной высоте.
  Alignment circleAlignment({double target = .40}) {
    final vis = aspect >= 1 ? 1.0 : aspect;          // видимая доля высоты
    if (vis >= 1) return Alignment.center;
    final t = (faceY - target * vis).clamp(0.0, 1 - vis); // верх окна, доля высоты
    return Alignment(0, (2 * t / (1 - vis) - 1).clamp(-1.0, 1.0));
  }

  factory AvatarLook.fromJson(Map<String, dynamic> j) => AvatarLook(
        look: (j['look'] as num).toInt(), id: j['id'], season: j['season'],
        emotions: (j['emotions'] as List).cast<String>(),
        faceY: (j['faceY'] as num?)?.toDouble() ?? 0.33,
        aspect: (j['aspect'] as num?)?.toDouble() ?? 0.78,
      );
}

/// Портрет исторического лица в общем пакете.
class CharacterPortrait {
  const CharacterPortrait({required this.id, required this.season});
  final String id; final String season;
}

/// Общий для всех серий контент: аватары, портреты персонажей, общий бандл.
class CommonInfo {
  const CommonInfo({required this.avatars, this.characters = const [], this.bundle, this.bank});
  final List<AvatarLook> avatars;
  final List<CharacterPortrait> characters;
  final Bundle? bundle;
  /// Банк пробника ЕНТ: сводка и бандл. null — банк не собран.
  final BankInfo? bank;
  AvatarLook? byLook(int n) => avatars.where((a) => a.look == n).firstOrNull;
  CharacterPortrait? portrait(String id) => characters.where((c) => c.id == id).firstOrNull;
  factory CommonInfo.fromJson(Map<String, dynamic> j) => CommonInfo(
        avatars: [for (final a in (j['avatars'] as List? ?? [])) AvatarLook.fromJson(a)],
        characters: [for (final c in (j['characters'] as List? ?? [])) CharacterPortrait(id: c['id'], season: c['season'])],
        bundle: j['bundle'] == null ? null : Bundle.fromJson((j['bundle'] as Map).cast<String, dynamic>()),
        bank: j['bank'] == null ? null : BankInfo.fromJson((j['bank'] as Map).cast<String, dynamic>()),
      );
}

/// Сводка банка из common.json: хватает ли вопросов на вариант, где лежит бандл.
class BankInfo {
  const BankInfo({required this.singleOk, required this.contextsOk, this.bundle});
  final int singleOk;
  final int contextsOk;
  final Bundle? bundle;
  factory BankInfo.fromJson(Map<String, dynamic> j) => BankInfo(
        singleOk: (j['singleOk'] as num?)?.toInt() ?? 0,
        contextsOk: (j['contextsOk'] as num?)?.toInt() ?? 0,
        bundle: j['bundle'] == null ? null : Bundle.fromJson((j['bundle'] as Map).cast<String, dynamic>()),
      );
}
