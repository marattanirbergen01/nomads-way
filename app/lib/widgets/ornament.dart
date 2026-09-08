import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Қошқар мүйіз — орнамент-полоса. [progress] закрашивает часть золотом; 1.0 — целиком.
class OrnamentLine extends StatelessWidget {
  const OrnamentLine({super.key, this.progress = 1.0, this.height = 16});
  final double progress;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _OrnamentPainter(progress.clamp(0, 1))),
      );
}

class _OrnamentPainter extends CustomPainter {
  _OrnamentPainter(this.progress);
  final double progress;
  static const _unit = 48.0;

  Path _unitPath() {
    final p = Path();
    p.moveTo(0, 8); p.lineTo(11, 8);
    p.moveTo(11, 8); p.cubicTo(11, 2, 20, 2, 20, 8.5); p.cubicTo(20, 12.5, 14.5, 12.5, 14.5, 8.5); p.cubicTo(14.5, 6.5, 17.3, 6.5, 17.3, 8.5);
    p.moveTo(37, 8); p.cubicTo(37, 2, 28, 2, 28, 8.5); p.cubicTo(28, 12.5, 33.5, 12.5, 33.5, 8.5); p.cubicTo(33.5, 6.5, 30.7, 6.5, 30.7, 8.5);
    p.moveTo(37, 8); p.lineTo(48, 8);
    return p;
  }

  void _row(Canvas c, Size s, Paint paint, double until) {
    final unit = _unitPath();
    final scale = s.height / 16;
    for (double x = 0; x < until; x += _unit * scale) {
      c.save();
      c.translate(x, 0);
      c.scale(scale);
      c.drawPath(unit, paint);
      c.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = const Color(0xFF5A4A3B)..style = PaintingStyle.stroke..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    final gold = Paint()..color = C.gold..style = PaintingStyle.stroke..strokeWidth = 1.6..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _row(canvas, size, dim, size.width);
    if (progress > 0) {
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      _row(canvas, size, gold, size.width);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrnamentPainter o) => o.progress != progress;
}

/// Ровная золотая линия горизонта для экранов вне сюжета.
class HorizonLine extends StatelessWidget {
  const HorizonLine({super.key});
  @override
  Widget build(BuildContext context) => Container(height: 2, color: C.gold);
}
