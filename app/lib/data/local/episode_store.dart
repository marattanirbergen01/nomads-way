import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/curriculum.dart';

enum InstallState {
  /// Серия ещё не скачана.
  absent,
  /// Скачана и совпадает с тем, что на сервере.
  ready,
  /// Скачана, но на сервере другой отпечаток — сценарий или кадры изменились.
  outdated,
  /// Установка невозможна (браузер) — играем потоком.
  unsupported,
}

/// Скачанные серии на диске: `<документы приложения>/episodes/<id>/`.
///
/// Серия качается одним zip, проверяется по sha256 и распаковывается. После этого
/// игра идёт без сети. Рядом лежит `.installed` с отпечатком содержимого — по нему
/// видно, что серия на сервере изменилась, и её нужно обновить.
class EpisodeStore {
  EpisodeStore({http.Client? client, Future<Directory> Function()? baseDir})
      : _client = client ?? http.Client(),
        _baseDir = baseDir ?? getApplicationDocumentsDirectory;
  final http.Client _client;
  /// Откуда брать корень для хранения. Подменяется в тестах на временную папку.
  final Future<Directory> Function() _baseDir;
  Directory? _root;

  /// Файловой системы может не быть: браузер, тестовое окружение без плагина.
  /// Тогда всё работает потоком, как раньше.
  bool get supported => !kIsWeb && _available != false;
  bool? _available;

  Future<Directory?> _dir() async {
    if (kIsWeb || _available == false) return null;
    if (_root != null) return _root;
    try {
      // Плагин может не ответить вовсе (тестовое окружение, урезанная сборка) —
      // тогда считаем файловую систему недоступной и играем потоком.
      final base = await _baseDir().timeout(const Duration(seconds: 4));
      final d = Directory(p.join(base.path, 'episodes'));
      d.createSync(recursive: true);
      _available = true;
      return _root = d;
    } catch (_) {
      _available = false;
      return null;
    }
  }

  Future<Directory?> _epDir(String id) async {
    final root = await _dir();
    return root == null ? null : Directory(p.join(root.path, id));
  }

  Future<File?> _stamp(String id) async {
    final d = await _epDir(id);
    return d == null ? null : File(p.join(d.path, '.installed'));
  }

  /// Отпечаток установленной копии, или null.
  Future<String?> installedHash(String id) async {
    final f = await _stamp(id);
    if (f == null || !f.existsSync()) return null;
    try {
      return (jsonDecode(f.readAsStringSync()) as Map)['contentHash'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<InstallState> state(CatalogEntry e) async {
    if (e.bundle == null) return InstallState.unsupported;
    final have = await installedHash(e.id);
    if (!supported) return InstallState.unsupported;
    if (have == null) return InstallState.absent;
    return have == e.bundle!.contentHash ? InstallState.ready : InstallState.outdated;
  }

  /// Файл из установленной серии, или null.
  Future<File?> file(String id, String name) async {
    final d = await _epDir(id);
    if (d == null) return null;
    final f = File(p.join(d.path, name));
    return f.existsSync() ? f : null;
  }

  /// Синхронная версия для виджетов: пути кэшируются после [warm].
  final _known = <String, Directory>{};
  Future<void> warm(String id) async {
    final d = await _epDir(id);
    if (d != null && d.existsSync()) _known[id] = d;
  }
  File? fileSync(String id, String name) {
    final d = _known[id];
    if (d == null) return null;
    final f = File(p.join(d.path, name));
    return f.existsSync() ? f : null;
  }

  /// Скачивает и распаковывает серию. [onProgress] — 0..1, приходит по мере загрузки.
  Future<void> install(CatalogEntry e, String baseUrl, {void Function(double)? onProgress}) async {
    final b = e.bundle;
    if (!supported || b == null) throw StateError('установка недоступна');

    final req = http.Request('GET', Uri.parse('$baseUrl/${b.url}'));
    final res = await _client.send(req);
    if (res.statusCode != 200) throw Exception('GET ${b.url} → ${res.statusCode}');
    final total = res.contentLength ?? b.bytes;

    final bytes = <int>[];
    await for (final chunk in res.stream) {
      bytes.addAll(chunk);
      if (total > 0) onProgress?.call((bytes.length / total).clamp(0, 1));
    }

    final got = sha256.convert(bytes).toString();
    if (got != b.sha256) throw Exception('битый архив: отпечаток не совпал');

    // распаковываем в свежую папку, чтобы старые кадры не остались
    final dir = await _epDir(e.id);
    if (dir == null) throw StateError('нет доступа к файловой системе');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    for (final f in ZipDecoder().decodeBytes(bytes)) {
      if (!f.isFile) continue;
      final out = File(p.join(dir.path, f.name))..createSync(recursive: true);
      out.writeAsBytesSync(f.content as List<int>);
    }
    (await _stamp(e.id))!.writeAsStringSync(jsonEncode({
      'contentHash': b.contentHash, 'sha256': b.sha256, 'bytes': b.bytes,
      'at': DateTime.now().toIso8601String(),
    }));
    _known[e.id] = dir;
    onProgress?.call(1);
  }

  Future<void> remove(String id) async {
    final d = await _epDir(id);
    if (d != null && d.existsSync()) d.deleteSync(recursive: true);
    _known.remove(id);
  }

  /// Что уже скачано: id → байты на диске.
  Future<Map<String, int>> installed() async {
    final root = await _dir();
    if (root == null) return {};
    final out = <String, int>{};
    for (final d in root.listSync().whereType<Directory>()) {
      var n = 0;
      for (final f in d.listSync(recursive: true).whereType<File>()) { n += f.lengthSync(); }
      out[p.basename(d.path)] = n;
    }
    return out;
  }
}
