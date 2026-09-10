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
    for (final m in media) {
      final f = File(p.join(build.path, 'media', season, '$m.jpg'));
      if (f.existsSync()) { files['media/$m.jpg'] = f; } else { missing++; }
    }

    // отпечаток содержимого: имена + байты, в стабильном порядке
    final names = files.keys.toList()..sort();
    final buf = <int>[];
    for (final n in names) {
      buf.addAll(utf8.encode(n));
      buf.addAll(files[n]!.readAsBytesSync());
    }
    final hash = sha256.convert(buf).toString().substring(0, 16);

    final zipPath = p.join(outDir.path, '$id.zip');
    final enc = ZipFileEncoder()..create(zipPath);
    for (final n in names) {
      enc.addArchiveFile(ArchiveFile(n, files[n]!.lengthSync(), files[n]!.readAsBytesSync()));
    }
    enc.close();

    final zip = File(zipPath);
    final bytes = zip.lengthSync();
    entry['bundle'] = {
      'url': 'bundles/$id.zip',
      'bytes': bytes,
      'sha256': sha256.convert(zip.readAsBytesSync()).toString(),
      'contentHash': hash,
      'files': names.length,
    };
    packed++;
    stdout.writeln('$id  ${names.length} файлов  ${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ  отпечаток $hash'
        '${missing > 0 ? '  (нет $missing кадров)' : ''}');
  }

  catalogFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(catalog));
  stdout.writeln('\nбандлов: $packed → ${outDir.path}');
}

String _repoRoot() {
  var d = Directory.current;
  while (!File(p.join(d.path, 'CLAUDE.md')).existsSync() || !Directory(p.join(d.path, 'content')).existsSync()) {
    if (d.parent.path == d.path) throw StateError('Не найден корень репозитория');
    d = d.parent;
  }
  return d.path;
}
