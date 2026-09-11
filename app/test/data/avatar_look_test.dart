import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/curriculum.dart';

void main() {
  test('лицо садится на одну высоту кружка у разных внешностей', () {
    // портрет 0.777: в квадрате видно 77.7% высоты, окно можно сдвигать на 22.3%
    final high = const AvatarLook(look: 1, id: 'a', season: 's1', emotions: ['calm'], faceY: .30, aspect: .777);
    final low = const AvatarLook(look: 2, id: 'b', season: 's1', emotions: ['calm'], faceY: .36, aspect: .777);
    double posInCircle(AvatarLook a) {
      final vis = a.aspect; final al = a.circleAlignment().y;
      final t = (al + 1) / 2 * (1 - vis);
      return (a.faceY - t) / vis;
    }
    expect(posInCircle(high), closeTo(.40, .02));
    expect(posInCircle(low), closeTo(.40, .02));
    expect(high.circleAlignment().y, lessThanOrEqualTo(low.circleAlignment().y), reason: 'высокое лицо — окно не ниже');
  });

  test('квадратный кадр не двигаем', () {
    const sq = AvatarLook(look: 1, id: 'a', season: 's1', emotions: ['calm'], faceY: .2, aspect: 1);
    expect(sq.circleAlignment(), Alignment.center);
  });
}
