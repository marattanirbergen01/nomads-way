import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../path/path_tab.dart';
import '../profile/profile_tab.dart';
import '../readiness/readiness_tab.dart';
import '../train/train_tab.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.services});
  final Services services;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.services.s;
    final tabs = [
      PathTab(services: widget.services),
      TrainTab(services: widget.services),
      ReadinessTab(services: widget.services),
      ProfileTab(services: widget.services),
    ];
    return Scaffold(
      body: IndexedStack(index: _i, children: tabs),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: C.groundDeep, border: Border(top: BorderSide(color: C.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(children: [
              _Tab(icon: _pathIcon, label: s('tab.path'), active: _i == 0, onTap: () => setState(() => _i = 0)),
              _Tab(icon: _trainIcon, label: s('tab.train'), active: _i == 1, onTap: () => setState(() => _i = 1)),
              _Tab(icon: _readyIcon, label: s('tab.ready'), active: _i == 2, onTap: () => setState(() => _i = 2)),
              _Tab(icon: _profileIcon, label: s('tab.profile'), active: _i == 3, onTap: () => setState(() => _i = 3)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.active, required this.onTap});
  final Widget Function(Color) icon; final String label; final bool active; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = active ? C.gold : C.inkFaint;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 24, height: 24, child: icon(c)),
          const SizedBox(height: 5),
          Text(label, style: st(11, w: active ? 600 : 500, color: c)),
        ]),
      ),
    );
  }
}

// Иконки нарисованы штрихом, как в макетах.
Widget _pathIcon(Color c) => CustomPaint(painter: _StrokePainter(c, (p, k) {
      p.moveTo(3 * k, 21 * k); p.cubicTo(8 * k, 18 * k, 8 * k, 13 * k, 13 * k, 12 * k); p.cubicTo(18 * k, 11 * k, 19 * k, 7 * k, 21 * k, 3 * k);
      p.moveTo(6 * k, 21 * k); p.lineTo(9 * k, 15 * k); p.moveTo(13 * k, 12 * k); p.lineTo(15 * k, 15 * k);
    }));
Widget _trainIcon(Color c) => CustomPaint(painter: _StrokePainter(c, (p, k) {
      p.addOval(Rect.fromCircle(center: Offset(12 * k, 12 * k), radius: 9 * k));
      p.addOval(Rect.fromCircle(center: Offset(12 * k, 12 * k), radius: 5 * k));
      p.addOval(Rect.fromCircle(center: Offset(12 * k, 12 * k), radius: 1.2 * k));
    }));
Widget _readyIcon(Color c) => CustomPaint(painter: _StrokePainter(c, (p, k) {
      p.moveTo(3 * k, 18 * k); p.lineTo(21 * k, 18 * k);
      p.moveTo(7 * k, 18 * k); p.arcToPoint(Offset(17 * k, 18 * k), radius: Radius.circular(5 * k));
      p.moveTo(12 * k, 8 * k); p.lineTo(12 * k, 5 * k);
      p.moveTo(5.6 * k, 11.6 * k); p.lineTo(3.6 * k, 9.6 * k);
      p.moveTo(18.4 * k, 11.6 * k); p.lineTo(20.4 * k, 9.6 * k);
    }));
Widget _profileIcon(Color c) => CustomPaint(painter: _StrokePainter(c, (p, k) {
      p.addOval(Rect.fromCircle(center: Offset(12 * k, 8 * k), radius: 4 * k));
      p.moveTo(4 * k, 21 * k); p.arcToPoint(Offset(20 * k, 21 * k), radius: Radius.circular(8 * k));
    }));

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.color, this.build);
  final Color color;
  final void Function(Path, double) build;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    build(p, size.width / 24);
    canvas.drawPath(p, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.75..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }
  @override
  bool shouldRepaint(_StrokePainter o) => o.color != color;
}
