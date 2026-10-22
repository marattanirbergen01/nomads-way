// ДЕМО (ветка experiment/minigames): запускалка мини-игр из настоящей сборки. В main не идёт.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'core/theme.dart';
import 'data/models/episode.dart';
import 'engine/games/game_spec.dart';
import 'features/games/game_screen.dart';

const _cdn = String.fromEnvironment('CDN_URL', defaultValue: 'http://localhost:8793');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final items = <(GameSpec, String)>[];
  for (final ep in ['s1e01', 's1e02']) {
    final e = Episode.fromJson(jsonDecode(utf8.decode((await http.get(Uri.parse('$_cdn/$ep/episode.json'))).bodyBytes)));
    for (final s in e.scenes) {
      for (final g in s.games) {
        final lang = e.motionLang(s.art, 'kk');
        final art = g.art ?? s.art;   // своя картинка игры («чистая» карта, схема поля) или кадр сцены
        final l = g.art == null ? lang : null;
        items.add((g, l == null ? '$_cdn/media/s1/$art.${e.mediaExt[art] ?? 'jpg'}' : '$_cdn/media/s1/${e.motionPoster(art, l)}'));
      }
    }
  }
  runApp(MaterialApp(home: Scaffold(backgroundColor: C.ground, body: SafeArea(child: Builder(builder: (ctx) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('Мини-ойындар (демо)', style: st(22, w: 700)),
    const SizedBox(height: 12),
    for (final (g, art) in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: GoldButton(
      label: g.title.of('kk'),
      onTap: () async {
        final o = await GameScreen.play(ctx, g, 'kk', artUrl: art);
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${g.id}: ${o.name}')));
      },
    )),
  ]))))));
}
