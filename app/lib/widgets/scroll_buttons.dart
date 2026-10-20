import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Кнопки ↑ / ↓ для прокрутки — для тех, кому свайп неудобен (пожилые игроки, первый раз со смартфоном).
///
/// Оборачивает экран со списком: вложенный вертикальный ListView без своего контроллера
/// подхватывает наш через [PrimaryScrollController]. Кнопки видны, только если есть куда листать;
/// одно нажатие — примерно экран (80 % высоты), чтобы строка с края не терялась.
class ScrollButtons extends StatefulWidget {
  const ScrollButtons({super.key, required this.child});
  final Widget child;
  @override
  State<ScrollButtons> createState() => _ScrollButtonsState();
}

class _ScrollButtonsState extends State<ScrollButtons> {
  // keepScrollOffset: false — новый экран на том же месте не должен начинаться с чужой позиции
  final _c = ScrollController(keepScrollOffset: false);
  bool _up = false, _down = false;

  void _sync() {
    if (!_c.hasClients || _c.positions.length != 1) return;
    final p = _c.position;
    if (!p.hasContentDimensions) return;
    final up = p.pixels > p.minScrollExtent + 4;
    final down = p.pixels < p.maxScrollExtent - 4;
    if (up != _up || down != _down) setState(() { _up = up; _down = down; });
  }

  void _page(int dir) {
    if (!_c.hasClients || _c.positions.length != 1) return;
    final p = _c.position;
    final to = (p.pixels + dir * p.viewportDimension * .8).clamp(p.minScrollExtent, p.maxScrollExtent);
    _c.animateTo(to, duration: Duration(milliseconds: math.min(450, 250 + (to - p.pixels).abs() ~/ 4)), curve: Curves.easeInOut);
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _sync(); });
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
        // список дорос до прокрутки (данные пришли, картинка загрузилась) — пересчитать кнопки
        onNotification: (_) { WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _sync(); }); return false; },
        child: Stack(children: [
          PrimaryScrollController(
            controller: _c,
            // по умолчанию Flutter отдаёт primary-контроллер только на iOS/Android; в браузере на компьютере тоже нужен
            automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
            child: widget.child,
          ),
          Positioned(right: 12, bottom: 12, child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_up) _Btn(icon: Icons.keyboard_arrow_up_rounded, label: 'up', onTap: () => _page(-1)),
            if (_up && _down) const SizedBox(height: 10),
            if (_down) _Btn(icon: Icons.keyboard_arrow_down_rounded, label: 'down', onTap: () => _page(1)),
          ])),
        ]),
      );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: label,
        child: Material(
          color: C.groundDeep.withValues(alpha: .92),
          shape: const CircleBorder(side: BorderSide(color: C.gold, width: 1.5)),
          elevation: 3,
          child: InkWell(
            key: ValueKey('scroll-$label'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 52, height: 52, child: Icon(icon, color: C.gold, size: 32)),
          ),
        ),
      );
}
