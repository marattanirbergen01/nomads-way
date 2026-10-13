import 'package:flutter/material.dart';

/// Мир «Степь и горизонт»: тёмная земля, золотой горизонт, светлое небо в шапках.
/// Приложение живёт в одной теме — это выбранный мир, а не режим системы.
abstract final class C {
  static const ground = Color(0xFF2A2019);   // земля
  static const groundDeep = Color(0xFF22190F);
  static const card = Color(0xFF362A21);
  static const cardHigh = Color(0xFF43352A);
  static const line = Color(0xFF3A2D21);
  static const lineSoft = Color(0xFF362A21);
  static const ink = Color(0xFFF4ECDF);      // текст
  static const inkSoft = Color(0xFFB8A68F);
  static const inkFaint = Color(0xFF9D8C75);
  static const gold = Color(0xFFD9A441);     // горизонт
  static const goldBright = Color(0xFFF1C453);
  static const goldDim = Color(0xFF57472F);  // приглушённый таймер
  static const goldDark = Color(0xFF8E6E1E);
  static const ember = Color(0xFFE08A4C);    // тёплое предупреждение
  // Верно/неверно в ответах: золото и ember слишком близки — нужны разные тона, не только яркость.
  static const right = Color(0xFF5DBB78);    // верный ответ
  static const wrong = Color(0xFFE5584F);    // неверный ответ
  static const locked = Color(0xFF6B7D97);   // закрытые периоды
  static const skyTop = Color(0xFFB9CBD9);   // небо шапок
  static const skyMid = Color(0xFFD9DDD7);
  static const skyWarm = Color(0xFFE8DEC8);
  static const onSky = Color(0xFF2A2019);
  static const onSkySoft = Color(0xFF5A4A3B);
}

TextStyle st(double size, {double w = 400, Color color = C.ink, double? height, double? spacing}) =>
    TextStyle(
      fontFamily: 'Golos',
      fontSize: size,
      color: color,
      height: height,
      letterSpacing: spacing,
      fontVariations: [FontVariation('wght', w)],
    );

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: C.ground,
    fontFamily: 'Golos',
    colorScheme: const ColorScheme.dark(
      surface: C.ground,
      primary: C.gold,
      onPrimary: C.ground,
      secondary: C.goldBright,
      error: C.ember,
      onSurface: C.ink,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink, fontFamily: 'Golos'),
    dividerColor: C.line,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.cardHigh,
      contentTextStyle: st(14, color: C.ink),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Золотая кнопка-пилюля из макетов.
class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, this.onTap, this.trailingArrow = false, this.height = 48});
  final String label;
  final VoidCallback? onTap;
  final bool trailingArrow;
  final double height;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Material(
          color: C.gold,
          borderRadius: BorderRadius.circular(height / 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onTap,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: st(15, w: 700, color: C.ground)),
                if (trailingArrow) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: C.ground),
                ],
              ]),
            ),
          ),
        ),
      );
}
