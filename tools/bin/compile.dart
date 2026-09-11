// content/ → build/. Единственный мост между зоной контента и приложением.
// Правила валидации — docs/CONTENT_FORMAT.md. Меняя их здесь, меняй и там.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final errors = <String>[];
final warnings = <String>[];
var enMissing = 0;
void err(String m) => errors.add(m);
void warn(String m) => warnings.add(m);

void main(List<String> args) {
  final check = args.contains('--check');
  final strict = args.contains('--strict');
  final root = _repoRoot();
  final content = p.join(root, 'content');
  final out = p.join(root, 'build');

  // ---- источники и факты
  final sources = <String>{
    for (final s in _yaml(p.join(content, 'sources/registry.yaml')) as List) s['id'] as String,
  };
  final facts = <String, Map>{};
  final factTopic = <String, String>{};
  void walk(Map node) {
    for (final f in (node['must_know'] as List? ?? [])) {
      facts[f['id']] = f;
      factTopic[f['id']] = node['id'];
      if (!sources.contains(f['source'])) err('fact ${f['id']}: неизвестный источник ${f['source']}');
    }
    for (final c in (node['children'] as List? ?? [])) walk(c);
  }
  final curriculum = (_yaml(p.join(content, 'curriculum/ent_history.yaml')) as List).cast<Map>();
  for (final n in curriculum) walk(n);

  // ---- серии
  final episodesDir = Directory(p.join(content, 'episodes'));
  final episodeFiles = episodesDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var compiled = 0;
  final catalog = <Map<String, Object?>>[];
  for (final file in episodeFiles) {
    final ep = _yaml(file.path) as Map;
    final id = ep['episode'] as String;
    final season = p.basename(p.dirname(file.path));
    final qFile = File(p.join(content, 'questions', season, '${id.substring(2)}.yaml')); // s1e01 → e01.yaml
    if (!qFile.existsSync()) { err('$id: нет файла вопросов ${qFile.path}'); continue; }
    final questions = (_yaml(qFile.path) as List).cast<Map>();
    final media = <String>{
      for (final m in _yaml(p.join(content, 'media', season, 'manifest.yaml')) as List) m['id'] as String,
    };

    final report = _validateEpisode(ep, questions, facts, sources, media, strict);
    if (check) { _print(id, report); continue; }
    if (errors.isEmpty) {
      _write(out, id, ep, questions, factTopic, report);
      compiled++;
      catalog.add({
        'id': id, 'number': _numberOf(id), 'season': season,
        'title': ep['title'], 'topics': ep['topics'], 'era': ep['era'], 'version': 1,
        'scenes': report['scenes'], 'questions': report['questions'],
        'approved': ep['approved_by'] != null, 'planned': false,
      });
    }
    _print(id, report);
  }

  stdout.writeln('');
  if (enMissing > 0) stdout.writeln('  △ без перевода en: $enMissing строк (пока допустимо)');
  for (final w in warnings) stdout.writeln('  △ $w');
  for (final e in errors) stdout.writeln('  ✗ $e');
  if (errors.isNotEmpty) { stdout.writeln('\n${errors.length} ошибок. Ничего не записано.'); exit(1); }
  if (strict && warnings.isNotEmpty) { stdout.writeln('\n--strict: ${warnings.length} предупреждений считаются ошибками.'); exit(1); }
  if (!check) {
    // Объявленный план: серии из planned_series, для которых ещё нет YAML.
    final written = {for (final c in catalog) c['id']};
    for (final node in curriculum) {
      for (final ps in (node['planned_series'] as List? ?? []).cast<Map>()) {
        final pid = ps['id'] as String;
        if (written.contains(pid)) continue;
        catalog.add({
          'id': pid, 'number': ps['number'] ?? _numberOf(pid), 'season': 's${_seasonOf(pid)}',
          'title': ps['title'], 'topics': [node['id']], 'era': ps['era'], 'version': 0,
          'scenes': 0, 'questions': 0, 'approved': false, 'planned': true,
        });
      }
    }
    catalog.sort((a, b) => ((a['number'] ?? 0) as int).compareTo((b['number'] ?? 0) as int));
    const enc = JsonEncoder.withIndent('  ');
    Directory(out).createSync(recursive: true);
    final copied = _copyMedia(content, out);
    if (copied > 0) stdout.writeln('медиа: скопировано $copied файлов → $out/media/');
    File(p.join(out, 'catalog.json')).writeAsStringSync(enc.convert(catalog));
    File(p.join(out, 'common.json')).writeAsStringSync(enc.convert(_common(content, out)));
    File(p.join(out, 'curriculum.json')).writeAsStringSync(enc.convert(_flatCurriculum(curriculum)));
  }
  stdout.writeln(check ? '\nПроверка пройдена.' : '\nСобрано серий: $compiled → $out');
  if (!check && Directory(p.join(out, 'bundles')).existsSync()) {
    stdout.writeln('catalog.json пересобран без бандлов — теперь: dart run bin/pack.dart');
  }
}

