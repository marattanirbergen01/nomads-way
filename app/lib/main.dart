import 'package:flutter/material.dart';
import 'core/services.dart';
import 'features/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await Services.boot();
  runApp(NomadsWayApp(services: services));
}

class NomadsWayApp extends StatelessWidget {
  const NomadsWayApp({super.key, required this.services});
  final Services services;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: services.locale,
        builder: (_, __) => MaterialApp(
          title: "Nomad's Way",
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF14615F)), useMaterial3: true),
          darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF58B7B0), brightness: Brightness.dark), useMaterial3: true),
          home: HomeScreen(services: services),
        ),
      );
}
