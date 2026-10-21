import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomads_way/data/models/episode.dart';
import 'package:nomads_way/widgets/scene_fx/scene_camera.dart';

Scene _scene(Map<String, dynamic> extra) => Scene.fromJson({
      'id': 'sc100', 'art': 'art_100', 'covers': [], 'quiz': [],
      'beats': [
        {'type': 'say', 'who': 'qasym', 'text': {'kk': 'Алға!', 'ru': 'Вперёд!'}, 'impact': true},
        {'type': 'say', 'who': 'narrator', 'text': {'kk': 'а', 'ru': 'б'}},
      ],
      ...extra,
    });

void main() {
  test('без записи в content/fx сцена «дышит», частиц нет, реплики обычные', () {
    final sc = Scene.fromJson({'id': 'sc010', 'art': 'a', 'covers': [], 'beats': [], 'quiz': []});
    expect(sc.camera.move, CameraMove.breathe);
    expect(sc.fx, isEmpty);
  });

  test('камера, слои и ударная реплика читаются из episode.json', () {
    final sc = _scene({
      'camera': {'move': 'push', 'zoom': 1.18, 'dur': 16, 'panY': 55},
      'fx': [
        {'type': 'fog'},
        {'type': 'embers', 'x': .52, 'y': .78, 'density': .6},
      ],
    });
    expect(sc.camera.move, CameraMove.push);
    expect(sc.camera.maxZoom, 1.18);
    expect(sc.camera.seconds, 16);
    expect(sc.camera.panY, 55);
    expect(sc.fx.map((f) => f.type), [FxType.fog, FxType.embers]);
    expect(sc.fx.last.anchored, isTrue, reason: 'искры едут вместе с картинкой');
    expect(sc.fx.first.anchored, isFalse, reason: 'туман висит над кадром');
    expect((sc.beats[0] as Say).impact, isTrue);
    expect((sc.beats[1] as Say).impact, isFalse);
  });

  test('незнакомый тип слоя (контент новее приложения) пропускается, а не роняет серию', () {
    final sc = _scene({'fx': [{'type': 'rain'}, {'type': 'snow'}]});
    expect(sc.fx.map((f) => f.type), [FxType.snow]);
  });

  group('кадр камеры', () {
    const view = Size(390, 844);
    const aspect = 768 / 1344;

    test('неподвижная камера = BoxFit.cover с выравниванием по pan', () {
      for (final pan in [0, 50, 100]) {
        final r = frame(view, aspect, pan.toDouble(), const CameraSpec(move: CameraMove.still), 0);
        // картинка, вписанная BoxFit.cover: целиком закрывает экран, лишнее уходит за края
        final k = [view.width / 768, view.height / 1344].reduce((a, b) => a > b ? a : b);
        final cover = Size(768 * k, 1344 * k);
        final expected = Alignment(pan / 50 - 1, 0).inscribe(cover, Offset.zero & view);
        expect(r.left, closeTo(expected.left, .01), reason: 'pan $pan');
        expect(r.top, closeTo(expected.top, .01));
        expect(r.size.width, closeTo(expected.width, .01));
      }
    });

    test('наезд: в начале кадр как сейчас, в конце приближен на zoom; экран всегда закрыт', () {
      const c = CameraSpec(move: CameraMove.push, zoom: 1.2);
      final a = frame(view, aspect, 50, c, 0), b = frame(view, aspect, 50, c, 1);
      expect(b.width / a.width, closeTo(1.2, 1e-9));
      for (final r in [a, b]) {
        expect(r.left <= 0 && r.top <= 0 && r.right >= view.width && r.bottom >= view.height, isTrue);
      }
    });

    test('панорама едет от from к to', () {
      const c = CameraSpec(move: CameraMove.pan, from: 30, to: 70);
      final a = frame(view, aspect, 50, c, 0), b = frame(view, aspect, 50, c, 1);
      expect(b.left, lessThan(a.left), reason: 'к правому краю картинки — картинка уезжает влево');
      expect(a.width, b.width, reason: 'панорама без приближения по ходу');
    });
  });
}
