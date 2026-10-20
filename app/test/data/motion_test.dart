import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';

Episode _ep(Map<String, Object> motion) => Episode.fromJson({
      'id': 's1e01', 'title': {'kk': 't'}, 'characters': {}, 'finalTest': {'single': 0, 'context': 0},
      'scenes': [], 'motion': motion,
    });

void main() {
  test('язык ролика: язык игрока, иначе kk, иначе любой; нет ролика — null', () {
    final both = _ep({'map_a': {'kk': 'map_a_kk.jpg', 'ru': 'map_a_ru.jpg'}});
    expect(both.motionLang('map_a', 'ru'), 'ru');
    expect(both.motionLang('map_a', 'kk'), 'kk');
    expect(both.motionLang('art_x', 'kk'), isNull);
    expect(_ep({'map_a': {'kk': 'a.jpg'}}).motionLang('map_a', 'ru'), 'kk');
    expect(_ep({'map_a': {'ru': 'a.png'}}).motionLang('map_a', 'kk'), 'ru');
    expect(both.motionPoster('map_a', 'ru'), 'map_a_ru.jpg');
    expect(_ep({}).motionLang('map_a', 'kk'), isNull);
  });
}
