import 'package:flutter/material.dart';
import 'core/services.dart';
import 'core/theme.dart';
import 'features/shell/app_shell.dart';
import 'widgets/art.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tuneImageCache();
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
          theme: buildTheme(),
          home: AppShell(services: services),
        ),
      );
}
