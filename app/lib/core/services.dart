import '../data/local/progress_repository.dart';
import '../data/remote/content_repository.dart';
import '../engine/mastery.dart';
import '../engine/scheduler.dart';
import 'locale_controller.dart';

/// Всё, что нужно экранам. Без DI-фреймворка — передаётся явно.
class Services {
  Services({required this.locale, required this.store, required this.content});
  final LocaleController locale;
  final ProgressRepository store;
  final ContentRepository content;
  final scheduler = const Scheduler();
  final mastery = const Mastery();

  /// В разработке — tools/serve.py. В проде — адрес CDN из конфигурации.
  static const defaultCdn = 'http://localhost:8787';

  static Future<Services> boot() async {
    final store = await ProgressRepository.open();
    return Services(
      locale: LocaleController(),
      store: store,
      content: ContentRepository(baseUrl: defaultCdn, store: store),
    );
  }
}

/// Короткая запись для строк интерфейса, пока их мало. Вырастет — вынесем в arb.
String t(String l, {required String kk, required String ru}) => l == 'kk' ? kk : ru;
