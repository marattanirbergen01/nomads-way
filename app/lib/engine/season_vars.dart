/// Переменные сюжета переносятся между сериями — но только внутри сезона (решение 2026-10-20).
///
/// Серия стартует с переменными конца ближайшей пройденной более ранней серии того же сезона.
/// Поэтому перепрохождение серии начинает её с тем, с чем игрок в неё вошёл, а не с её же прошлыми
/// выборами; новый сезон начинается с чистого листа.
class SeasonVars {
  static final _id = RegExp(r'^s(\d+)e(\d+)$');

  static (int season, int episode)? parse(String id) {
    final m = _id.firstMatch(id);
    return m == null ? null : (int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// [endVars] — переменные на конце каждой пройденной серии: id серии → vars.
  static Map<String, int> entryFor(String episodeId, Map<String, Map<String, int>> endVars) {
    final me = parse(episodeId);
    if (me == null) return {};
    String? best;
    var bestEp = -1;
    for (final id in endVars.keys) {
      final p = parse(id);
      if (p == null || p.$1 != me.$1 || p.$2 >= me.$2) continue;
      if (p.$2 > bestEp) { best = id; bestEp = p.$2; }
    }
    return best == null ? {} : Map.of(endVars[best]!);
  }
}
