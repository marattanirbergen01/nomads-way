import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';
import 'package:nomads_way/engine/story_runner.dart';

Episode _ep() => Episode.fromJson({
      'id': 't', 'title': {'kk': 'T'},
      'characters': {'n': {'name': {'kk': 'N'}, 'fiction': false}},
      'finalTest': {'single': 10, 'context': 10},
      'scenes': [
        {'id': 'a', 'art': 'x', 'covers': ['f1'], 'quiz': ['q1'],
         'beats': [
           {'type': 'say', 'who': 'n', 'text': {'kk': 'hi'}},
           {'type': 'choice', 'prompt': {'kk': '?'}, 'options': [
             {'id': 'o1', 'text': {'kk': '1'}, 'set': {'x': 2}, 'goto': 'c'},
             {'id': 'o2', 'text': {'kk': '2'}, 'set': {}, 'goto': 'b'},
           ]},
         ]},
        {'id': 'b', 'art': 'x', 'covers': [], 'quiz': [], 'beats': [{'type': 'say', 'who': 'n', 'text': {'kk': 'b'}}]},
        {'id': 'c', 'art': 'x', 'covers': [], 'quiz': ['q2'], 'beats': [{'type': 'say', 'who': 'n', 'text': {'kk': 'c'}}]},
      ],
    });

void main() {
  test('биты → выбор → квиз сцены → переход по goto → конец', () {
    final r = StoryRunner(_ep());
    expect((r.next() as BeatEvent).beat, isA<Say>());
    final ch = (r.next() as BeatEvent).beat as Choice;
    expect(r.awaitingChoice, isTrue);
    expect(() => r.next(), throwsStateError);
    r.choose(ch.options.first);
    expect(r.vars['x'], 2);
    final qb = r.next() as QuizBreak;               // квиз ПОСЛЕ сцены, ДО перехода
    expect(qb.questionIds, ['q1']);
    expect((r.next() as BeatEvent).scene.id, 'c');   // goto сработал
    expect((r.next() as QuizBreak).questionIds, ['q2']);
    expect(r.next(), isA<EpisodeEnd>());
    expect(r.ended, isTrue);
  });

  test('сцена без выбора идёт к следующей по порядку', () {
    final r = StoryRunner(_ep());
    r.next();
    final ch = (r.next() as BeatEvent).beat as Choice;
    r.choose(ch.options[1]);                          // → b
    r.next();                                          // QuizBreak a
    expect((r.next() as BeatEvent).scene.id, 'b');
    expect((r.next() as BeatEvent).scene.id, 'c');   // b без выбора и без квиза → c
  });

  test('snapshot / restore сохраняет позицию и переменные', () {
    final r = StoryRunner(_ep());
    r.next();
    r.choose(((r.next() as BeatEvent).beat as Choice).options.first);
    final r2 = StoryRunner.restore(_ep(), r.snapshot());
    expect(r2.vars['x'], 2);
    expect(r2.next(), isA<QuizBreak>());
  });
}
