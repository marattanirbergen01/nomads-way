import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';

Scene _scene(List<Map<String, dynamic>> rules) => Scene.fromJson({
      'id': 'sc045', 'art': 'art_045', 'covers': [], 'beats': [], 'quiz': [], 'artWhen': rules,
    });

void main() {
  test('кадр по флагу выбора: первое совпавшее правило, иначе базовый', () {
    final sc = _scene([
      {'if': [{'var': 'yurt_river', 'op': '>', 'value': 0}], 'art': 'art_045_river'},
      {'if': [{'var': 'yurt_hill', 'op': '>', 'value': 0}], 'art': 'art_045_hill'},
    ]);
    expect(sc.artFor({'yurt_river': 1}), 'art_045_river');
    expect(sc.artFor({'yurt_hill': 1}), 'art_045_hill');
    expect(sc.artFor({}), 'art_045', reason: 'выбор ещё не сделан — базовый кадр');
    expect(sc.artFor({'yurt_river': 1, 'yurt_hill': 1}), 'art_045_river', reason: 'первое правило побеждает');
  });

  test('сравнения и связка &&', () {
    final sc = _scene([
      {'if': [{'var': 'loyalty', 'op': '>=', 'value': 2}, {'var': 'caution', 'op': '==', 'value': 0}], 'art': 'art_loyal'},
      {'if': [{'var': 'loyalty', 'op': '<', 'value': 2}], 'art': 'art_doubt'},
    ]);
    expect(sc.artFor({'loyalty': 3}), 'art_loyal');
    expect(sc.artFor({'loyalty': 3, 'caution': 1}), 'art_045', reason: 'второе условие && не выполнено, второе правило тоже');
    expect(sc.artFor({'loyalty': 1}), 'art_doubt');
  });
}