// ---------------------------------------------------------------- валидация
Map<String, Object?> _validateEpisode(Map ep, List<Map> questions, Map<String, Map> facts,
    Set<String> sources, Set<String> media, bool strict) {
  final id = ep['episode'] as String;
  final scenes = (ep['scenes'] as List).cast<Map>();
  final sceneIds = {for (final s in scenes) s['id'] as String};
  final chars = {for (final c in (ep['characters'] as List)) c['id'] as String};
  final qById = {for (final q in questions) q['id'] as String: q};
  final reachable = <String>{scenes.first['id']};
  final usedQ = <String>{};
  final covered = <String>{};
  var beats = 0, choices = 0;

  for (final s in scenes) {
    final sid = s['id'] as String;
    final layer = s['layer'] as String?;
    if (layer != null && !{'history', 'personal'}.contains(layer)) {
      err('$id/$sid: layer должен быть history|personal');
    }
    if (layer == 'personal') {
      if ((s['covers'] as List? ?? []).isNotEmpty) err('$id/$sid: personal-сцена не несёт covers');
      if ((s['quiz'] as List? ?? []).isNotEmpty) err('$id/$sid: personal-сцена не несёт quiz');
    }
    if (layer == 'history' && (s['covers'] as List? ?? []).isEmpty) {
      err('$id/$sid: history-сцена обязана нести хотя бы один факт в covers');
    }
    final pan = s['pan'];
    if (pan != null && (pan is! int || pan < 0 || pan > 100)) err('$id/$sid: pan 0..100');
    final side = s['avatar'];
    if (side != null && !{'left', 'right'}.contains(side)) err('$id/$sid: avatar left|right');
    for (final f in (s['covers'] as List? ?? [])) {
      if (!facts.containsKey(f)) err('$id/$sid: covers неизвестный факт $f');
    }
    covered.addAll((s['covers'] as List? ?? []).cast<String>());
    if (!media.contains(s['art'])) err('$id/$sid: art ${s['art']} нет в media/manifest.yaml');

    for (final b in (s['beats'] as List).cast<Map>()) {
      beats++;
      if (b.containsKey('say')) {
        final say = b['say'] as Map;
        if (!chars.contains(say['who'])) err('$id/$sid: неизвестный персонаж ${say['who']}');
        final emo = say['emo'] as String?;
        if (emo != null && !_emotions.contains(emo)) err('$id/$sid: emo должен быть одним из ${_emotions.join('|')}');
        _needLangs(say, '$id/$sid say');
      } else if (b.containsKey('choice')) {
        choices++;
        final ch = b['choice'] as Map;
        _needLangs(ch['prompt'] as Map, '$id/$sid choice.prompt');
        for (final o in (ch['options'] as List).cast<Map>()) {
          _needLangs(o, '$id/$sid option ${o['id']}');
          if (o['art'] != null && !media.contains(o['art'])) {
            err('$id/$sid option ${o['id']}: art ${o['art']} нет в media/manifest.yaml');
          }
          final g = o['goto'] as String?;
          if (g == null) { err('$id/$sid option ${o['id']}: нет goto'); continue; }
          if (g != 'end' && !sceneIds.contains(g)) err('$id/$sid: goto $g не существует');
          reachable.add(g);
        }
      } else {
        err('$id/$sid: beat не say и не choice');
      }
    }
    // вопросы этой сцены: факт должен прозвучать здесь или раньше
    for (final qid in (s['quiz'] as List? ?? []).cast<String>()) {
      final q = qById[qid];
      if (q == null) { err('$id/$sid: quiz ссылается на несуществующий $qid'); continue; }
      usedQ.add(qid);
      if (!covered.contains(q['fact'])) err('$qid: факт ${q['fact']} не прозвучал в $sid или раньше');
      if (q['format'] == 'context' && q['context'] != sid) warn('$qid: context=${q['context']}, но задаётся после $sid');
    }
  }
  // последовательный переход между сценами без choice допустим — сцена без choice ведёт к следующей
  for (var i = 0; i < scenes.length - 1; i++) {
    final hasChoice = (scenes[i]['beats'] as List).any((b) => (b as Map).containsKey('choice'));
    if (!hasChoice) reachable.add(scenes[i + 1]['id']);
  }
  for (final sid in sceneIds) if (!reachable.contains(sid)) err('$id: сцена $sid недостижима');

  // вопросы
  final perFact = <String, int>{};
  for (final q in questions) {
    final qid = q['id'] as String;
    if (!usedQ.contains(qid)) warn('$qid не используется ни одной сценой');
    if (!facts.containsKey(q['fact'])) err('$qid: неизвестный факт ${q['fact']}');
    perFact[q['fact']] = (perFact[q['fact']] ?? 0) + 1;
    if (!{'single', 'context'}.contains(q['format'])) err('$qid: format должен быть single|context');
    if (q['format'] == 'context' && q['context'] == null) err('$qid: format context требует поле context');
    final opts = (q['options'] as List).cast<Map>();
    if (opts.length != 4) err('$qid: вариантов ${opts.length}, нужно 4');
    if (opts.where((o) => o['correct'] == true).length != 1) err('$qid: должен быть ровно один correct');
    if (!sources.contains((q['source'] as String).split('#').first)) err('$qid: неизвестный источник ${q['source']}');
    if ((q['distractor_note'] as String?)?.isEmpty ?? true) err('$qid: нет distractor_note');
    _needLangs(q['stem'] as Map, '$qid stem');
    _needLangs(q['explain'] as Map, '$qid explain');
    for (final o in opts) _needLangs(o, '$qid option ${o['id']}');
    final d = q['difficulty'];
    if (d is! int || d < 1 || d > 3) err('$qid: difficulty 1..3');
  }
  for (final f in covered) {
    final n = perFact[f] ?? 0;
    if (n == 0) warn('факт $f прозвучал, но не проверяется ни одним вопросом');
    else if (n < 3) warn('факт $f: $n вопрос(а), цель — 3 разной формулировки');
  }
  return {
    'scenes': scenes.length, 'beats': beats, 'choices': choices,
    'questions': questions.length,
    'single': questions.where((q) => q['format'] == 'single').length,
    'context': questions.where((q) => q['format'] == 'context').length,
    'facts_covered': covered.length,
    'approved_by': ep['approved_by'],
  };
}

