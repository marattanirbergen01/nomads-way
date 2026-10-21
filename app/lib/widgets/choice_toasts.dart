import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../data/models/episode.dart';

/// Плашки после выбора: «+2 Батылдық», «Бекет мұны ұмытпайды» — стопкой вверху экрана.
///
/// Движение — по эталону сессии «Анимация» (content/media/s1/app/toasts/toast_motion_spec.md,
/// исходник motion/toasts/toasts.js): все тайминги и кривые оттуда без изменений.
/// Плашки не перехватывают тапы: игрок продолжает листать ответ.
class ChoiceToasts extends StatefulWidget {
  const ChoiceToasts({super.key, required this.toasts, required this.locale, this.onAccent, this.onDone});
  final List<ChoiceToast> toasts;
  final String locale;
  /// Начало акцента плашки i (для звука).
  final void Function(ChoiceToast toast)? onAccent;
  final VoidCallback? onDone;

  /// Вся жизнь стопки из n плашек, мс: последний выход заканчивается в (n−1)·250 + 2000 + (n−1)·80 + 400.
  static int lifeMs(int n) => (n - 1) * 250 + 2000 + (n - 1) * 80 + 400;

  @override
  State<ChoiceToasts> createState() => _ChoiceToastsState();
}

// ---- тайминги и кривые эталона
const _stepIn = 250, _gap = 8.0, _h = 52.0, _hold = 2000, _exitStep = 80, _exitDur = 400;
const _back = Cubic(0.34, 1.56, 0.64, 1);
const _ease = Cubic(0.25, 0.1, 0.25, 1);
const _plusUp = Cubic(0.33, 0, 0.2, 1);
const _plusDown = Cubic(0.4, 0, 0.2, 1);
const _shine = Cubic(0.45, 0, 0.25, 1);
const _pulse = Cubic(0.2, 0, 0.2, 1);
const _exit = Cubic(0.42, 0, 1, 1);

double _phase(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _ChoiceToastsState extends State<ChoiceToasts> with SingleTickerProviderStateMixin {
  late final int _n = math.min(widget.toasts.length, 3);
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: ChoiceToasts.lifeMs(_n)));
  final _accented = <int>{};

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final t = _c.value * ChoiceToasts.lifeMs(_n);
      for (var i = 0; i < _n; i++) {
        if (t >= i * _stepIn + 320 && _accented.add(i)) widget.onAccent?.call(widget.toasts[i]);
      }
    });
    _c.forward().whenComplete(() => widget.onDone?.call());
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final top = MediaQuery.of(context).padding.top + 12;
    return IgnorePointer(child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * ChoiceToasts.lifeMs(_n);
        return Stack(children: [
          for (var i = 0; i < _n; i++)
            Positioned(
              left: 16, right: 16, top: top + i * (_h + _gap), height: _h,
              child: _Plaque(
                toast: widget.toasts[i], locale: widget.locale, reduce: reduce,
                t: t - i * _stepIn,
                exitAt: ((_n - 1) * _stepIn + _hold + (_n - 1 - i) * _exitStep - i * _stepIn).toDouble(),
                life: t,
              ),
            ),
        ]);
      },
    ));
  }
}

class _Plaque extends StatelessWidget {
  const _Plaque({required this.toast, required this.locale, required this.t, required this.exitAt, required this.life, required this.reduce});
  final ChoiceToast toast; final String locale;
  /// Время от появления этой плашки, мс (может быть < 0 — ещё не вышла).
  final double t;
  /// Начало выхода, мс от появления этой плашки.
  final double exitAt;
  /// Время стопки — для дрейфа дымки.
  final double life;
  final bool reduce;

  static const _gold = Color(0xFFF1C453), _ember = Color(0xFFE08A4C), _emberHot = Color(0xFFF4AC70);
  static const _ink = Color(0xFFF4ECDF), _iconFill = Color(0xFF2F241B);

