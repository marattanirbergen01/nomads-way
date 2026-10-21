import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../data/models/scene_fx.dart';

/// Кадр с живой камерой: медленный наезд, отъезд, панорама или «дыхание».
///
/// Картинка заполняет экран как BoxFit.cover, `pan` сдвигает её по горизонтали как раньше;
/// камера добавляет приближение и движение туда-обратно с мягкими разворотами.
/// Фаза считается от [since] — момента входа в сцену, поэтому камера не прыгает,
/// когда экран реплики сменяется экраном выбора и виджет строится заново.
///
/// [image] — сам кадр, растягивается на прямоугольник камеры (BoxFit.fill).
/// [provider] — тот же кадр как ImageProvider: по нему узнаём пропорции.
/// [anchored] рисуется в координатах картинки и едет вместе с ней (огонь у костра).
class SceneCamera extends StatefulWidget {
  const SceneCamera({
    super.key,
    required this.image,
    required this.provider,
    required this.since,
    this.pan = 50,
    this.spec = CameraSpec.breathe,
    this.anchored,
  });

  final Widget image;
  final ImageProvider provider;
  final DateTime since;
  final int pan;
  final CameraSpec spec;
  final Widget? anchored;

  @override
  State<SceneCamera> createState() => _SceneCameraState();
}

class _SceneCameraState extends State<SceneCamera> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));
  ImageStream? _stream;
  late final _listener = ImageStreamListener(_onImage);
  double _aspect = 768 / 1344; // кадры сезона 1; уточняется, когда картинка загрузится
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
    _still = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) || widget.spec.move == CameraMove.still;
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(SceneCamera old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool _) {
    final a = info.image.width / info.image.height;
    info.dispose();
    if (mounted && a != _aspect) setState(() => _aspect = a);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _ticker.dispose();
    super.dispose();
  }

  /// 0..1..0 по времени с мягкими разворотами (easeInOutSine).
  double _phase() {
    if (_still) return 0;
    final period = (widget.spec.seconds ?? _defaultSeconds(widget.spec.move)) * 1000;
    final ms = DateTime.now().difference(widget.since).inMilliseconds.toDouble();
    final x = (ms / period) % 2;
    final t = x <= 1 ? x : 2 - x;
    return 0.5 - math.cos(math.pi * t) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final rect = frame(box.biggest, _aspect, widget.pan.toDouble(), widget.spec, _phase());
      return ClipRect(
        child: Stack(children: [
          Positioned.fromRect(rect: rect, child: widget.image),
          if (widget.anchored != null) Positioned.fromRect(rect: rect, child: IgnorePointer(child: widget.anchored!)),
        ]),
      );
    });
  }

  static double _defaultSeconds(CameraMove m) => switch (m) {
        CameraMove.breathe => 9,
        CameraMove.pan => 18,
        _ => 14,
      };
}

/// Прямоугольник картинки на экране [view] при фазе движения [k] (0..1).
/// Лишнее по ширине и высоте распределяется по pan (0..100) так же, как Alignment у BoxFit.cover.
@visibleForTesting
Rect frame(Size view, double aspect, double pan, CameraSpec c, double k) {
  double lerp(double a, double b) => a + (b - a) * k;
  final base = pan.clamp(0, 100).toDouble();
  final (zoom, panX) = switch (c.move) {
    CameraMove.still => (1.0, base),
    CameraMove.breathe => (lerp(1.02, c.maxZoom), lerp(c.from ?? base, c.to ?? base)),
    CameraMove.push => (lerp(1, c.maxZoom), lerp(c.from ?? base, c.to ?? base)),
    CameraMove.pull => (lerp(c.maxZoom, 1), lerp(c.from ?? base, c.to ?? base)),
    CameraMove.pan => (c.maxZoom, lerp(c.from ?? math.max(0, base - 30), c.to ?? math.min(100, base + 30))),
  };
  final cover = math.max(view.width / aspect, view.height);
  final h = cover * zoom;
  final w = h * aspect;
  return Rect.fromLTWH(
    -(w - view.width) * panX.clamp(0, 100) / 100,
    -(h - view.height) * c.panY.clamp(0, 100) / 100,
    w,
    h,
  );
}