void _needLangs(Map m, String where) {
  for (final l in const ['kk', 'ru']) {
    if ((m[l] as String?)?.trim().isEmpty ?? true) err('$where: нет $l');
  }
  if ((m['en'] as String?)?.trim().isEmpty ?? true) enMissing++;
}

// ---------------------------------------------------------------- вывод
void _write(String out, String id, Map ep, List<Map> questions, Map<String, String> factTopic, Map report) {
  final dir = Directory(p.join(out, id))..createSync(recursive: true);
  final enc = const JsonEncoder.withIndent('  ');

  Map<String, String> t(Map? m) => {
        for (final l in const ['kk', 'ru', 'en'])
          if (m?[l] != null) l: m![l] as String,
      };

  final episode = {
    'id': id,
    'version': 1,
    'title': t(ep['title']),
    'topics': ep['topics'],
    'era': ep['era'],
    'characters': {
      for (final c in (ep['characters'] as List).cast<Map>())
        c['id']: {
          'name': t(c['name']),
          'fiction': c['fiction'] == true,
          if (c['avatar'] == true) 'avatar': true,
          if (c['default_name'] != null) 'defaultName': t(c['default_name']),
        },
    },
    'scenes': [
      for (final s in (ep['scenes'] as List).cast<Map>())
        {
          'id': s['id'],
          'art': s['art'],
          if (s['title'] != null) 'title': t(s['title']),
          if (s['layer'] != null) 'layer': s['layer'],
          if (s['pan'] != null) 'pan': s['pan'],
          if (s['avatar'] != null) 'avatarSide': s['avatar'],
          'covers': s['covers'] ?? [],
          'beats': [
            for (final b in (s['beats'] as List).cast<Map>())
              if (b.containsKey('say'))
                {'type': 'say', 'who': b['say']['who'], 'text': t(b['say']), if (b['say']['emo'] != null) 'emo': b['say']['emo']}
              else
                {
                  'type': 'choice',
                  'prompt': t(b['choice']['prompt']),
                  'options': [
                    for (final o in (b['choice']['options'] as List).cast<Map>())
                      {'id': o['id'], 'text': t(o), 'set': o['set'] ?? {}, 'goto': o['goto'], if (o['art'] != null) 'art': o['art']},
                  ],
                },
          ],
          'quiz': s['quiz'] ?? [],
        },
    ],
    'finalTest': {'single': ep['final_test']?['single'] ?? 10, 'context': ep['final_test']?['context'] ?? 10},
  };

  final qs = [
    for (final q in questions)
      {
        'id': q['id'],
        'fact': q['fact'],
        'topic': factTopic[q['fact']],
        'format': q['format'],
        'context': q['context'],
        'difficulty': q['difficulty'],
        'stem': t(q['stem']),
        'options': [
          for (final o in (q['options'] as List).cast<Map>())
            {'id': o['id'], 'text': t(o), 'correct': o['correct'] == true},
        ],
        'explain': t(q['explain']),
        'source': q['source'],
      },
  ];

  final manifest = {
    'episode': id,
    'version': 1,
    'builtAt': DateTime.now().toUtc().toIso8601String(),
    'files': ['episode.json', 'questions.json'],
    'media': [
      for (final s in (ep['scenes'] as List).cast<Map>()) ...[
        s['art'],
        for (final b in (s['beats'] as List).cast<Map>())
          if (b['choice'] != null)
            for (final o in (b['choice']['options'] as List).cast<Map>())
              if (o['art'] != null) o['art'],
      ],
    ],
    'stats': report,
  };

  File(p.join(dir.path, 'episode.json')).writeAsStringSync(enc.convert(episode));
  File(p.join(dir.path, 'questions.json')).writeAsStringSync(enc.convert(qs));
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync(enc.convert(manifest));
}

