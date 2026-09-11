import 'package:flutter/foundation.dart';
import '../data/local/episode_store.dart';
import '../data/local/progress_repository.dart';
import '../data/remote/content_repository.dart';
import '../engine/awards.dart';
import '../engine/mastery.dart';
import '../engine/scheduler.dart';
import 'locale_controller.dart';
import 'strings.dart';

/// Всё, что нужно экранам. Без DI-фреймворка — передаётся явно.
class Services {
  Services({required this.locale, required this.store, required this.content});
  final LocaleController locale;
  final ProgressRepository store;
  final ContentRepository content;
  EpisodeStore get episodes => content.episodes;
  final scheduler = const Scheduler();
  final mastery = const Mastery();
  final awards = const AwardsEngine();

  /// Уведомляет вкладки, что прогресс/профиль изменились и надо перечитать хранилище.
  final changes = _Bus();
  void touch() => changes.ping();

  String get l => locale.code;
  Str get s => Str.of(locale.code);

  /// Стрик по дням с ответами; выдаёт награду за каждую семёрку.
  int streakDays() => AwardsEngine.streakDays(store.attempts().map((a) => a.at), DateTime.now());
  Future<Award?> checkStreakAward() async {
    final now = DateTime.now();
    if (!awards.streakAwardDue(streakDays(), now, store.lastStreakGrant())) return null;
    await store.grantAward(Award.streak7.id);
    await store.markStreakGrant(now);
    return Award.streak7;
  }

  /// Средняя готовность по активным темам, 0..1.
  double readiness(Iterable<String> factIds) => mastery.topic(factIds, store.attempts());

  /// Имя аватара: из профиля, иначе имя персонажа по умолчанию.
  String playerName(String fallback) => store.playerName.isEmpty ? fallback : store.playerName;

  /// Адрес CDN задаётся при сборке: --dart-define=CDN_URL=... (абсолютный или относительный, например /cdn).
  static const _cdnDefine = String.fromEnvironment('CDN_URL', defaultValue: 'http://localhost:8787');
  static String get defaultCdn => Uri.base.resolve(_cdnDefine).toString().replaceFirst(RegExp(r'/$'), '');

  static Future<Services> boot() async {
    final store = await ProgressRepository.open();
    final locale = LocaleController()..set(store.locale);
    locale.addListener(() => store.setLocale(locale.code));
    final s = Services(locale: locale, store: store, content: ContentRepository(baseUrl: defaultCdn, store: store));
    // аватары нужны везде — тянем описание сразу, но старт не ждём
    s.content.common().then((_) => s.touch()).catchError((_) {});
    return s;
  }
}

/// Короткая запись для строк интерфейса.
String t(String l, {required String kk, required String ru}) => l == 'kk' ? kk : ru;

/// Человеческая дата «3 дня назад».
String ago(DateTime at, Str s, DateTime now) {
  final d = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (d <= 0) return s('today');
  if (d == 1) return s('yesterday');
  if (d >= 7 && d < 14) return s('week.ago');
  return s('days.ago').replaceFirst('{n}', '$d');
}

class _Bus extends ChangeNotifier {
  void ping() => notifyListeners();
}
