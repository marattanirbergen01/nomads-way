import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../data/models/scene_fx.dart';

/// Слой частиц поверх кадра. С картинкой не связан: просто рисует пыль,
/// песок, туман, снег, искры или отсвет огня в своих границах.
class ParticleLayer extends StatefulWidget {
  const ParticleLayer({super.key, required this.fx, this.seed = 1});

  final List<FxLayer> fx;
  final int seed;

  @override
  State<ParticleLayer> createState() => _ParticleLayerState();
}

class _ParticleLayerState extends State<ParticleLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _clock = _Clock();
  List<_System> _systems = const [];
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _build();
    _ticker.start();
  }

  @override
  void didUpdateWidget(ParticleLayer old) {
    super.didUpdateWidget(old);
    if (!_sameFx(old.fx, widget.fx)) _build();
  }

  void _build() {
    final rnd = math.Random(widget.seed);
    _systems = [for (final f in widget.fx) _System.create(f, math.Random(rnd.nextInt(1 << 30)))];
  }

  void _tick(Duration now) {
    // Не больше 50 мс за кадр: после сворачивания вкладки частицы не «прыгают».
    final dt = math.min((now - _last).inMicroseconds / 1e6, 0.05);
    _last = now;
    _clock.advance(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _Painter(_systems, _clock), size: Size.infinite),
      ),
    );
  }

  static bool _sameFx(List<FxLayer> a, List<FxLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].type != b[i].type || a[i].x != b[i].x || a[i].y != b[i].y) return false;
    }
    return true;
  }
}

class _Clock extends ChangeNotifier {
  double time = 0;
  double dt = 0;

  void advance(double d) {
    dt = d;
    time += d;
    notifyListeners();
  }
}

class _Painter extends CustomPainter {
  _Painter(this.systems, this.clock) : super(repaint: clock);

  final List<_System> systems;
  final _Clock clock;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final s in systems) {
      s.step(clock.dt, clock.time, size);
      s.paint(canvas, size, clock.time);
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.systems != systems;
}

// ---------------------------------------------------------------------------

abstract class _System {
  _System(this.spec, this.rnd);

  final FxLayer spec;
  final math.Random rnd;
  final Paint p = Paint()..isAntiAlias = true;
  Size _size = Size.zero;

  static _System create(FxLayer f, math.Random r) => switch (f.type) {
        FxType.dust => _Dust(f, r),
        FxType.sand => _Sand(f, r),
        FxType.fog => _Fog(f, r),
        FxType.snow => _Snow(f, r),
        FxType.embers => _Embers(f, r),
        FxType.firelight => _Firelight(f, r),
      };

  /// Сколько частиц при данном размере: эталон — телефон 400×800.
  int count(Size s, int base) =>
      (base * spec.density * (s.width * s.height / 320000).clamp(0.5, 2.5)).round();

  void step(double dt, double t, Size size) {
    if (size != _size) {
      _size = size;
      reset(size);
    }
    update(dt, t, size);
  }

  void reset(Size size);
  void update(double dt, double t, Size size);
  void paint(Canvas canvas, Size size, double t);

  double r(double a, double b) => a + rnd.nextDouble() * (b - a);
}

/// Плавающие пылинки в луче света.
class _Dust extends _System {
  _Dust(super.spec, super.rnd);

  final _ps = <_P>[];

  @override
  void reset(Size s) {
    _ps
      ..clear()
      ..addAll(List.generate(count(s, 45), (_) {
        return _P(r(0, s.width), r(0, s.height))
          ..vx = r(4, 14) * spec.wind
          ..vy = r(-6, 4)
          ..size = r(0.8, 2.6)
          ..a = r(0.35, 0.85)
          ..tone = r(0, 1)
          ..phase = r(0, 6.28);
      }));
  }

  @override
  void update(double dt, double t, Size s) {
    for (final q in _ps) {
      q.x += (q.vx + math.sin(t * 0.4 + q.phase) * 6) * dt;
      q.y += (q.vy + math.cos(t * 0.3 + q.phase) * 4) * dt;
      _wrap(q, s, 4);
    }
  }

  @override
  void paint(Canvas c, Size s, double t) {
    for (final q in _ps) {
      final tw = 0.6 + 0.4 * math.sin(t * 1.3 + q.phase * 3);
      p.color = _sand(q.tone, q.a * tw);
      c.drawCircle(Offset(q.x, q.y), q.size, p);
    }
  }
}

/// Песчаная буря: косые штрихи по ветру, порывы и мутная дымка у земли.
class _Sand extends _System {
  _Sand(super.spec, super.rnd);

  final _ps = <_P>[];
  final _haze = Paint();

