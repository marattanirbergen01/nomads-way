// build/ → build/bundles/<episode>.zip + отпечаток в catalog.json.
//
// Серия качается одним файлом и играется с диска: без сети во время игры и
// без двадцати отдельных запросов посреди сцены. Отпечаток (sha256 содержимого)
// нужен, чтобы клиент понял, что серия изменилась, и предложил обновить —
// сценарий и кадры первой серии ещё будут меняться.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  final root = _repoRoot();
  final build = Directory(p.join(root, 'build'));
  if (!build.existsSync()) {
    stderr.writeln('build/ не собран — сначала dart run bin/compile.dart');
    exit(1);
  }
  final catalogFile = File(p.join(build.path, 'catalog.json'));
  final catalog = (jsonDecode(catalogFile.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final outDir = Directory(p.join(build.path, 'bundles'))..createSync(recursive: true);

  var packed = 0;
  for (final entry in catalog) {
    if (entry['planned'] == true) continue;
    final id = entry['id'] as String;
    final epDir = Directory(p.join(build.path, id));
    if (!epDir.existsSync()) { stderr.writeln('$id: нет build/$id — пропущено'); continue; }
    final season = entry['season'] as String? ?? 's1';

    // что кладём в бандл: json серии + её кадры (по манифесту) + обложка
    final files = <String, File>{};
    for (final name in const ['episode.json', 'questions.json']) {
      files[name] = File(p.join(epDir.path, name));
    }
    final manifest = jsonDecode(File(p.join(epDir.path, 'manifest.json')).readAsStringSync()) as Map<String, dynamic>;
    final media = <String>{...(manifest['media'] as List).cast<String>(), 'cover_$id'};
    var missing = 0;
    // кадр может быть png (карта): расширение из episode.json → mediaExt, по умолчанию jpg
    final ext = ((jsonDecode(files['episode.json']!.readAsStringSync()) as Map)['mediaExt'] as Map?) ?? const {};
    for (final m in media) {
      final e = (ext[m] as String?) ?? 'jpg';
      final f = File(p.join(build.path, 'media', season, '$m.$e'));
      if (f.existsSync()) { files['media/$m.$e'] = f; } else { missing++; }
    }

    // ролики карт и их постеры (имена готовые, из manifest.motionFiles)
    for (final name in ((manifest['motionFiles'] as List?) ?? const []).cast<String>()) {
      final f = File(p.join(build.path, 'media', season, name));
      if (f.existsSync()) { files['media/$name'] = f; } else { missing++; }
    }

    final b = _writeBundle(outDir, id, files);
    entry['bundle'] = b;
    packed++;
    stdout.writeln('$id  ${files.length} файлов  ${((b['bytes'] as int) / 1024 / 1024).toStringAsFixed(1)} МБ  отпечаток ${b['contentHash']}'
        '${missing > 0 ? '  (нет $missing кадров)' : ''}');
  }

  catalogFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(catalog));

  // ---- общий пакет: аватары и баннер сезона — нужны в каждой серии, качаются один раз
  final commonFile = File(p.join(build.path, 'common.json'));
  if (commonFile.existsSync()) {
    final common = jsonDecode(commonFile.readAsStringSync()) as Map<String, dynamic>;
    final files = <String, File>{};
    for (final a in (common['avatars'] as List).cast<Map<String, dynamic>>()) {
      final season = a['season'] as String;
      for (final emo in (a['emotions'] as List).cast<String>()) {
        for (final name in ['${a['id']}_${emo}_bust.png', '${a['id']}_$emo.jpg']) {
          files['media/$season/avatars/$name'] = File(p.join(build.path, 'media', season, 'avatars', name));
        }
      }
    }
    for (final c in ((common['characters'] as List?) ?? []).cast<Map<String, dynamic>>()) {
      final name = '${c['id']}.jpg';
      files['media/${c['season']}/characters/$name'] = File(p.join(build.path, 'media', c['season'] as String, 'characters', name));
    }
    final banner = File(p.join(build.path, 'media', 's1', 'cover_season1.jpg'));
    if (banner.existsSync()) files['media/s1/cover_season1.jpg'] = banner;
    if (files.isNotEmpty) {
      final entry = _writeBundle(outDir, 'common', files);
      common['bundle'] = entry;
      stdout.writeln('common  ${files.length} файлов  ${((entry['bytes'] as int) / 1024 / 1024).toStringAsFixed(1)} МБ  отпечаток ${entry['contentHash']}');
    }

    // ---- банк пробника: вопросы школы + карты к ним, качается один раз на «Жаттығу»
    final bankDir = Directory(p.join(build.path, 'bank'));
    if (common['bank'] is Map && File(p.join(bankDir.path, 'bank.json')).existsSync()) {
      final bf = <String, File>{
        for (final f in bankDir.listSync(recursive: true).whereType<File>())
          p.relative(f.path, from: bankDir.path).replaceAll(r'\\', '/'): f,
      };
      final entry = _writeBundle(outDir, 'bank', bf);
      (common['bank'] as Map)['bundle'] = entry;
      stdout.writeln('bank  ${bf.length} файлов  ${((entry['bytes'] as int) / 1024 / 1024).toStringAsFixed(1)} МБ  отпечаток ${entry['contentHash']}');
    }
    commonFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(common));
  }
  stdout.writeln('\nбандлов: $packed + common + bank → ${outDir.path}');
}

/// Пишет zip из файлов и возвращает описание бандла для каталога.
Map<String, Object?> _writeBundle(Directory outDir, String id, Map<String, File> files) {
  final names = files.keys.toList()..sort();
  final buf = <int>[];
  for (final n in names) { buf.addAll(utf8.encode(n)); buf.addAll(files[n]!.readAsBytesSync()); }
  final hash = sha256.convert(buf).toString().substring(0, 16);
  final zipPath = p.join(outDir.path, '$id.zip');
  final enc = ZipFileEncoder()..create(zipPath);
  for (final n in names) { enc.addArchiveFile(ArchiveFile(n, files[n]!.lengthSync(), files[n]!.readAsBytesSync())); }
  enc.close();
  final zip = File(zipPath);
  return {
    'url': 'bundles/$id.zip', 'bytes': zip.lengthSync(),
    'sha256': sha256.convert(zip.readAsBytesSync()).toString(), 'contentHash': hash, 'files': names.length,
  };
}

String _repoRoot() {
  var d = Directory.current;
  while (!File(p.join(d.path, 'CLAUDE.md')).existsSync() || !Directory(p.join(d.path, 'content')).existsSync()) {
    if (d.parent.path == d.path) throw StateError('Не найден корень репозитория');
    d = d.parent;
  }
  return d.path;
}
