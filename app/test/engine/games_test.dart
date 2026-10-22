import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';
import 'package:nomads_way/engine/games/game_spec.dart';
import 'package:nomads_way/engine/story_runner.dart';

/// Настоящие описания из сборки (content/games/s1.yaml → компилятор → episode.json).
Episode _ep(String id) => Episode.fromJson(jsonDecode(File('../build/$id/episode.json').readAsStringSync()) as Map<String, dynamic>);
T _game<T extends GameSpec>(String ep, String id) =>
    _ep(ep).scenes.expand((s) => s.games).firstWhere((g) => g.id == id) as T;

void main() {
  group('путь кочевья', () {
    late RouteSpec spec;
    setUp(() => spec = _game<RouteSpec>('s1e01', 'route_shu'));

    test('через Каратау и Талас — 10 дней, победа', () {
      final g = RouteGame(spec);
      for (final n in ['karatau', 'talas', 'shu']) { expect(g.go(n), isTrue); }
      expect(g.finished, isTrue);
      expect(g.daysUsed, 10);
      expect(g.outcome, GameOutcome.win);
    });
    test('через степь — набег, поражение', () {
      final g = RouteGame(spec)..go('steppe')..go('shu');
      expect(g.outcome, GameOutcome.lose);
    });
    test('пески — дольше лимита, наполовину', () {
      final g = RouteGame(spec)..go('sands')..go('talas')..go('shu');
      expect(g.daysUsed, 12);
      expect(g.outcome, GameOutcome.win, reason: '12 = лимит');
      final g2 = RouteGame(spec)..go('sands')..go('talas')..go('karatau');
      expect(g2.canGo('shu'), isFalse, reason: 'из Каратау к Шу дороги нет');
    });
    test('ход только в соседнюю точку; отмена', () {
      final g = RouteGame(spec);
      expect(g.go('shu'), isFalse);
      g.go('karatau');
      g.undo();
      expect(g.at, 'syganaq');
    });
  });

  group('базар', () {
    test('все нужды закрыты — победа; шёлк вместо пшеницы — наполовину или хуже', () {
      final spec = _game<TradeSpec>('s1e02', 'bazaar_syganaq');
      final g = TradeGame(spec)..add('wheat')..add('cloth')..add('arrow')..add('salt')..add('salt');
      expect(g.left, 1);
      expect(g.outcome, GameOutcome.win);
      final g2 = TradeGame(spec)..add('silk')..add('pot')..add('salt')..add('salt');
      expect(g2.outcome, GameOutcome.lose, reason: 'закрыта одна нужда из четырёх');
      final g3 = TradeGame(spec);
      for (var i = 0; i < 20; i++) { g3.add('salt'); }
      expect(g3.left, 0, reason: 'больше бюджета не купить');
    });
  });

  group('залп', () {
    test('шкала 0→1→0; попадание в окне', () {
      final spec = _game<VolleySpec>('s1e02', 'volley_syganaq');
      final g = VolleyGame(spec);
      expect(g.meter(0), closeTo(0, 1e-9));
      expect(g.meter(spec.periodMs ~/ 2), closeTo(1, 1e-9));
      expect(g.shoot(spec.periodMs ~/ 2 - 60), isTrue, reason: 'около вершины — в золотой полосе');
      expect(g.shoot(0), isFalse, reason: 'рано');
      expect(g.shoot(spec.periodMs ~/ 2), isTrue);
      expect(g.finished, isTrue);
      expect(g.outcome, GameOutcome.win);
    });
    test('только для лучника (when role_archer)', () {
      final spec = _game<VolleySpec>('s1e02', 'volley_syganaq');
      expect(spec.visible({}), isFalse);
      expect(spec.visible({'role_archer': 1}), isTrue);
    });
  });

  test('тактика: охват — победа, в лоб — поражение', () {
    final spec = _game<TacticsSpec>('s1e02', 'battle_syganaq_1510');
    expect(spec.moves.firstWhere((m) => m.id == 'envelop').outcome, GameOutcome.win);
    expect(spec.moves.firstWhere((m) => m.id == 'head_on').outcome, GameOutcome.lose);
    expect(spec.outcome(GameOutcome.win).toasts.single.text.of('kk'), 'Байқағыш', reason: 'исход даёт плашку');
  });

  group('движок сюжета', () {
    test('игра после реплик сцены, до вопросов; исход ставит переменные', () {
      final ep = _ep('s1e01');
      final r = StoryRunner(ep);
      GameBreak? gb;
      for (var i = 0; i < 500; i++) {
        final e = r.next();
        if (r.awaitingChoice) { r.choose((e as BeatEvent).beat is Choice ? ((e.beat as Choice).options.first) : throw StateError('')); continue; }
        if (e is GameBreak) { gb = e; break; }
        if (e is EpisodeEnd) break;
      }
      expect(gb?.game.id, 'route_shu');
      expect(gb?.scene.id, 'sc031');
      expect(() => r.next(), throwsStateError, reason: 'пока игра не сыграна — дальше нельзя');
      final before = r.vars['vigilant'] ?? 0;
      r.finishGame(GameOutcome.win);
      expect(r.vars['vigilant'], before + 1);
      final e = r.next();
      expect(e, isA<QuizBreak>(), reason: 'после игры — вопросы сцены');
    });

    test('вышли посреди игры — после восстановления игра начнётся снова', () {
      final ep = _ep('s1e01');
      final r = StoryRunner(ep);
      for (var i = 0; i < 500; i++) {
        final e = r.next();
        if (r.awaitingChoice) { r.choose(((e as BeatEvent).beat as Choice).options.first); continue; }
        if (e is GameBreak) break;
      }
      final snap = jsonDecode(jsonEncode(r.snapshot())) as Map<String, dynamic>;
      final r2 = StoryRunner.restore(ep, snap);
      expect(r2.next(), isA<GameBreak>());
    });
  });
}