void _print(String id, Map report) {
  stdout.writeln('$id  сцен ${report['scenes']}  битов ${report['beats']}  выборов ${report['choices']}  '
      'вопросов ${report['questions']} (${report['single']} single / ${report['context']} context)  '
      'фактов ${report['facts_covered']}  виза: ${report['approved_by'] ?? '—'}');
}

/// content/media/<season>/out/*.jpg → build/media/<season>/. Сырые PNG не копируются — только результат pack_media.sh.
int _copyMedia(String content, String out) {
  var n = 0;
  final mediaRoot = Directory(p.join(content, 'media'));
  if (!mediaRoot.existsSync()) return 0;
  for (final season in mediaRoot.listSync().whereType<Directory>()) {
    final src = Directory(p.join(season.path, 'out'));
    if (!src.existsSync()) continue;
    final dst = Directory(p.join(out, 'media', p.basename(season.path)))..createSync(recursive: true);
    for (final f in src.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.jpg') && !f.path.endsWith('.png')) continue;
      final rel = p.relative(f.path, from: src.path);
      File(p.join(dst.path, rel)).parent.createSync(recursive: true);
      f.copySync(p.join(dst.path, rel));
      n++;
    }
  }
  return n;
}

const _emotions = ['calm', 'joy', 'alarm', 'sorrow'];

