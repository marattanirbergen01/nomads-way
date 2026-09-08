import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';

enum MenuAction { resume, restart, saveExit, transcript, sources, toggleLang, toggleSound, cycleSpeed }

/// Меню паузы (три линии): где ты сейчас и действия. Возвращает выбранное действие.
Future<MenuAction?> showSceneMenu(BuildContext context, Services sv, {
  required String episodeTitle, required String? sceneTitle, required String era,
  required int sceneIndex, required int sceneCount, required int sourcesCount,
}) {
  final s = sv.s;
  return showModalBottomSheet<MenuAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Widget row(String label, IconData icon, String value, MenuAction a) => InkWell(
            onTap: () => Navigator.pop(ctx, a),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x735A4A3B)))),
              child: Row(children: [
                Icon(icon, size: 22, color: C.gold), const SizedBox(width: 14),
                Expanded(child: Text(label, style: st(15.5))),
                Text(value, style: st(13, color: C.inkSoft)),
              ]),
            ),
          );
      final speed = [s('speed.slow'), s('speed.mid'), s('speed.fast')][sv.store.textSpeed.clamp(0, 2)];
      final pct = sceneCount == 0 ? 0 : (sceneIndex * 100 / sceneCount).round();
      return Container(
        decoration: const BoxDecoration(color: Color(0xF21A140F), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: C.cardHigh, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Text(s('menu'), style: st(15, w: 600)),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s('now.reading'), style: st(11, w: 600, color: C.gold, spacing: 1.1)),
              const SizedBox(height: 4),
              Text(sceneTitle == null ? episodeTitle : '$episodeTitle · $sceneTitle', style: st(17, w: 600)),
              const SizedBox(height: 3),
              Text('$era · ${sceneIndex + 1}-${s('scene.of')} / $sceneCount · $pct%', style: st(12.5, color: C.inkSoft)),
            ]),
          ),
          const SizedBox(height: 8),
          row(s('transcript'), Icons.notes_rounded, '', MenuAction.transcript),
          row(s('text.speed'), Icons.schedule_rounded, speed, MenuAction.cycleSpeed),
          row(s('sound'), Icons.volume_up_outlined, sv.store.sound ? s('on') : s('off'), MenuAction.toggleSound),
          row(s('lang'), Icons.language_rounded, sv.l.toUpperCase(), MenuAction.toggleLang),
          row(s('sources'), Icons.description_outlined, '$sourcesCount', MenuAction.sources),
          row(s('restart.ep'), Icons.replay_rounded, '', MenuAction.restart),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: GoldButton(label: s('save.exit'), height: 52, onTap: () => Navigator.pop(ctx, MenuAction.saveExit))),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 52,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF5A4A3B)), shape: const StadiumBorder()),
              onPressed: () => Navigator.pop(ctx, MenuAction.resume),
              child: Text(s('keep.reading'), style: st(16, w: 600, color: const Color(0xFFE8D9BD))),
            ),
          ),
        ]),
      );
    }),
  );
}
