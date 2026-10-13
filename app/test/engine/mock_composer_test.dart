import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/bank.dart';
import 'package:nomads_way/data/models/question.dart';
import 'package:nomads_way/engine/mock_composer.dart';
import 'package:nomads_way/engine/quiz_runner.dart';

/// Настоящий банк школы из сборки (dart run bin/compile.dart в tools/).
Bank _realBank() {
  final f = File('../build/bank/bank.json');
  if (!f.existsSync()) fail('нет ../build/bank/bank.json — сначала собрать контент');
  return Bank.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
}

/// Маленький банк с крайними случаями: image_missing, check, контекст-карта, контекст из 9 вопросов.
Bank _tinyBank() {
  final qs = <Map<String, dynamic>>[];
  final ctx = <Map<String, dynamic>>[];
  Map<String, dynamic> q(String id, {String fmt = 'single', String? context, int topic = 1, bool check = false, bool missing = false, bool shuffle = true}) => {
        'id': id, 'format': fmt, 'context': context, 'stem': {'kk': 'сұрақ $id'},
        'options': [for (var i = 0; i < 4; i++) {'kk': '$id-нұсқа-$i'}],
        'answer': 2, 'topic': topic, 'season': 1, 'episode': 's1e01',
        if (check) 'check': true, if (missing) 'image_missing': true, if (!shuffle) 'shuffle': false,
      };
  for (var i = 0; i < 30; i++) { qs.add(q('s$i', topic: i % 12)); }
  qs.add(q('bad-check', check: true));
  qs.add(q('bad-missing', missing: true));
  void addCtx(String id, int n, {bool image = false, List<int> badAt = const []}) {
    final ids = <String>[];
    for (var i = 0; i < n; i++) {
      final qid = '$id-q$i';
      ids.add(qid);
      qs.add(q(qid, fmt: 'context', context: id, check: badAt.contains(i) && i.isEven, missing: badAt.contains(i) && i.isOdd));
    }
    ctx.add({'id': id, if (!image) 'text': {'kk': 'мәтін $id'}, if (image) 'image': 'media/$id.jpg', 'questions': ids});
  }
  addCtx('text1', 5);
  addCtx('text2', 6, badAt: [0, 1]);   // годных 4 — в пробник не годится
  addCtx('map1', 5, image: true);
  addCtx('big', 9);
  return Bank.fromJson({'contexts': ctx, 'questions': qs});
}

void _checkStructure(MockVariant v) {
  final m = v.mode;
  expect(v.questions.length, 20);
  final singles = v.questions.take(m.singles).toList();
  expect(singles.every((q) => q.format == QFormat.single), isTrue);
  expect(singles.map((q) => q.id).toSet().length, m.singles, reason: 'без повторов');
  expect(v.contexts.length, m.contexts);
  expect(v.contexts.map((c) => c.id).toSet().length, m.contexts, reason: 'контексты разные');
  for (var b = 0; b < m.contexts; b++) {
    final block = v.questions.skip(m.singles + b * 5).take(5).toList();
    expect(block.every((q) => q.format == QFormat.context && q.context == v.contexts[b].id), isTrue,
        reason: 'блок ${b + 1} — только вопросы своего контекста');
    expect(block.map((q) => q.id).toSet().length, 5);
  }
  expect(v.questions.every((q) => q.eligible), isTrue);
}