/// Общий для всех серий контент: аватары игрока (три внешности × эмоции).
/// Собирается из media/<season>/manifest.yaml: kind avatar, status approved,
/// id вида avatar_NN_slug_emotion. В сборку попадают только те, для кого есть файлы в out/.
Map<String, Object?> _common(String content, String out) {
  final looks = <String, Map<String, Object?>>{};
  final mediaRoot = Directory(p.join(content, 'media'));
  if (mediaRoot.existsSync()) {
    for (final season in mediaRoot.listSync().whereType<Directory>()) {
      final mf = File(p.join(season.path, 'manifest.yaml'));
      if (!mf.existsSync()) continue;
      final sid = p.basename(season.path);
      for (final m in (_yaml(mf.path) as List).cast<Map>()) {
        if (m['kind'] != 'avatar' || m['status'] != 'approved') continue;
        final match = RegExp(r'^(avatar_(\d+)_[a-z]+)_([a-z]+)$').firstMatch(m['id'] as String);
        if (match == null) continue;
        final base = match.group(1)!, emo = match.group(3)!;
        if (!_emotions.contains(emo)) continue;
        final bust = File(p.join(out, 'media', sid, 'avatars', '${base}_${emo}_bust.png'));
        final face = File(p.join(out, 'media', sid, 'avatars', '${base}_$emo.jpg'));
        if (!bust.existsSync() || !face.existsSync()) { warn('аватар ${m['id']}: нет файлов в out/avatars — пропущен'); continue; }
        final look = looks.putIfAbsent(base, () {
          // где лицо: из manifest (face_y) или по альфе эталонного кадра calm
          final calm = File(p.join(out, 'media', sid, 'avatars', '${base}_calm_bust.png'));
          final probe = _faceProbe(calm.existsSync() ? calm : bust);
          final manual = (m['face_y'] as num?)?.toDouble();
          return {
            'look': int.parse(match.group(2)!), 'id': base, 'season': sid, 'emotions': <String>[],
            'aspect': probe?.aspect ?? 0.78,
            'faceY': manual ?? probe?.faceY ?? 0.33,
          };
        });
        if (m['face_y'] != null) look['faceY'] = (m['face_y'] as num).toDouble();
        (look['emotions'] as List<String>).add(emo);
      }
    }
  }
  final list = looks.values.toList()..sort((a, b) => (a['look'] as int).compareTo(b['look'] as int));
  for (final l in list) { (l['emotions'] as List<String>).sort((a, b) => _emotions.indexOf(a).compareTo(_emotions.indexOf(b))); }
  return {'version': 1, 'avatars': list};
}

