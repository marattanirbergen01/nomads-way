import 'package:flutter/material.dart';
import 'core/locale_controller.dart';
import 'features/home/home_screen.dart';

void main() => runApp(NomadsWayApp(locale: LocaleController()));

class NomadsWayApp extends StatelessWidget {
  const NomadsWayApp({super.key, required this.locale});
  final LocaleController locale;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: locale,
        builder: (_, __) => MaterialApp(
          title: "Nomad's Way",
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF14615F), brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF58B7B0), brightness: Brightness.dark),
            useMaterial3: true,
          ),
          home: HomeScreen(locale: locale),
        ),
      );
}