void main() {
  group('composeMock на банке школы', () {
    late Bank bank;
    setUpAll(() => bank = _realBank());

    test('20 заданий: 1–10 single, 11–15 контекст 1, 16–20 контекст 2', () {
      final v = MockComposer.composeMock(bank, random: Random(7));
      _checkStructure(v);
      expect(v.blockOf(9), isNull);
      expect(v.blockOf(10), 0);
      expect(v.blockOf(15), 1);
      expect(v.startsBlock(10) && v.startsBlock(15) && !v.startsBlock(11), isTrue);
    });

    test('не больше 2 вопросов на тему в 1–10', () {
      for (var seed = 0; seed < 200; seed++) {
        final v = MockComposer.composeMock(bank, random: Random(seed));
        final per = <String, int>{};
        for (final q in v.questions.take(10)) { per[q.topic!] = (per[q.topic!] ?? 0) + 1; }
        expect(per.values.every((n) => n <= 2), isTrue, reason: 'seed $seed: $per');
      }
    });

    test('check и image_missing не попадают ни при каком seed (1000 seed)', () {
      final bad = bank.questions.where((q) => !q.eligible).map((q) => q.id).toSet();
      expect(bad, isNotEmpty, reason: 'в банке есть вопросы с check');
      for (var seed = 0; seed < 1000; seed++) {
        final v = MockComposer.composeMock(bank, random: Random(seed));
        expect(v.questions.any((q) => bad.contains(q.id)), isFalse, reason: 'seed $seed');
      }
    });

    test('из контекста с 9 вопросами — ровно 5, при разных seed разные пятёрки', () {
      final big = bank.contexts.firstWhere((c) => bank.eligibleOf(c).length > 5);
      final fives = <String>{};
      var hits = 0;
      for (var seed = 0; seed < 3000 && hits < 30; seed++) {
        final v = MockComposer.composeMock(bank, random: Random(seed));
        final b = v.contexts.indexWhere((c) => c.id == big.id);
        if (b < 0) continue;
        hits++;
        final block = v.questions.skip(10 + b * 5).take(5).map((q) => q.id).toList();
        expect(block.length, 5);
        expect(block.every(big.questionIds.contains), isTrue);
        fives.add((List.of(block)..sort()).join(','));
      }
      expect(hits, greaterThan(1), reason: 'контекст из 9 вопросов должен попадать в варианты');
      expect(fives.length, greaterThan(1), reason: 'пятёрки должны различаться');
    });

    test('порядок внутри блока разный при разных seed, состав — из своего контекста', () {
      // для каждого контекста копим встреченные порядки его блока
      final orders = <String, Set<String>>{};
      for (var seed = 0; seed < 1500; seed++) {
        final v = MockComposer.composeMock(bank, random: Random(seed));
        for (var b = 0; b < 2; b++) {
          final c = v.contexts[b];
          final block = v.questions.skip(10 + b * 5).take(5).map((q) => q.id).toList();
          expect(block.every(c.questionIds.contains), isTrue);
          if (bank.eligibleOf(c).length == 5) (orders[c.id] ??= {}).add(block.join(','));
        }
      }
      final repeated = orders.values.where((o) => o.length > 1);
      expect(repeated, isNotEmpty, reason: 'один и тот же контекст должен приходить в разном порядке');
    });

    test('контексты-карты участвуют наравне с текстовыми', () {
      var maps = 0;
      for (var seed = 0; seed < 300; seed++) {
        maps += MockComposer.composeMock(bank, random: Random(seed)).contexts.where((c) => c.isImage).length;
      }
      expect(maps, greaterThan(0));
    });

    test('недавние вопросы не повторяются, пока хватает других', () {
      final first = MockComposer.composeMock(bank, random: Random(1));
      final recent = first.questions.map((q) => q.id).toSet();
      final next = MockComposer.composeMock(bank, random: Random(2), recent: recent);
      expect(next.questions.where((q) => recent.contains(q.id)), isEmpty);
    });
  });

  group('composeQuick на банке школы', () {
    late Bank bank;
    setUpAll(() => bank = _realBank());

    test('20: 1–15 single без повторов и не больше 2 на тему, 16–20 один контекст, без check', () {
      final bad = bank.questions.where((q) => !q.eligible).map((q) => q.id).toSet();
      for (var seed = 0; seed < 300; seed++) {
        final v = MockComposer.composeQuick(bank, random: Random(seed));
        _checkStructure(v);
        expect(v.mode.singles, 15);
        final per = <String, int>{};
        for (final q in v.questions.take(15)) { per[q.topic!] = (per[q.topic!] ?? 0) + 1; }
        expect(per.values.every((n) => n <= 2), isTrue, reason: 'seed $seed');
        expect(v.questions.any((q) => bad.contains(q.id)), isFalse);
      }
    });
  });

  group('крайние случаи', () {
    test('image_missing и check не попадают; контекст с 4 годными не выбирается', () {
      final bank = _tinyBank();
      for (var seed = 0; seed < 1000; seed++) {
        final v = MockComposer.composeMock(bank, random: Random(seed));
        _checkStructure(v);
        expect(v.questions.any((q) => q.id.startsWith('bad-')), isFalse);
        expect(v.contexts.any((c) => c.id == 'text2'), isFalse);
        expect(v.questions.any((q) => q.id == 'text2-q0' || q.id == 'text2-q1'), isFalse);
      }
    });

    test('не хватает вопросов — canCompose false, compose бросает', () {
      final empty = Bank.fromJson({'contexts': [], 'questions': []});
      expect(MockComposer.canCompose(empty, MockMode.mock), isFalse);
      expect(() => MockComposer.composeMock(empty, random: Random(1)), throwsStateError);
    });
  });

  group('варианты ответа', () {
    test('после перемешивания правильный — тот же по тексту; буквы назначаются заново', () {
      final bank = _realBank();
      final v = MockComposer.composeMock(bank, random: Random(3));
      final run = QuizRunner(v.questions, random: Random(3));
      var moved = 0;
      while (!run.done) {
        final p = run.current()!;
        final q = p.question;
        final right = q.correct.text.of('kk');
        final shown = p.options.indexWhere((o) => o.correct);
        expect(p.options[shown].text.of('kk'), right);
        if (shown != q.options.indexWhere((o) => o.correct)) moved++;
        final r = run.answer(p.options[shown].id);
        expect(r.correct, isTrue, reason: 'проверка по варианту, не по букве');
      }
      expect(run.correctCount, 20);
      expect(moved, greaterThan(0), reason: 'правильный ответ не должен стоять на своём месте всегда');
    });

    test('shuffle: false — порядок исходный при любом seed', () {
      final bank = _realBank();
      final fixed = bank.questions.firstWhere((q) => !q.shuffle);
      for (var seed = 0; seed < 50; seed++) {
        final p = QuizRunner([fixed], random: Random(seed)).current()!;
        expect(p.options.map((o) => o.id).toList(), fixed.options.map((o) => o.id).toList());
      }
    });

    test('у банка факт ent.<тема>, объяснения нет', () {
      final q = _realBank().questions.first;
      expect(q.fact, startsWith('ent.'));
      expect(q.fromBank, isTrue);
      expect(q.explain.of('kk'), isEmpty);
    });
  });
}