  @override
  void reset(Size s) {
    _ps
      ..clear()
      ..addAll(List.generate(count(s, 170), (_) {
        return _P(r(0, s.width), r(0, s.height))
          ..vx = r(260, 620)
          ..vy = r(15, 70)
          ..size = r(0.8, 2.0)
          ..a = r(0.35, 0.75)
          ..tone = r(0, 1);
      }));
    _haze.shader = ui.Gradient.linear(
      Offset(0, s.height * 0.35),
      Offset(0, s.height),
      const [Color(0x00C9A066), Color(0xFFC9A066)],
    );
  }

  double _gust(double t) =>
      0.65 + 0.25 * math.sin(t * 0.45) + 0.15 * math.sin(t * 1.7 + 1.3);

  @override
  void update(double dt, double t, Size s) {
    final g = _gust(t);
    for (final q in _ps) {
      q.x += q.vx * g * spec.wind * dt;
      q.y += q.vy * dt;
      _wrap(q, s, 40);
    }
  }

  @override
  void paint(Canvas c, Size s, double t) {
    final g = _gust(t);
    c.saveLayer(Offset.zero & s, Paint()..color = Color.fromRGBO(0, 0, 0, (0.10 + 0.22 * g).clamp(0, 1)));
    c.drawRect(Offset.zero & s, _haze);
    c.restore();

    p
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final q in _ps) {
      final len = q.vx * g * 0.035;
      p
        ..strokeWidth = q.size
        ..color = _sand(q.tone, q.a * g);
      c.drawLine(Offset(q.x, q.y), Offset(q.x - len * spec.wind, q.y - len * q.vy / q.vx), p);
    }
    p.style = PaintingStyle.fill;
  }
}

/// Туман: крупные мягкие пятна медленно ползут понизу кадра.
class _Fog extends _System {
  _Fog(super.spec, super.rnd);

  final _blobs = <_P>[];
  late Paint _blob;

  @override
  void reset(Size s) {
    final n = (7 * spec.density).round().clamp(3, 14);
    _blobs
      ..clear()
      ..addAll(List.generate(n, (_) {
        return _P(r(-0.3, 1.3) * s.width, r(0.35, 1.0) * s.height)
          ..vx = r(6, 18) * (spec.wind >= 0 ? 1 : -1)
          ..size = r(0.75, 1.25)
          ..a = r(0.5, 1)
          ..phase = r(0, 6.28);
      }));
    // Один градиент на все пятна: центр в нуле, двигаем холстом.
    final rad = s.width * 0.55;
    _blob = Paint()
      ..shader = ui.Gradient.radial(Offset.zero, rad, const [
        Color(0x70E6EEF5),
        Color(0x30E6EEF5),
        Color(0x00E6EEF5),
      ], const [0, 0.55, 1]);
  }

  @override
  void update(double dt, double t, Size s) {
    final rad = s.width * 0.55;
    for (final b in _blobs) {
      b.x += b.vx * dt;
      if (b.vx > 0 && b.x - rad * b.size > s.width) b.x = -rad * b.size;
      if (b.vx < 0 && b.x + rad * b.size < 0) b.x = s.width + rad * b.size;
    }
  }

  @override
  void paint(Canvas c, Size s, double t) {
    for (final b in _blobs) {
      final breathe = 0.75 + 0.25 * math.sin(t * 0.2 + b.phase);
      c.save();
      c.translate(b.x, b.y + math.sin(t * 0.15 + b.phase) * 10);
      c.scale(b.size * 1.6, b.size * 0.7); // приплюснутые, стелются
      c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, b.a * breathe));
      c.drawCircle(Offset.zero, s.width * 0.55, _blob);
      c.restore();
      c.restore();
    }
  }
}

/// Снег: крупные хлопья ближе и быстрее, мелкие дальше и медленнее.
class _Snow extends _System {
  _Snow(super.spec, super.rnd);

  final _ps = <_P>[];

  @override
  void reset(Size s) {
    _ps
      ..clear()
      ..addAll(List.generate(count(s, 90), (_) {
        final z = r(0, 1);
        return _P(r(0, s.width), r(0, s.height))
          ..size = 0.8 + z * 2.4
          ..vy = 25 + z * 70
          ..vx = r(8, 25) * spec.wind
          ..a = 0.35 + z * 0.55
          ..phase = r(0, 6.28);
      }));
  }

  @override
  void update(double dt, double t, Size s) {
    for (final q in _ps) {
      q.x += (q.vx + math.sin(t * 1.1 + q.phase) * 12) * dt;
      q.y += q.vy * dt;
      _wrap(q, s, 6);
    }
  }

  @override
  void paint(Canvas c, Size s, double t) {
    for (final q in _ps) {
      p.color = Color.fromRGBO(255, 255, 255, q.a);
      c.drawCircle(Offset(q.x, q.y), q.size, p);
    }
  }
}

