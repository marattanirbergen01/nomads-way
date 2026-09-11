import 'package:flutter/material.dart';
import '../core/services.dart';
import 'art.dart';

/// Портрет в кружке: настоящий кадр из общего пакета; пока его нет — силуэт.
class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.size, this.look = 1, this.ring = false, this.services, this.emo = 'calm'});
  final double size;
  final int look;
  final bool ring;
  final Services? services;
  final String emo;
  @override
  Widget build(BuildContext context) {
    final a = services?.content.commonSync?.byLook(look);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF43352A),
        border: ring ? Border.all(color: const Color(0xFFD9A441), width: size > 60 ? 3 : 2) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: a == null
          ? CustomPaint(painter: _HeadPainter(look))
          : Art(
              url: services!.content.avatarUrl(a, a.face(emo)), file: services!.content.avatarFile(a, a.face(emo)),
              fit: BoxFit.cover, alignment: a.circleAlignment(), width: size, height: size, logicalWidth: size,
              fallback: CustomPaint(painter: _HeadPainter(look), size: Size(size, size)),
            ),
    );
  }
}

/// Фигура по пояс поверх сцены. Настоящий кадр с прозрачным фоном; пока его нет — силуэт.
class AvatarBust extends StatelessWidget {
  const AvatarBust({super.key, this.look = 1, this.mirror = false, this.services, this.emo = 'calm'});
  final int look;
  final bool mirror;
  final Services? services;
  final String emo;
  @override
  Widget build(BuildContext context) {
    final a = services?.content.commonSync?.byLook(look);
    final child = a == null
        ? CustomPaint(painter: _BustPainter(look))
        : Art(
            url: services!.content.avatarUrl(a, a.bust(emo)), file: services!.content.avatarFile(a, a.bust(emo)),
            fit: BoxFit.contain, logicalWidth: 300,
            fallback: CustomPaint(painter: _BustPainter(look)),
          );
    return Transform.flip(flipX: mirror, child: Align(alignment: Alignment.topCenter, child: child));
  }
}

Color _chapan(int look) => switch (look) { 2 => const Color(0xFF5B4A3B), 3 => const Color(0xFF4E4A63), _ => const Color(0xFF4E5F4E) };
Color _chapanDark(int look) => switch (look) { 2 => const Color(0xFF4B3D31), 3 => const Color(0xFF423F55), _ => const Color(0xFF445443) };

class _HeadPainter extends CustomPainter {
  _HeadPainter(this.look);
  final int look;
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 64;
    c.drawCircle(Offset(32 * k, 26 * k), 11 * k, Paint()..color = const Color(0xFF9D8C75));
    final shoulders = Path()..moveTo(12 * k, 56 * k)..arcToPoint(Offset(52 * k, 56 * k), radius: Radius.circular(20 * k))..lineTo(52 * k, 64 * k)..lineTo(12 * k, 64 * k)..close();
    c.drawPath(shoulders, Paint()..color = _chapan(look).withValues(alpha: .9));
  }
  @override
  bool shouldRepaint(_HeadPainter o) => o.look != look;
}

class _BustPainter extends CustomPainter {
  _BustPainter(this.look);
  final int look;
  @override
  void paint(Canvas c, Size s) {
    // исходник рисован в 220×330
    final k = s.width / 220;
    final kh = s.height / 330;
    c.save();
    c.scale(k, kh);
    Paint f(Color col) => Paint()..color = col;
    final torso = Path()
      ..moveTo(110, 122)
      ..cubicTo(79, 122, 61, 139, 57, 164)
      ..lineTo(43, 274)
      ..cubicTo(40, 292, 44, 309, 52, 323)
      ..lineTo(55, 383)..lineTo(165, 383)..lineTo(168, 323)
      ..cubicTo(176, 309, 180, 292, 177, 274)
      ..lineTo(163, 164)
      ..cubicTo(159, 139, 141, 122, 110, 122)..close();
    c.drawPath(torso, f(_chapan(look)));
    final armL = Path()..moveTo(57, 148)..cubicTo(47, 157, 42, 169, 40, 182)..lineTo(30, 274)..cubicTo(29, 282, 33, 289, 40, 290)..lineTo(50, 292)..cubicTo(55, 293, 60, 288, 61, 283)..lineTo(75, 179)..close();
    c.drawPath(armL, f(_chapanDark(look)));
    final armR = Path()..moveTo(163, 148)..cubicTo(173, 157, 178, 169, 180, 182)..lineTo(190, 274)..cubicTo(191, 282, 187, 289, 180, 290)..lineTo(170, 292)..cubicTo(165, 293, 160, 288, 159, 283)..lineTo(145, 179)..close();
    c.drawPath(armR, f(_chapanDark(look)));
    c.drawCircle(const Offset(35, 292), 11, f(const Color(0xFFA87F5A)));
    c.drawCircle(const Offset(185, 292), 11, f(const Color(0xFFA87F5A)));
    final collar = Path()..moveTo(92, 124)..lineTo(110, 154)..lineTo(128, 124)..cubicTo(122, 121, 116, 120, 110, 120)..cubicTo(104, 120, 98, 121, 92, 124)..close();
    c.drawPath(collar, f(const Color(0xFF8E6E1E)));
    c.drawLine(const Offset(110, 154), const Offset(110, 330), Paint()..color = const Color(0xFF3E4C3E)..strokeWidth = 3);
    c.drawRect(const Rect.fromLTWH(56, 248, 108, 22), f(const Color(0xFF33281F)));
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(100, 250, 20, 18), const Radius.circular(3)), f(const Color(0xFF8E6E1E)));
    c.drawRect(const Rect.fromLTWH(100, 104, 20, 22), f(const Color(0xFF9C7452)));
    c.drawOval(Rect.fromCenter(center: const Offset(110, 80), width: 56, height: 64), f(const Color(0xFFB78B63)));
    final hat = Path()..moveTo(80, 66)..quadraticBezierTo(80, 24, 110, 24)..quadraticBezierTo(140, 24, 140, 66)..close();
    c.drawPath(hat, f(const Color(0xFF3E3128)));
    final brim = Path()..moveTo(76, 62)..quadraticBezierTo(110, 77, 144, 62)..lineTo(144, 74)..quadraticBezierTo(110, 90, 76, 74)..close();
    c.drawPath(brim, f(const Color(0xFF5A4A3B)));
    c.restore();
  }
  @override
  bool shouldRepaint(_BustPainter o) => o.look != look;
}
