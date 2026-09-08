import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../engine/awards.dart';
import 'awards_meta.dart';

/// Награда всплывает на весь экран со свечением.
class AwardScreen extends StatelessWidget {
  const AwardScreen({super.key, required this.award, required this.count, required this.services});
  final Award award; final int count; final Services services;

  static Future<void> show(BuildContext context, Services s, Award a, int count) =>
      Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => AwardScreen(award: a, count: count, services: s),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)), child: child)),
      ));

  @override
  Widget build(BuildContext context) {
    final s = services.s; final l = services.l; final m = awardMeta[award]!;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1410),
      body: Stack(children: [
        Positioned(
          left: -115, right: -115, top: 300 - 310,
          child: Container(height: 620, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x57F1C453), Color(0x1FF1C453), Color(0x00F1C453)], stops: [0, .38, .66]))),
        ),
        SafeArea(
          child: Column(children: [
            const SizedBox(height: 56),
            Text(s('award.new'), style: st(12, w: 700, color: C.gold, spacing: 2.6)),
            const SizedBox(height: 60),
            Medal(award: award, size: 188),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(children: [
                Text(m.name(l).toUpperCase(), style: st(36, w: 800, spacing: 1.4), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(m.desc(l), style: st(16, color: const Color(0xFFE8D9BD), height: 1.45), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: C.goldDark), borderRadius: BorderRadius.circular(999)),
                  child: Text(s('award.n').replaceFirst('{n}', '$count'), style: st(13, w: 600, color: C.gold)),
                ),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
              child: SizedBox(width: double.infinity, child: GoldButton(label: s('award.ok'), height: 52, onTap: () => Navigator.of(context).pop())),
            ),
          ]),
        ),
      ]),
    );
  }
}
