import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Небо шапки: светлый градиент с солнцем у горизонта.
class SkyHeader extends StatelessWidget {
  const SkyHeader({super.key, required this.height, required this.child, this.sun = false, this.sunRise = .5});
  final double height; final Widget child; final bool sun; final double sunRise;
  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.skyTop, C.skyMid, C.skyWarm], stops: [0, .58, 1])),
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          if (sun)
            Positioned(
              left: 0, right: 0, bottom: -70 + 60 * sunRise,
              child: Center(
                child: Container(
                  width: 150, height: 150,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFFF6D77A), C.goldBright, Color(0x00F1C453)], stops: [0, .5, .72])),
                ),
              ),
            ),
          child,
        ]),
      );
}

/// Карточка на «земле».
class GroundCard extends StatelessWidget {
  const GroundCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.outlined = false, this.dim = false});
  final Widget child; final EdgeInsets padding; final VoidCallback? onTap; final bool outlined; final bool dim;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? .7 : 1,
        child: Material(
          color: outlined ? Colors.transparent : C.card,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              padding: padding,
              decoration: outlined ? BoxDecoration(border: Border.all(color: C.cardHigh), borderRadius: BorderRadius.circular(14)) : null,
              child: child,
            ),
          ),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text; final String? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(text, style: st(15, w: 600))),
          if (trailing != null) Text(trailing!, style: st(12, color: C.inkSoft)),
        ]),
      );
}

class Bar extends StatelessWidget {
  const Bar(this.value, {super.key, this.height = 4});
  final double value; final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: height, backgroundColor: C.ground, color: C.gold),
      );
}

class Chevron extends StatelessWidget {
  const Chevron({super.key});
  @override
  Widget build(BuildContext context) => const Icon(Icons.chevron_right_rounded, size: 20, color: C.inkFaint);
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.gold = false});
  final String text; final bool gold;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: gold ? C.gold : C.ground, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: st(12, w: gold ? 600 : 400, color: gold ? C.ground : const Color(0xFFE8D9BD))),
      );
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.glow = false});
  final Color color; final bool glow;
  @override
  Widget build(BuildContext context) => Container(
        width: 12, height: 12,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: .18), spreadRadius: 4)] : null),
      );
}

/// Картинка с CDN с тихой заглушкой.
class NetArt extends StatelessWidget {
  const NetArt({super.key, required this.url, this.fit = BoxFit.cover, this.alignment = Alignment.center, this.fallback, this.width, this.height});
  final String url; final BoxFit fit; final Alignment alignment; final Widget? fallback; final double? width; final double? height;
  @override
  Widget build(BuildContext context) {
    final fb = fallback ?? Container(color: C.cardHigh, width: width, height: height);
    return Image.network(
      url, fit: fit, alignment: alignment, width: width, height: height, gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fb,
      loadingBuilder: (_, child, p) => p == null ? child : fb,
    );
  }
}