/// Оценка положения лица по альфе PNG: верх непрозрачной области — верх головного убора,
/// первая строка шире 60% максимума — плечи. Глаза обычно на 0.6 пути от верха к плечам.
({double faceY, double aspect})? _faceProbe(File png) {
  try {
    final data = png.readAsBytesSync();
    if (data.length < 8 || data[0] != 0x89 || data[1] != 0x50) return null;
    var pos = 8; int? w, h, ct; final idat = BytesBuilder();
    while (pos + 8 <= data.length) {
      final len = ByteData.sublistView(data, pos, pos + 4).getUint32(0);
      final type = String.fromCharCodes(data.sublist(pos + 4, pos + 8));
      final body = data.sublist(pos + 8, pos + 8 + len);
      pos += 12 + len;
      if (type == 'IHDR') { final bd = ByteData.sublistView(body); w = bd.getUint32(0); h = bd.getUint32(4); ct = body[9]; }
      else if (type == 'IDAT') { idat.add(body); }
      else if (type == 'IEND') { break; }
    }
    if (w == null || h == null || ct != 6) return null;
    final raw = ZLibDecoder().convert(idat.toBytes());
    const bpp = 4; final stride = w * bpp;
    var prev = List<int>.filled(stride, 0); var i = 0;
    final widths = <int>[];
    for (var y = 0; y < h; y++) {
      final f = raw[i++]; final line = raw.sublist(i, i + stride); i += stride;
      for (var x = 0; x < stride; x++) {
        final a = x >= bpp ? line[x - bpp] : 0, b = prev[x], c = x >= bpp ? prev[x - bpp] : 0;
        line[x] = (line[x] + switch (f) {
          1 => a, 2 => b, 3 => (a + b) ~/ 2,
          4 => () { final pp = a + b - c; final pa = (pp - a).abs(), pb = (pp - b).abs(), pc = (pp - c).abs(); return pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }(),
          _ => 0,
        }) & 255;
      }
      var n = 0;
      for (var x = 3; x < stride; x += bpp) { if (line[x] > 40) n++; }
      widths.add(n);
      prev = line;
    }
    final top = widths.indexWhere((n) => n > 0);
    if (top < 0) return null;
    final mx = widths.reduce((a, b) => a > b ? a : b);
    var shoulders = widths.indexWhere((n) => n > mx * 0.6);
    if (shoulders <= top) shoulders = (top + h) ~/ 2;
    return (faceY: (top + 0.6 * (shoulders - top)) / h, aspect: w / h);
  } catch (_) {
    return null;
  }
}

int _numberOf(String id) => int.tryParse(RegExp(r'e(\d+)').firstMatch(id)?.group(1) ?? '') ?? 0;
int _seasonOf(String id) => int.tryParse(RegExp(r'^s(\d+)').firstMatch(id)?.group(1) ?? '') ?? 1;

/// Плоский список узлов программы: периоды (без родителя) и темы с фактами.
/// Клиент строит из него экран «Жол» и «Дайындық», не разбирая YAML.
List<Map<String, Object?>> _flatCurriculum(List<Map> roots) {
  final out = <Map<String, Object?>>[];
  void walk(Map n, String? parent) {
    final facts = (n['must_know'] as List? ?? []).cast<Map>();
    out.add({
      'id': n['id'], 'parent': parent, 'title': n['title'], 'status': n['status'],
      if (n['era'] != null) 'era': n['era'],
      'facts': [for (final f in facts) {'id': f['id'], 'kk': f['kk'], 'ru': f['ru']}],
    });
    for (final c in (n['children'] as List? ?? []).cast<Map>()) walk(c, n['id'] as String);
  }
  for (final r in roots) walk(r, null);
  return out;
}

// ---------------------------------------------------------------- utils
dynamic _yaml(String path) => _plain(loadYaml(File(path).readAsStringSync()));
dynamic _plain(dynamic n) {
  if (n is YamlMap) return {for (final e in n.entries) e.key.toString(): _plain(e.value)};
  if (n is YamlList) return [for (final e in n) _plain(e)];
  return n;
}
String _repoRoot() {
  var d = Directory.current;
  while (!File(p.join(d.path, 'CLAUDE.md')).existsSync() || !Directory(p.join(d.path, 'content')).existsSync()) {
    if (d.parent.path == d.path) throw StateError('Не найден корень репозитория (CLAUDE.md + content/)');
    d = d.parent;
  }
  return d.path;
}