  @override
  Widget build(BuildContext context) {
    if (t < 0) return const SizedBox.shrink();
    final trait = toast.kind == ToastKind.trait;
    final ring = trait ? _gold : _ember;

    // вход / выход
    final pIn = _phase(t, 0, 320), pOp = _phase(t, 0, 220), pEx = _phase(t, exitAt, exitAt + _exitDur);
    var dy = reduce ? 0.0 : -16 * (1 - _back.transform(pIn));
    var op = _ease.transform(pOp);
    if (pEx > 0) { final e = _exit.transform(pEx); dy += reduce ? 0 : -12 * e; op *= 1 - e; }
    if (op <= 0) return const SizedBox.shrink();

    // иконка
    final pIcon = _phase(t, 80, 320);
    final iconScale = reduce ? 1.0 : 0.6 + 0.4 * _back.transform(pIcon);
    final iconOp = _ease.transform(_phase(t, 80, 238));

    // акцент
    var plus = 1.0; double shineX = -1, shineA = 0; double pulseR = 18, pulseA = 0; var ringColor = ring;
    if (!reduce && trait) {
      if (t >= 320 && t < 470) plus = 1 + .15 * _plusUp.transform(_phase(t, 320, 470));
      if (t >= 470 && t < 700) plus = 1.15 - .15 * _plusDown.transform(_phase(t, 470, 700));
      if (t >= 340 && t <= 700) {
        final pl = _phase(t, 340, 700);
        shineX = _shine.transform(pl);
        shineA = .30 * math.sin(math.pi * pl);
      }
    } else if (!reduce && t >= 320 && t <= 700) {
      final pl = _phase(t, 320, 700), pc = _pulse.transform(pl);
      pulseR = 18 + 8 * pc; pulseA = .6 * (1 - pc);
      ringColor = Color.lerp(ring, _emberHot, math.sin(math.pi * pl))!;
    }
    final drift = reduce ? 0.0 : 3 * math.sin(2 * math.pi * life / 4000);

    final text = toast.text.of(locale);
    final label = trait
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.scale(scale: plus, child: Text('+${toast.n}', style: st(17, w: 700, color: _gold))),
            const SizedBox(width: 6),
            Text(text, style: st(17, w: 500, color: _ink), maxLines: 1),
          ])
        : Text(text, style: st(17, w: 500, color: _ink), maxLines: 1);

    return Opacity(
      opacity: op,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 16, offset: Offset(0, 6))]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth;
                return Stack(clipBehavior: Clip.hardEdge, children: [
                  const Positioned.fill(child: ColoredBox(color: Color(0xD122190F))),
                  // дымка по краям: слева как есть, справа отражённая, дрейф в противофазе
                  Positioned(left: -0.38 * 140 + drift, top: (_h - 80) / 2, width: 140, height: 80,
                      child: Opacity(opacity: .75, child: Image.asset('assets/toasts/toast_haze.png', fit: BoxFit.fill))),
                  Positioned(right: -0.38 * 140 - drift, top: (_h - 80) / 2, width: 140, height: 80,
                      child: Opacity(opacity: .75, child: Transform.flip(flipX: true, child: Image.asset('assets/toasts/toast_haze.png', fit: BoxFit.fill)))),
                  // блик у черты: полоса 56 pt с наклоном, проходит слева направо один раз
                  if (shineA > 0)
                    Positioned(left: -56 + shineX * (w + 11 + 56), top: 0, bottom: 0, width: 56,
                        child: Transform(transform: Matrix4.skewX(-0.36), alignment: Alignment.center,
                            child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [
                              _gold.withValues(alpha: 0), _gold.withValues(alpha: shineA), _gold.withValues(alpha: 0)]))))),
                  // иконка: круг 36 в кольце 1,5; пока нет картинок — первая буква
                  Positioned(left: 8, top: (_h - 36) / 2, width: 36, height: 36, child: Opacity(opacity: iconOp, child: Transform.scale(
                    scale: iconScale,
                    child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                      if (pulseA > 0)
                        Container(width: pulseR * 2, height: pulseR * 2, decoration: BoxDecoration(shape: BoxShape.circle,
                            border: Border.all(color: _ember.withValues(alpha: pulseA), width: 1.5))),
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: _iconFill, border: Border.all(color: ringColor, width: 1.5)),
                        alignment: Alignment.center,
                        child: Text(text.isEmpty ? '' : text.characters.first.toUpperCase(), style: st(16, w: 600, color: ringColor)),
                      ),
                    ]),
                  ))),
                  // текст по центру зоны от 54 до правого края − 12; не влезает в 17 — ужимается
                  Positioned(left: 54, right: 12, top: 0, bottom: 0, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: label))),
                  // край
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x14F4ECDF))))),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}
