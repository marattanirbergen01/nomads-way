import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';
import 'package:nomads_way/engine/season_vars.dart';
import 'package:nomads_way/engine/story_runner.dart';

void main() {
  group('SeasonVars.entryFor', () {
    final ends = {
      's1e01': {'yurt_river': 1, 'trust': 2},
      's1e02': {'yurt_river': 1, 'trust': 3, 'horse': 1},
      's1e04': {'late': 1},
      's2e01': {'other_season': 1},
    };

    test('первая серия сезона — с нуля', () => expect(SeasonVars.entryFor('s1e01', ends), isEmpty));
    test('берёт конец предыдущей серии сезона', () => expect(SeasonVars.entryFor('s1e02', ends), ends['s1e01']));
    test('ближайшая пройденная раньше, а не последняя по времени', () {
      expect(SeasonVars.entryFor('s1e03', ends), ends['s1e02'], reason: 's1e04 позже по номеру — не считается');
    });
    test('перепрохождение серии стартует с того, с чем в неё вошли, а не с её конца', () {
      expect(SeasonVars.entryFor('s1e02', ends), isNot(ends['s1e02']));
    });
    test('другой сезон не наследует', () {
      expect(SeasonVars.entryFor('s2e01', ends), isEmpty);
      expect(SeasonVars.entryFor('s2e02', ends), ends['s2e01']);
    });
    test('копия, а не ссылка: выборы новой серии не портят сохранённое', () {
      final v = SeasonVars.entryFor('s1e02', ends)..['trust'] = 99;
      expect(ends['s1e01']!['trust'], 2);
      expect(v['trust'], 99);
    });
    test('id не по шаблону — с нуля', () => expect(SeasonVars.entryFor('intro', ends), isEmpty));
  });

  test('реплика с when звучит, если переменную поставила прошлая серия', () {
    final ep = Episode.fromJson({
      'id': 's1e02', 'title': {'kk': 't'}, 'characters': {}, 'finalTest': {'single': 0, 'context': 0},
      'scenes': [
        {'id': 'a', 'art': 'x', 'covers': [], 'quiz': [], 'beats': [
          {'type': 'say', 'who': 'n', 'text': {'kk': 'всем'}},
          {'type': 'say', 'who': 'n', 'text': {'kk': 'помнишь реку?'}, 'when': [{'var': 'yurt_river', 'op': '>=', 'value': 1}]},
        ]},
      ],
    });
    List<String> lines(Map<String, int> vars) {
      final r = StoryRunner(ep, vars: vars);
      final out = <String>[];
      for (var e = r.next(); e is BeatEvent; e = r.next()) { out.add((e.beat as Say).text.of('kk')); }
      return out;
    }
    expect(lines({}), ['всем']);
    expect(lines(SeasonVars.entryFor('s1e02', {'s1e01': {'yurt_river': 1}})), ['всем', 'помнишь реку?']);
  });
}