/// Искры костра: вылетают из точки (x, y), поднимаются, кружатся и гаснут.
class _Embers extends _System {
  _Embers(super.spec, super.rnd);

  final _ps = <_P>[];
  double _acc = 0;

  // Слой искр едет вместе с картинкой и меняет размер каждый кадр,
  // поэтому частицы при этом не сбрасываются, а свечение рисуется
  // единичным градиентом и масштабируется холстом.
  final _glow = Paint()
    ..blendMode = BlendMode.plus
    ..shader = ui.Gradient.radial(Offset.zero, 1, const [
      Color(0x80FFB050),
      Color(0x00FF7020),
    ]);

  @override
  void reset(Size s) {}

  @override
  void update(double dt, double t, Size s) {
    final ox = spec.x * s.width, oy = spec.y * s.height;
    _acc += dt * 22 * spec.density;
    while (_acc >= 1) {
      _acc -= 1;
      _ps.add(_P(ox + r(-1, 1) * s.width * 0.025, oy - r(0, 6))
        ..vx = r(-18, 18)
        ..vy = -r(45, 120)
        ..size = r(1.0, 2.4)
        ..life = r(1.0, 2.6)
        ..phase = r(0, 6.28));
    }
    for (final q in _ps) {
      q.age += dt;
      q.vx += math.sin(t * 3 + q.phase) * 40 * dt;
      q.vy *= 1 - 0.35 * dt;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
    }
    _ps.removeWhere((q) => q.age >= q.life);
  }

  @override
  void paint(Canvas c, Size s, double t) {
    final flick = 0.8 + 0.12 * math.sin(t * 9.1) + 0.08 * math.sin(t * 23.7 + 1);
    c.save();
    c.translate(spec.x * s.width, spec.y * s.height);
    c.scale(flick * s.width * 0.1);
    c.drawCircle(Offset.zero, 1, _glow);
    c.restore();

    p.blendMode = BlendMode.plus;
    for (final q in _ps) {
      final k = q.age / q.life; // 0 — только вылетела, 1 — погасла
      final fade = (1 - k) * (0.7 + 0.3 * math.sin(t * 20 + q.phase));
      p.color = Color.fromRGBO(255, (220 - 140 * k).round(), (110 - 90 * k).round(), fade.clamp(0, 1));
      c.drawCircle(Offset(q.x, q.y), q.size * (1 - 0.4 * k), p);
    }
    p.blendMode = BlendMode.srcOver;
  }
}

/// Отсвет огня: тёплое пятно и «дышащие» тени — мерцание на лицах.
class _Firelight extends _System {
  _Firelight(super.spec, super.rnd);

  final _warm = Paint()
    ..blendMode = BlendMode.plus
    ..shader = ui.Gradient.radial(Offset.zero, 1, const [
      Color(0x55FF9A3C),
      Color(0x22FF7A28),
      Color(0x00FF6A20),
    ], const [0, 0.45, 1]);
  final _shade = Paint();

  @override
  void reset(Size s) {}

  @override
  void update(double dt, double t, Size s) {}

  @override
  void paint(Canvas c, Size s, double t) {
    // Сумма несоизмеримых синусов — без заметного периода, как живой огонь.
    final f = 0.72 +
        0.14 * math.sin(t * 6.3) +
        0.09 * math.sin(t * 11.7 + 0.8) +
        0.05 * math.sin(t * 23.1 + 2.1);
    final rad = s.width * (spec.radius ?? 0.6);

    _shade.color = Color.fromRGBO(10, 4, 0, ((1 - f) * 0.35).clamp(0, 1));
    c.drawRect(Offset.zero & s, _shade);

    c.save();
    c.translate(spec.x * s.width + math.sin(t * 2.3) * rad * 0.02, spec.y * s.height);
    c.scale((0.92 + 0.12 * f) * rad);
    c.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, f.clamp(0, 1)));
    c.drawCircle(Offset.zero, 1, _warm);
    c.restore();
    c.restore();
  }
}

// ---------------------------------------------------------------------------

class _P {
  _P(this.x, this.y);
  double x, y;
  double vx = 0, vy = 0;
  double size = 1, a = 1, phase = 0;
  double tone = 0; // оттенок песка: 0 — светлое золото, 1 — тёмная охра
  double age = 0, life = 1;
}

/// Цвет песчинки: от светлого золота к тёмной охре.
Color _sand(double tone, double alpha) => Color.fromRGBO(
      (232 - 62 * tone).round(),
      (192 - 70 * tone).round(),
      (118 - 58 * tone).round(),
      alpha.clamp(0, 1).toDouble(),
    );

void _wrap(_P q, Size s, double m) {
  if (q.x > s.width + m) q.x = -m;
  if (q.x < -m) q.x = s.width + m;
  if (q.y > s.height + m) q.y = -m;
  if (q.y < -m) q.y = s.height + m;
}
