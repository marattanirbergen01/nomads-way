/// Локализованная строка из бандла: {kk, ru, en}. kk — оригинал и запасной вариант.
class L10n {
  const L10n(this._m);
  final Map<String, String> _m;

  factory L10n.fromJson(Map<String, dynamic> j) =>
      L10n({for (final e in j.entries) e.key: e.value as String});

  String of(String locale) => _m[locale] ?? _m['kk'] ?? _m.values.firstOrNull ?? '';
  /// Реплика с подставленным именем игрока. Имя не склоняется — контент написан так,
  /// что оно стоит только в именительном падеже.
  String ofPlayer(String locale, String player) => of(locale).replaceAll('{player}', player);
  bool has(String locale) => _m.containsKey(locale);
}
