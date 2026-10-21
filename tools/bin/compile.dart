// content/ → build/. Единственный мост между зоной контента и приложением.
// Правила валидации — docs/CONTENT_FORMAT.md. Меняя их здесь, меняй и там.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final errors = <String>[];
final warnings = <String>[];
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
  final seriesQids = <String>{};
  // переменные сюжета, которые ставят уже прочитанные серии сезона: игрок приносит их с собой
  final seasonVars = <String, Set<String>>{};
  // живой кадр: content/fx/<season>.yaml — камера, частицы, ударные реплики (отдельно от серий, их пишет студия)
  final fxBySeason = <String, Map>{};
  final fxUsed = <String>{};
  // банк школы грузится до серий: его вопросы встают в quiz сцен по раскладке (см. _bankQuiz)
  final bank = _loadBank(content, sources, const {});
  final bankMaps = <String, Map>{};
  // подписи переменных сюжета для плашек после выбора: content/vars/<season>.yaml
  final varsBySeason = <String, Map>{};

  for (final file in episodeFiles) {
    final ep = _yaml(file.path) as Map;
    final id = ep['episode'] as String;
    final season = p.basename(p.dirname(file.path));
    final qFile = File(p.join(content, 'questions', season, '${id.substring(2)}.yaml')); // s1e01 → e01.yaml
    if (!qFile.existsSync()) { err('$id: нет файла вопросов ${qFile.path}'); continue; }
    final questions = (_yaml(qFile.path) as List).cast<Map>();
    seriesQids.addAll(questions.map((q) => q['id'] as String));
    final mediaList = (_yaml(p.join(content, 'media', season, 'manifest.yaml')) as List).cast<Map>();
    final media = <String>{for (final m in mediaList) m['id'] as String};
    final portraits = <String>{for (final m in mediaList) if (m['kind'] == 'character' && m['status'] == 'approved') m['id'] as String};

    final inherited = seasonVars.putIfAbsent(season, () => <String>{});
    final report = _validateEpisode(ep, questions, facts, sources, media, strict, inherited: inherited);
    inherited.addAll((report['sets'] as Set<String>?) ?? const {});
    report.remove('sets');
    final seasonFx = fxBySeason.putIfAbsent(season, () {
      final f = File(p.join(content, 'fx', '$season.yaml'));
      return f.existsSync() ? (_yaml(f.path) as Map? ?? {}) : {};
    });
    if (seasonFx.containsKey(id)) fxUsed.add(id);
    final fx = _sceneFx(id, ep, seasonFx[id]);
    final seasonVarsLabels = varsBySeason.putIfAbsent(season, () => _loadVarLabels(content, season));
    final seasonBankMap = bankMaps.putIfAbsent(season, () {
      final f = File(p.join(content, _bankMapPath(season)));
      return f.existsSync() ? (_yaml(f.path) as Map? ?? {}) : {};
    });
    final bankQuiz = _bankQuiz(id, ep, seasonBankMap[id], bank, {for (final q in questions) q['id'] as String});
    final bankN = bankQuiz.values.fold<int>(0, (n, l) => n + l.length);
    report['questions'] = (report['questions'] as int) + bankN;
    report['single'] = (report['single'] as int) + bankN;
    report['bank'] = bankN;
    if (check) { _print(id, report); continue; }
    if (errors.isEmpty) {
      final outMedia = p.join(content, 'media', season, 'out');
      _write(out, id, ep, questions, factTopic, report, portraitMedia: portraits, mediaExt: _mediaExt(outMedia),
          motion: _motion(outMedia, _artsOf(ep)), fx: fx, bankQuiz: bankQuiz, varLabels: seasonVarsLabels);
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

  for (final e in fxBySeason.entries) {
    for (final id in e.value.keys) {
      if (!fxUsed.contains(id)) warn('fx/${e.key}.yaml: серии $id нет — запись не используется');
    }
  }

  // ---- банк пробника ЕНТ: вне сюжета, правила серий к нему не применяются
  if (bank != null) {
    for (final q in bank.questions) {
      if (seriesQids.contains(q['id'])) err('bank ${q['id']}: id совпадает с вопросом серии');
    }
    for (final c in bank.contexts) {
      if (seriesQids.contains(c['id'])) err('bank ${c['id']}: id совпадает с вопросом серии');
    }
    _printBank(bank);
  }

  stdout.writeln('');
  for (final w in warnings) stdout.writeln('  △ $w');
  for (final e in errors) stdout.writeln('  ✗ $e');
  if (errors.isNotEmpty) { stdout.writeln('\n${errors.length} ошибок. Ничего не записано.'); exit(1); }
  if (strict && warnings.isNotEmpty) { stdout.writeln('\n--strict: ${warnings.length} предупреждений считаются ошибками.'); exit(1); }
  if (!check) {
    // Описания бандлов из прошлого catalog.json сохраняем: pack.dart пересчитает их сам,
    // а без этого свежая пересборка «теряла» бандлы и клиент считал, что серия не скачиваема.
    final prevCatalog = File(p.join(out, 'catalog.json'));
    if (prevCatalog.existsSync()) {
      try {
        final prev = {for (final e in (jsonDecode(prevCatalog.readAsStringSync()) as List).cast<Map>()) e['id']: e};
        for (final c in catalog) {
          final b = prev[c['id']]?['bundle'];
          if (b != null) c['bundle'] = b;
        }
      } catch (_) {}
    }
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
    final commonFile = File(p.join(out, 'common.json'));
    final common = _common(content, out);
    if (commonFile.existsSync()) {
      try {
        final prev = jsonDecode(commonFile.readAsStringSync()) as Map;
        if (prev['bundle'] != null) common['bundle'] = prev['bundle'];
        final prevBank = (prev['bank'] as Map?)?['bundle'];
        if (prevBank != null) (bank?.summary)?['bundle'] = prevBank;
      } catch (_) {}
    }
    if (bank != null) {
      _writeBank(content, out, bank);
      common['bank'] = bank.summary;
    }
    commonFile.writeAsStringSync(enc.convert(common));
    File(p.join(out, 'curriculum.json')).writeAsStringSync(enc.convert(_flatCurriculum(curriculum)));
  }
  stdout.writeln(check ? '\nПроверка пройдена.' : '\nСобрано серий: $compiled → $out');
  if (!check && Directory(p.join(out, 'bundles')).existsSync()) {
    stdout.writeln('описания бандлов перенесены из прошлого каталога; после правок контента: dart run bin/pack.dart');
  }
}

// ---------------------------------------------------------------- валидация
/// [inherited] — переменные, которые ставят более ранние серии того же сезона (переносятся к игроку).
Map<String, Object?> _validateEpisode(Map ep, List<Map> questions, Map<String, Map> facts,
    Set<String> sources, Set<String> media, bool strict, {Set<String> inherited = const {}}) {
  final id = ep['episode'] as String;
  final scenes = (ep['scenes'] as List).cast<Map>();
  final sceneIds = {for (final s in scenes) s['id'] as String};
  final chars = {for (final c in (ep['characters'] as List)) c['id'] as String};
  final qById = {for (final q in questions) q['id'] as String: q};
  final reachable = <String>{scenes.first['id']};
  final usedQ = <String>{};
  final ownVars = <String>{
    for (final s in scenes)
      for (final b in (s['beats'] as List).cast<Map>())
        if (b['choice'] != null)
          for (final o in (b['choice']['options'] as List).cast<Map>())
            ...((o['set'] as Map?)?.keys.cast<String>() ?? const <String>[]),
  };
  final knownVars = {...ownVars, ...inherited};
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
    for (final r in (s['art_when'] as List? ?? []).cast<Map>()) {
      if (!media.contains(r['art'])) err('$id/$sid art_when: art ${r['art']} нет в media/manifest.yaml');
      final cond = _parseCond(r['if']?.toString() ?? '');
      if (cond == null) err('$id/$sid art_when: не разобрал условие «${r['if']}» — формат: flag, !flag, var >= 2, a && b');
      else for (final c in cond) { if (!knownVars.contains(c['var'])) warn('$id/$sid art_when: переменную ${c['var']} никто не устанавливает'); }
    }
    for (final f in (s['covers'] as List? ?? [])) {
      if (!facts.containsKey(f)) err('$id/$sid: covers неизвестный факт $f');
    }
    covered.addAll((s['covers'] as List? ?? []).cast<String>());
    if (!media.contains(s['art'])) err('$id/$sid: art ${s['art']} нет в media/manifest.yaml');

    var hasCondSay = false;
    for (final b in (s['beats'] as List).cast<Map>()) {
      beats++;
      if (b.containsKey('say')) {
        final say = b['say'] as Map;
        if (!chars.contains(say['who'])) err('$id/$sid: неизвестный персонаж ${say['who']}');
        final emo = (say['emotion'] ?? say['emo']) as String?;
        if (emo != null && !_emotions.contains(emo)) err('$id/$sid: emotion должен быть одним из ${_emotions.join('|')}');
        if (say['when'] != null) {
          final cond = _parseCond(say['when'].toString());
          if (cond == null) err('$id/$sid say when: не разобрал условие «${say['when']}»');
          else for (final c in cond) { if (!knownVars.contains(c['var'])) warn('$id/$sid say when: переменную ${c['var']} никто не устанавливает'); }
          hasCondSay = true;
        }
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
          if (o['reply'] != null) {
            final r = o['reply'];
            if (r is! Map) { err('$id/$sid option ${o['id']}: reply должен быть {kk, ru, emotion?}'); }
            else {
              _needLangs(r, '$id/$sid option ${o['id']} reply');
              final re = r['emotion'] as String?;
              if (re != null && !_emotions.contains(re)) err('$id/$sid option ${o['id']} reply: emotion ${re}');
            }
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
    if (hasCondSay && (s['covers'] as List? ?? []).isNotEmpty) {
      warn('$id/$sid: есть реплики с when — убедитесь, что факты из covers звучат в безусловных репликах');
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
    // Источников может быть несколько через «;»: «bank:school_tests_2026; tb06_ru#§30,с.126» —
    // вопрос из банка школы, подтверждён учебником. «bank:» — пометка, что ссылка на сборник тестов.
    for (final ref in (q['source'] as String).split(';')) {
      final id = ref.trim().replaceFirst(RegExp(r'^bank:'), '').split('#').first;
      if (!sources.contains(id)) err('$qid: неизвестный источник ${ref.trim()}');
    }
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
    'sets': ownVars,
  };
}

void _needLangs(Map m, String where) {
  for (final l in const ['kk', 'ru']) {
    if ((m[l] as String?)?.trim().isEmpty ?? true) err('$where: нет $l');
  }
}

// ---------------------------------------------------------------- вывод
void _write(String out, String id, Map ep, List<Map> questions, Map<String, String> factTopic, Map report, {Set<String> portraitMedia = const {}, Map<String, String> mediaExt = const {}, Map<String, Map<String, String>> motion = const {}, Map<String, _Fx> fx = const {}, Map<String, List<Map<String, Object?>>> bankQuiz = const {}, Map varLabels = const {}}) {
  final dir = Directory(p.join(out, id))..createSync(recursive: true);
  final enc = const JsonEncoder.withIndent('  ');

  Map<String, String> t(Map? m) => {
        for (final l in const ['kk', 'ru', 'en'])
          if (m?[l] != null) l: m![l] as String,
      };

  final episode = {
    'id': id,
    'version': 1,
    if (mediaExt.isNotEmpty) 'mediaExt': mediaExt,
    // кадр → {язык: постер}: ролик media/<art>_<lang>.mp4, постер — его последний кадр
    if (motion.isNotEmpty) 'motion': motion,
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
          if (c['portrait'] != null) 'portrait': c['portrait']
          else if (portraitMedia.contains('char_${c['id']}')) 'portrait': 'char_${c['id']}',
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
          if (fx[s['id']]?.camera != null) 'camera': fx[s['id']]!.camera,
          if (fx[s['id']]?.layers.isNotEmpty ?? false) 'fx': fx[s['id']]!.layers,
          if (s['art_when'] != null)
            'artWhen': [
              for (final r in (s['art_when'] as List).cast<Map>())
                {'if': _parseCond(r['if'].toString()), 'art': r['art']},
            ],
          'covers': s['covers'] ?? [],
          'beats': [
            for (final (i, b) in (s['beats'] as List).cast<Map>().indexed)
              if (b.containsKey('say'))
                {
                  'type': 'say', 'who': b['say']['who'], 'text': t(b['say']),
                  if ((b['say']['emotion'] ?? b['say']['emo']) != null) 'emo': b['say']['emotion'] ?? b['say']['emo'],
                  if (b['say']['when'] != null) 'when': _parseCond(b['say']['when'].toString()),
                  if (fx[s['id']]?.impact.contains(i) ?? false) 'impact': true,
                }
              else
                {
                  'type': 'choice',
                  'prompt': t(b['choice']['prompt']),
                  'options': [
                    for (final o in (b['choice']['options'] as List).cast<Map>())
                      {
                        'id': o['id'], 'text': t(o), 'set': o['set'] ?? {}, 'goto': o['goto'],
                        if (o['art'] != null) 'art': o['art'],
                        if (_toasts(o['set'] as Map? ?? const {}, varLabels) case final ts when ts.isNotEmpty) 'toasts': ts,
                        if (o['reply'] is Map) 'reply': t(o['reply'] as Map),
                        if (o['reply'] is Map && (o['reply'] as Map)['emotion'] != null) 'replyEmo': (o['reply'] as Map)['emotion'],
                      },
                  ],
                },
          ],
          // вопросы банка школы сюжет не прерывают (решение Марата 2026-10-21): только итоговый тест
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
    for (final l in bankQuiz.values) ...l,
  ];

  final manifest = {
    'episode': id,
    'version': 1,
    'builtAt': DateTime.now().toUtc().toIso8601String(),
    'files': ['episode.json', 'questions.json'],
    'media': [
      for (final s in (ep['scenes'] as List).cast<Map>()) ...[
        s['art'],
        for (final r in (s['art_when'] as List? ?? []).cast<Map>()) r['art'],
        for (final b in (s['beats'] as List).cast<Map>())
          if (b['choice'] != null)
            for (final o in (b['choice']['options'] as List).cast<Map>())
              if (o['art'] != null) o['art'],
      ],
    ],
    // файлы роликов и постеров: pack.dart кладёт их в бандл как есть
    if (motion.isNotEmpty) 'motionFiles': [
      for (final e in motion.entries)
        for (final l in e.value.entries) ...['${e.key}_${l.key}.mp4', l.value],
    ],
    'stats': report,
  };

  File(p.join(dir.path, 'episode.json')).writeAsStringSync(enc.convert(episode));
  File(p.join(dir.path, 'questions.json')).writeAsStringSync(enc.convert(qs));
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync(enc.convert(manifest));
}

// ---------------------------------------------------------------- живой кадр
/// Эффекты одной сцены в том виде, в каком их читает клиент.
class _Fx {
  Map<String, Object>? camera;
  final layers = <Map<String, Object>>[];
  final impact = <int>{};
}

const _moves = ['still', 'breathe', 'push', 'pull', 'pan'];
const _layerTypes = ['dust', 'sand', 'fog', 'snow', 'embers', 'firelight'];

/// Проверяет запись серии из content/fx/<season>.yaml и приводит её к виду для episode.json.
/// Ударная реплика задаётся куском её текста (kk или ru) — так запись не съезжает, когда реплики добавляют.
Map<String, _Fx> _sceneFx(String id, Map ep, Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map) { err('fx/$id: ожидался словарь сцен'); return const {}; }
  final scenes = {for (final s in (ep['scenes'] as List).cast<Map>()) s['id'] as String: s};
  final res = <String, _Fx>{};
  for (final e in raw.entries) {
    final sid = e.key as String;
    final where = 'fx/$id/$sid';
    final scene = scenes[sid];
    if (scene == null) { err('$where: такой сцены в серии нет'); continue; }
    final spec = e.value;
    if (spec is! Map) { err('$where: ожидались camera / fx / impact'); continue; }
    for (final k in spec.keys) {
      if (!const ['camera', 'fx', 'impact'].contains(k)) err('$where: неизвестное поле $k');
    }
    final fx = res[sid] = _Fx();

    final cam = spec['camera'];
    if (cam != null) {
      final m = cam is String ? {'move': cam} : cam;
      if (m is! Map) {
        err('$where camera: строка или {move, …}');
      } else {
        final move = m['move'];
        if (!_moves.contains(move)) err('$where camera: move — одно из ${_moves.join('|')}');
        for (final k in m.keys) {
          if (!const ['move', 'zoom', 'from', 'to', 'dur', 'pan_y'].contains(k)) err('$where camera: неизвестное поле $k');
        }
        num? n(String k, num lo, num hi) {
          final v = m[k];
          if (v == null) return null;
          if (v is! num || v < lo || v > hi) { err('$where camera: $k — число $lo..$hi'); return null; }
          return v;
        }
        final zoom = n('zoom', 1, 1.5), from = n('from', 0, 100), to = n('to', 0, 100), dur = n('dur', 3, 60), panY = n('pan_y', 0, 100);
        fx.camera = {
          'move': '$move',
          if (zoom != null) 'zoom': zoom, if (from != null) 'from': from, if (to != null) 'to': to,
          if (dur != null) 'dur': dur, if (panY != null) 'panY': panY,
        };
      }
    }

    for (final l in (spec['fx'] as List? ?? const [])) {
      final m = l is String ? {'type': l} : l;
      if (m is! Map || !_layerTypes.contains(m['type'])) { err('$where fx: тип — одно из ${_layerTypes.join('|')}'); continue; }
      final out = <String, Object>{'type': m['type'] as String};
      const ranges = {'x': [0, 1], 'y': [0, 1], 'r': [0.05, 1.5], 'density': [0, 3], 'wind': [-3, 3]};
      for (final k in m.keys) {
        if (k == 'type') continue;
        final r = ranges[k];
        final v = m[k];
        if (r == null) { err('$where fx ${m['type']}: неизвестное поле $k'); continue; }
        if (v is! num || v < r[0] || v > r[1]) { err('$where fx ${m['type']}: $k — число ${r[0]}..${r[1]}'); continue; }
        out[k as String] = v;
      }
      if ((m['type'] == 'embers' || m['type'] == 'firelight') && (m['x'] == null || m['y'] == null)) {
        warn('$where fx ${m['type']}: без x, y огонь встанет в центр кадра');
      }
      fx.layers.add(out);
    }

    final beats = (scene['beats'] as List).cast<Map>();
    for (final q in (spec['impact'] as List? ?? const [])) {
      final hits = [
        for (final (i, b) in beats.indexed)
          if (b['say'] is Map && ['kk', 'ru'].any((l) => '${(b['say'] as Map)[l] ?? ''}'.contains('$q'))) i,
      ];
      if (hits.length != 1) {
        err('$where impact «$q»: ${hits.isEmpty ? 'нет реплики с таким текстом' : 'подходит ${hits.length} реплики — уточните'}');
      } else {
        fx.impact.add(hits.single);
      }
    }
  }
  return res;
}

void _print(String id, Map report) {
  stdout.writeln('$id  сцен ${report['scenes']}  битов ${report['beats']}  выборов ${report['choices']}  '
      'вопросов ${report['questions']} (${report['single']} single / ${report['context']} context${(report['bank'] ?? 0) > 0 ? ', из них банка школы ${report['bank']} — в итоговый тест' : ''})  '
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
      if (!f.path.endsWith('.jpg') && !f.path.endsWith('.png') && !f.path.endsWith('.mp4')) continue;
      final rel = p.relative(f.path, from: src.path);
      File(p.join(dst.path, rel)).parent.createSync(recursive: true);
      f.copySync(p.join(dst.path, rel));
      n++;
    }
  }
  return n;
}

const _emotions = ['calm', 'joy', 'alarm', 'sorrow', 'resolve'];

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

  // портреты исторических лиц: kind character, approved, файл в out/characters/
  final chars = <Map<String, Object?>>[];
  if (mediaRoot.existsSync()) {
    for (final season in mediaRoot.listSync().whereType<Directory>()) {
      final mf = File(p.join(season.path, 'manifest.yaml'));
      if (!mf.existsSync()) continue;
      final sid = p.basename(season.path);
      for (final m in (_yaml(mf.path) as List).cast<Map>()) {
        if (m['kind'] != 'character' || m['status'] != 'approved') continue;
        final f = File(p.join(out, 'media', sid, 'characters', '${m['id']}.jpg'));
        if (!f.existsSync()) { warn('портрет ${m['id']}: нет файла в out/characters — пропущен'); continue; }
        chars.add({'id': m['id'], 'season': sid});
      }
    }
  }
  return {'version': 1, 'avatars': list, 'characters': chars};
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

/// Условие для art_when: `flag` (> 0), `!flag` (== 0), `var >= 2`, части через `&&`.
/// Возвращает список {var, op, value} (все должны выполниться) или null при ошибке.
List<Map<String, Object>>? _parseCond(String src) {
  final out = <Map<String, Object>>[];
  for (final raw in src.split('&&')) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(!)?([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(t);
    if (m != null) { out.add({'var': m.group(2)!, 'op': m.group(1) == null ? '>' : '==', 'value': 0}); continue; }
    final c = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*(==|!=|<=|>=|<|>)\s*(-?\d+)$').firstMatch(t);
    if (c == null) return null;
    out.add({'var': c.group(1)!, 'op': c.group(2)!, 'value': int.parse(c.group(3)!)});
  }
  return out.isEmpty ? null : out;
}

int _numberOf(String id) => int.tryParse(RegExp(r'e(\d+)').firstMatch(id)?.group(1) ?? '') ?? 0;
int _seasonOf(String id) => int.tryParse(RegExp(r'^s(\d+)').firstMatch(id)?.group(1) ?? '') ?? 1;

/// Расширения медиа-файлов сезона, отличные от jpg: {id: 'png'}. Клиент по умолчанию ждёт jpg.
/// Все кадры серии: сцены, art_when, варианты выбора.
Iterable<String> _artsOf(Map ep) sync* {
  for (final s in (ep['scenes'] as List).cast<Map>()) {
    if (s['art'] != null) yield s['art'] as String;
    for (final r in (s['art_when'] as List? ?? []).cast<Map>()) yield r['art'] as String;
    for (final b in (s['beats'] as List).cast<Map>()) {
      if (b['choice'] == null) continue;
      for (final o in (b['choice']['options'] as List).cast<Map>()) { if (o['art'] != null) yield o['art'] as String; }
    }
  }
}

/// Анимированные кадры (карты): `<art>_<lang>.mp4` + постер-последний кадр `<art>_<lang>.jpg|png` в out/.
/// art → {язык: файл постера}. Ролик без постера — предупреждение, не подключается.
Map<String, Map<String, String>> _motion(String outDir, Iterable<String> arts) {
  final res = <String, Map<String, String>>{};
  for (final art in arts.toSet()) {
    for (final lang in const ['kk', 'ru']) {
      if (!File(p.join(outDir, '${art}_$lang.mp4')).existsSync()) continue;
      final poster = ['jpg', 'png'].map((e) => '${art}_$lang.$e').where((n) => File(p.join(outDir, n)).existsSync()).firstOrNull;
      if (poster == null) {
        warn('$art: есть ${art}_$lang.mp4, но нет постера ${art}_$lang.jpg|png — ролик не подключён');
        continue;
      }
      (res[art] ??= {})[lang] = poster;
    }
  }
  return res;
}

Map<String, String> _mediaExt(String outDir) {
  final dir = Directory(outDir);
  if (!dir.existsSync()) return const {};
  final res = <String, String>{};
  for (final f in dir.listSync().whereType<File>()) {
    final ext = p.extension(f.path).replaceFirst('.', '');
    // ролики (mp4) — не кадры: у них своя запись motion, а постер — png с тем же именем
    if (ext.isNotEmpty && ext != 'jpg' && ext != 'mp4') res[p.basenameWithoutExtension(f.path)] = ext;
  }
  return res;
}

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

// ---------------------------------------------------------------- плашки после выбора
/// content/vars/<season>.yaml: `traits` (черта, «+N название») и `flags` (с `toast` — «это запомнят» / предмет).
Map _loadVarLabels(String content, String season) {
  final f = File(p.join(content, 'vars', '$season.yaml'));
  if (!f.existsSync()) return const {};
  final y = _yaml(f.path) as Map? ?? {};
  void need(String where, Object? m) {
    if (m is! Map || (m['kk'] as String?)?.trim().isEmpty != false || (m['ru'] as String?)?.trim().isEmpty != false) {
      err('vars/$season.yaml $where: нужны kk и ru');
    }
  }
  for (final e in ((y['traits'] as Map?) ?? {}).entries) { need('traits.${e.key}', e.value); }
  for (final e in ((y['flags'] as Map?) ?? {}).entries) {
    final toast = (e.value as Map?)?['toast'];
    if (toast != null) need('flags.${e.key}.toast', toast);
  }
  return y;
}

/// Плашки варианта: сначала черты (в порядке set, «+N»), потом флаги с подписью; не больше трёх.
/// Переменная без подписи — молча без плашки.
List<Map<String, Object?>> _toasts(Map set, Map labels) {
  final traits = (labels['traits'] as Map?) ?? const {};
  final flags = (labels['flags'] as Map?) ?? const {};
  final res = <Map<String, Object?>>[];
  for (final e in set.entries) {
    final t = traits[e.key];
    if (t is Map && e.value is int && (e.value as int) > 0) {
      res.add({'kind': 'trait', 'n': e.value, 'text': {'kk': t['kk'], 'ru': t['ru']}, if (t['icon'] != null) 'icon': t['icon']});
    }
  }
  for (final e in set.entries) {
    final f = flags[e.key];
    final toast = f is Map ? f['toast'] : null;
    if (toast is Map) {
      res.add({'kind': f['icon'] == 'icon_flag_item' ? 'item' : 'memory', 'text': {'kk': toast['kk'], 'ru': toast['ru']},
          if (f['icon'] != null) 'icon': f['icon']});
    }
  }
  return res.take(3).toList();
}

// ---------------------------------------------------------------- вопросы банка в сериях
/// Раскладка вопросов банка школы по сценам — от окна «Контент». Лежит отдельно от серий:
/// «Сборка» студии перезаписывает content/episodes/, а студия про вопросы банка не знает.
String _bankMapPath(String season) => p.join('scripts', season, 'yaml', 'bank_map.yaml');

/// Сцена → вопросы банка в формате questions.json. В quiz сцены они не встают — только в набор
/// итогового теста серии (и оттуда в повторение); сцена в раскладке — где прозвучал ответ (проверяется). Правила серий (fact ↔ covers, explain) к ним
/// не применяются; check / image_missing и контекстные (без текста контекста не решаются) — пропуск.
Map<String, List<Map<String, Object?>>> _bankQuiz(String id, Map ep, Object? raw, _Bank? bank, Set<String> ownIds) {
  if (raw == null) return const {};
  final where = 'bank_map/$id';
  if (raw is! Map) { err('$where: ожидался словарь сцен'); return const {}; }
  if (bank == null) { err('$where: банк не собран, вопросы банка ставить некуда'); return const {}; }
  final byId = {for (final q in bank.questions) q['id']: q};
  final scenes = {for (final s in (ep['scenes'] as List).cast<Map>()) s['id'] as String: s};
  final seen = <String>{};
  final res = <String, List<Map<String, Object?>>>{};
  for (final e in raw.entries) {
    final sid = e.key as String;
    final scene = scenes[sid];
    if (scene == null) { err('$where: сцены $sid нет в серии'); continue; }
    if (scene['layer'] == 'personal') { err('$where/$sid: personal-сцена не несёт quiz'); continue; }
    for (final qid in (e.value as List? ?? const []).cast<String>()) {
      final q = byId[qid];
      if (q == null) { err('$where/$sid: вопроса $qid нет в банке'); continue; }
      if (ownIds.contains(qid) || !seen.add(qid)) { warn('$where/$sid: $qid уже стоит в серии — пропущен'); continue; }
      if (q['check'] == true || q['image_missing'] == true) { warn('$where/$sid: $qid помечен check/image_missing — пропущен'); continue; }
      if (q['format'] != 'single') { warn('$where/$sid: $qid контекстный (без текста не решается) — пропущен'); continue; }
      final opts = (q['options'] as List).cast<Map>();
      (res[sid] ??= []).add({
        'id': qid,
        'fact': q['topic'] == null ? '' : 'ent.${q['topic']}',
        'topic': q['topic'] == null ? null : 'ent.${q['topic']}',
        'format': 'single',
        'context': null,
        'difficulty': 2,
        'stem': q['stem'],
        'options': [
          for (var i = 0; i < opts.length; i++) {'id': '$qid.$i', 'text': opts[i], 'correct': i == q['answer']},
        ],
        'explain': <String, String>{},
        'source': 'school_tests_2026',
        if (q['shuffle'] == false) 'shuffle': false,
      });
    }
  }
  return res;
}

// ---------------------------------------------------------------- банк пробника ЕНТ
// content/bank/*.yaml → build/bank/bank.json + build/bank/media/. Формат — CONTENT_FORMAT.md,
// раздел «content/bank». Банк не привязан к сюжету: fact ↔ covers, ru, explain к нему не применяются.

class _Bank {
  _Bank(this.contexts, this.questions, this.media, this.summary);
  final List<Map<String, Object?>> contexts;
  final List<Map<String, Object?>> questions;
  final Set<String> media;              // пути от content/bank/: media/x.jpg
  final Map<String, Object?> summary;   // уходит в common.json → bank
}

/// Годен для пробника: ответ не под сомнением и картинка на месте.
bool _bankOk(Map q) => q['check'] != true && q['image_missing'] != true;

_Bank? _loadBank(String content, Set<String> sources, Set<String> seriesQids) {
  final dir = Directory(p.join(content, 'bank'));
  if (!dir.existsSync()) return null;
  final all = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.yaml')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  // Файл с `lang:` — не банк, а перевод к нему (school_tests_ru.yaml): те же id, только тексты.
  final files = <File>[];
  final tr = <String, Map<String, Map>>{}; // lang → id → запись перевода
  for (final f in all) {
    final y = _yaml(f.path) as Map;
    final lang = y['lang'] as String?;
    if (lang == null) { files.add(f); continue; }
    final m = tr.putIfAbsent(lang, () => {});
    for (final e in [...(y['contexts'] as List? ?? []), ...(y['questions'] as List? ?? [])].cast<Map>()) {
      m[e['id'] as String] = e;
    }
  }
  if (files.isEmpty) return null;
  /// kk из банка + переводы по id: {kk, ru}. Нет перевода — ошибка (если перевод на этот язык вообще есть).
  Map<String, String> l10n(String id, String field, String kkText, {int? option}) {
    final out = {'kk': kkText};
    for (final e in tr.entries) {
      final rec = e.value[id];
      if (rec == null) continue; // отсутствие записи целиком проверяется отдельно
      final node = option == null ? rec[field] : ((rec[field] as List?)?.elementAtOrNull(option));
      final t = node is Map ? (node[e.key] as String?)?.trim() : null;
      if (t == null || t.isEmpty) { err('bank $id: нет перевода ${e.key} для $field${option == null ? '' : '[$option]'}'); continue; }
      out[e.key] = t;
    }
    return out;
  }
  void needTranslation(String id, {int? options}) {
    for (final e in tr.entries) {
      final rec = e.value[id];
      if (rec == null) { err('bank $id: нет перевода ${e.key}'); continue; }
      if (options != null && (rec['options'] as List? ?? []).length != options) {
        err('bank $id: в переводе ${e.key} вариантов ${(rec['options'] as List? ?? []).length}, в оригинале $options');
      }
    }
  }

  final contexts = <Map<String, Object?>>[];
  final questions = <Map<String, Object?>>[];
  final media = <String>{};
  final ids = <String>{};
  String? kk(Object? m) => m is Map ? (m['kk'] as String?)?.trim() : null;

  void needImage(String where, Object? img) {
    if (img == null) return;
    final rel = img as String;
    if (!File(p.join(dir.path, rel)).existsSync()) { err('bank $where: нет файла картинки $rel'); return; }
    media.add(rel);
  }

  for (final f in files) {
    final name = p.basename(f.path);
    final b = _yaml(f.path) as Map;
    final source = b['source'] as String?;
    if (source == null || !sources.contains(source)) err('bank $name: неизвестный источник $source');

    final ctx = <String, Map>{};
    for (final c in (b['contexts'] as List? ?? []).cast<Map>()) {
      final id = c['id'] as String;
      if (!ids.add(id)) err('bank $id: повтор id');
      if (seriesQids.contains(id)) err('bank $id: id совпадает с вопросом серии');
      ctx[id] = c;
      final text = kk(c['text']);
      if ((text == null || text.isEmpty) && c['image'] == null) err('bank $id: у контекста нет ни text, ни image');
      needImage(id, c['image']);
      needTranslation(id);
      contexts.add({
        'id': id,
        if (text != null && text.isNotEmpty) 'text': l10n(id, 'text', text),
        if (c['image'] != null) 'image': c['image'],
        if (kk(c['caption']) case final cap? when cap.isNotEmpty) 'caption': l10n(id, 'caption', cap),
        'questions': (c['questions'] as List? ?? []).cast<String>(),
      });
    }

    final byId = <String, Map>{};
    for (final q in (b['questions'] as List? ?? []).cast<Map>()) {
      final id = q['id'] as String;
      if (!ids.add(id)) err('bank $id: повтор id');
      if (seriesQids.contains(id)) err('bank $id: id совпадает с вопросом серии');
      byId[id] = q;
      final format = q['format'];
      if (format != 'single' && format != 'context') err('bank $id: format должен быть single|context');
      if (format == 'context') {
        final c = ctx[q['context']];
        if (c == null) {
          err('bank $id: контекст ${q['context']} не найден');
        } else if (!(c['questions'] as List? ?? []).contains(id)) {
          err('bank $id: вопроса нет в questions контекста ${q['context']}');
        }
      }
      if (format == 'single' && q['context'] != null) err('bank $id: у single не должно быть context');
      if (kk(q['stem'])?.isEmpty ?? true) err('bank $id: пустой stem.kk');
      final opts = (q['options'] as List? ?? []).cast<Object?>();
      if (opts.length < 3 || opts.length > 6) err('bank $id: вариантов ${opts.length}, нужно 3–6');
      for (var i = 0; i < opts.length; i++) {
        if (kk(opts[i])?.isEmpty ?? true) err('bank $id: пустой вариант $i');
      }
      final answer = q['answer'];
      if (answer is! int || answer < 0 || answer >= opts.length) err('bank $id: answer $answer вне options');
      needImage(id, q['image']);
      needTranslation(id, options: opts.length);
      questions.add({
        'id': id, 'format': format,
        if (q['context'] != null) 'context': q['context'],
        'stem': l10n(id, 'stem', kk(q['stem']) ?? ''),
        'options': [for (var i = 0; i < opts.length; i++) l10n(id, 'options', kk(opts[i]) ?? '', option: i)],
        'answer': answer,
        if (q['shuffle'] == false) 'shuffle': false,
        if (q['image'] != null) 'image': q['image'],
        'topic': q['topic'], 'season': q['season'], 'episode': q['episode'],
        if (q['check'] == true) 'check': true,
        if (q['image_missing'] == true) 'image_missing': true,
      });
    }
    // в обратную сторону: каждый id из контекста — существующий context-вопрос этого контекста
    for (final c in ctx.values) {
      for (final qid in (c['questions'] as List? ?? []).cast<String>()) {
        final q = byId[qid];
        if (q == null) { err('bank ${c['id']}: вопрос $qid не найден'); continue; }
        if (q['context'] != c['id']) err('bank ${c['id']}: вопрос $qid указывает на контекст ${q['context']}');
      }
    }
  }

  final okIds = {for (final q in questions) if (_bankOk(q)) q['id']};
  final singleOk = questions.where((q) => q['format'] == 'single' && _bankOk(q)).length;
  final ctxOk = contexts.where((c) => (c['questions'] as List).where(okIds.contains).length >= 5).length;
  // перевод на id, которого нет в банке, — скорее всего опечатка или устаревшая запись
  final bankIds = {for (final c in contexts) c['id'], for (final q in questions) q['id']};
  for (final e in tr.entries) {
    for (final id in e.value.keys) { if (!bankIds.contains(id)) warn('bank перевод ${e.key}: $id нет в банке'); }
  }
  return _Bank(contexts, questions, media, {
    'langs': ['kk', ...tr.keys],
    'questions': questions.length,
    'single': questions.where((q) => q['format'] == 'single').length,
    'context': questions.where((q) => q['format'] == 'context').length,
    'contexts': contexts.length,
    'singleOk': singleOk,
    'contextsOk': ctxOk,
    'media': media.length,
  });
}

void _printBank(_Bank b) {
  final s = b.summary;
  stdout.writeln('bank   вопросов ${s['questions']} (${s['single']} single / ${s['context']} context)  '
      'контекстов ${s['contexts']}  картинок ${s['media']}  '
      'годны для пробника: single ${s['singleOk']}, контекстов ≥5 вопросов ${s['contextsOk']}');
}

void _writeBank(String content, String out, _Bank b) {
  final dir = Directory(p.join(out, 'bank'));
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  Directory(p.join(dir.path, 'media')).createSync(recursive: true);
  for (final rel in b.media) {
    File(p.join(content, 'bank', rel)).copySync(p.join(dir.path, rel));
  }
  // без отступов: файл большой, читается только приложением
  File(p.join(dir.path, 'bank.json')).writeAsStringSync(jsonEncode({'contexts': b.contexts, 'questions': b.questions}));
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
