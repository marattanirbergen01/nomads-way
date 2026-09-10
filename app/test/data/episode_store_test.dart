import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nomads_way/data/local/episode_store.dart';
import 'package:nomads_way/data/models/curriculum.dart';

/// Бандл собран tools/pack.dart и лежит в build/ — тестируем на настоящем архиве.
CatalogEntry _entry() {
  final catalog = (jsonDecode(File('../build/catalog.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  return CatalogEntry.fromJson(catalog.firstWhere((e) => e['id'] == 's1e01'));
}

void main() {
  late Directory tmp;
  late EpisodeStore store;
  late CatalogEntry entry;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nw_test_');
    entry = _entry();
    store = EpisodeStore(
      baseDir: () async => tmp,
      client: MockClient((req) async {
        final f = File('../build${req.url.path}');
        if (!f.existsSync()) return http.Response('nf', 404);
        return http.Response.bytes(f.readAsBytesSync(), 200);
      }),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('бандл собран pack.dart и описан в каталоге', () {
    expect(entry.bundle, isNotNull, reason: 'сначала dart run bin/pack.dart');
    expect(entry.bundle!.bytes, greaterThan(100000));
    expect(entry.bundle!.sha256.length, 64);
    expect(entry.bundle!.contentHash.length, 16);
  });

  test('серия скачивается, распаковывается и читается с диска', () async {
    expect(await store.state(entry), InstallState.absent);
    final steps = <double>[];
    await store.install(entry, 'http://cdn', onProgress: steps.add);

    expect(steps.last, 1.0);
    expect(steps.length, greaterThan(1), reason: 'прогресс приходит по мере загрузки');
    expect(await store.state(entry), InstallState.ready);

    final ep = await store.file('s1e01', 'episode.json');
    expect(ep, isNotNull);
    expect(jsonDecode(ep!.readAsStringSync())['id'], 's1e01');
    expect(await store.file('s1e01', 'media/cover_s1e01.jpg'), isNotNull);

    await store.warm('s1e01');
    expect(store.fileSync('s1e01', 'episode.json'), isNotNull);

    final sizes = await store.installed();
    expect(sizes['s1e01'], greaterThan(100000));
  });

  test('изменившийся контент помечается как устаревший, а не ломает игру', () async {
    await store.install(entry, 'http://cdn');
    expect(await store.state(entry), InstallState.ready);

    // сценарий и кадры первой серии ещё будут меняться — отпечаток станет другим
    final changed = CatalogEntry.fromJson({
      ...(jsonDecode(File('../build/catalog.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => e['id'] == 's1e01'),
      'bundle': {...entry.bundle!.toJsonForTest(), 'contentHash': 'ffffffffffffffff'},
    });
    expect(await store.state(changed), InstallState.outdated);
    // старая копия всё ещё читается — играть можно до обновления
    expect(await store.file('s1e01', 'episode.json'), isNotNull);
  });

  test('битый архив не устанавливается', () async {
    final bad = CatalogEntry.fromJson({
      ...(jsonDecode(File('../build/catalog.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((e) => e['id'] == 's1e01'),
      'bundle': {...entry.bundle!.toJsonForTest(), 'sha256': 'a' * 64},
    });
    await expectLater(store.install(bad, 'http://cdn'), throwsA(isA<Exception>()));
    expect(await store.state(entry), InstallState.absent, reason: 'ничего не установлено');
  });

  test('удаление стирает серию', () async {
    await store.install(entry, 'http://cdn');
    await store.remove('s1e01');
    expect(await store.state(entry), InstallState.absent);
    expect(await store.installed(), isEmpty);
  });

  test('без файловой системы всё выключается тихо', () async {
    final none = EpisodeStore(baseDir: () async => throw const FileSystemException('нет'));
    expect(await none.state(entry), InstallState.unsupported);
    expect(await none.file('s1e01', 'episode.json'), isNull);
    expect(await none.installed(), isEmpty);
    expect(none.supported, isFalse);
  });
}
