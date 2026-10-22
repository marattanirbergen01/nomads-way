import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/games/game_spec.dart';
import '../../widgets/art.dart';

/// Мини-игра на весь экран (эксперимент, ветка experiment/minigames).
/// Возвращает исход через Navigator.pop. «Өткізу» — частичный успех: проигрыш сюжет не блокирует.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.spec, required this.locale, this.artUrl, this.artFile});
  final GameSpec spec;
  final String locale;
  /// Фон — кадр сцены (для пути кочевья это сама карта).
  final String? artUrl;
  final File? artFile;

  static Future<GameOutcome> play(BuildContext context, GameSpec spec, String locale, {String? artUrl, File? artFile}) async =>
      await Navigator.of(context).push<GameOutcome>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GameScreen(spec: spec, locale: locale, artUrl: artUrl, artFile: artFile),
      )) ??
      GameOutcome.partial;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  GameOutcome? _result;
  Str get s => Str.of(widget.locale);
  String get l => widget.locale;

  void _finish(GameOutcome o) => setState(() => _result = o);

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final body = switch (spec) {
      RouteSpec r => _RouteView(spec: r, locale: l, onDone: _finish, done: _result != null, artUrl: widget.artUrl, artFile: widget.artFile),
      TradeSpec t => _TradeView(spec: t, locale: l, onDone: _finish, done: _result != null),
      TacticsSpec t => _TacticsView(spec: t, locale: l, onDone: _finish, done: _result != null),
      VolleySpec v => _VolleyView(spec: v, locale: l, onDone: _finish, done: _result != null),
    };
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: C.ground,
        body: Stack(fit: StackFit.expand, children: [
          // фон — приглушённый кадр сцены; у пути кочевья карта рисуется в самом поле игры
          if (spec is! RouteSpec && (widget.artUrl != null || widget.artFile != null))
            Opacity(opacity: .35, child: Art(url: widget.artUrl, file: widget.artFile, width: double.infinity, height: double.infinity)),
          SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(spec.title.of(l).toUpperCase(), style: st(13, w: 700, color: C.gold, spacing: 1.6))),
                  if (_result == null)
                    TextButton(onPressed: () => _finish(GameOutcome.partial), child: Text(s('game.skip'), style: st(14, color: C.inkSoft))),
                ]),
                const SizedBox(height: 4),
                Text(spec.prompt.of(l), style: st(15, height: 1.4).copyWith(shadows: const [Shadow(blurRadius: 6)])),
              ]),
            ),
            Expanded(child: body),
            if (_result != null) _ResultBar(outcome: _result!, spec: spec, locale: l, onNext: () => Navigator.of(context).pop(_result)),
          ])),
        ]),
      ),
    );
  }
}

class _ResultBar extends StatelessWidget {
  const _ResultBar({required this.outcome, required this.spec, required this.locale, required this.onNext});
  final GameOutcome outcome; final GameSpec spec; final String locale; final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final s = Str.of(locale);
    final color = switch (outcome) { GameOutcome.win => C.right, GameOutcome.partial => C.gold, GameOutcome.lose => C.wrong };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(color: Color(0xF2221A14), border: Border(top: BorderSide(color: C.gold, width: 1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(s('game.${outcome.name}'), style: st(22, w: 700, color: color)),
        if (spec.outcome(outcome).reply case final r?) ...[
          const SizedBox(height: 6),
          Text(r.of(locale), style: st(16, height: 1.4)),
        ],
        const SizedBox(height: 12),
        GoldButton(label: s('game.next'), onTap: onNext),
      ]),
    );
  }
}

// ---------------------------------------------------------------- путь кочевья
class _RouteView extends StatefulWidget {
  const _RouteView({required this.spec, required this.locale, required this.onDone, required this.done, this.artUrl, this.artFile});
  final RouteSpec spec; final String locale; final void Function(GameOutcome) onDone; final bool done;
  final String? artUrl; final File? artFile;
  @override
  State<_RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends State<_RouteView> {
  late final RouteGame g = RouteGame(widget.spec);
  /// Карта сцен — 4:7, точки заданы в долях этого кадра.
  static const _aspect = 4 / 7;

  static Color _kindColor(String k) => switch (k) {
        'enemy' => C.wrong, 'river' => const Color(0xFF6FA8C8), 'hill' => const Color(0xFFB08A5A), _ => C.gold,
      };

  @override
  Widget build(BuildContext context) {
    final s = Str.of(widget.locale);
    return Column(children: [
      Expanded(child: Center(child: AspectRatio(aspectRatio: _aspect, child: LayoutBuilder(builder: (context, c) {
        // точки заданы в долях кадра карты; карта и точки в одной рамке 4:7
        final w = c.maxWidth, h = c.maxHeight;
        Offset at(RouteNode n) => Offset(n.x * w, n.y * h);
        return Stack(clipBehavior: Clip.none, children: [
          if (widget.artUrl != null || widget.artFile != null)
            Positioned.fill(child: Art(url: widget.artUrl, file: widget.artFile, fit: BoxFit.fill, width: w, height: h)),
          Positioned.fill(child: CustomPaint(painter: _RoutePainter(g: g, at: at))),
          for (final n in widget.spec.nodes)
            Positioned(
              left: at(n).dx - 22, top: at(n).dy - 22, width: 44, height: 44,
              child: GestureDetector(
                onTap: widget.done ? null : () => setState(() {
                  if (g.go(n.id) && g.finished) widget.onDone(g.outcome);
                }),
                child: _NodeDot(color: _kindColor(n.kind), active: g.path.contains(n.id), reachable: !widget.done && g.canGo(n.id)),
              ),
            ),
          for (final n in widget.spec.nodes)
            Positioned(left: at(n).dx - 70, top: at(n).dy + 18, width: 140,
                child: Text(n.label.of(widget.locale), textAlign: TextAlign.center,
                    style: st(11.5, w: 600, color: C.ink).copyWith(shadows: const [Shadow(blurRadius: 4), Shadow(blurRadius: 8)]))),
        ]);
      })))),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(children: [
          Text('${g.daysUsed} / ${widget.spec.daysLimit} ${s('game.days')}',
              style: st(16, w: 700, color: g.daysUsed > widget.spec.daysLimit ? C.wrong : C.gold)),
          const Spacer(),
          if (!widget.done && g.path.length > 1)
            TextButton.icon(onPressed: () => setState(g.undo), icon: const Icon(Icons.undo_rounded, color: C.inkSoft),
                label: Text(s('game.undo'), style: st(14, color: C.inkSoft))),
        ]),
      ),
    ]);
  }
}

class _NodeDot extends StatelessWidget {
  const _NodeDot({required this.color, required this.active, required this.reachable});
  final Color color; final bool active, reachable;
  @override
  Widget build(BuildContext context) => Center(child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: active ? 22 : (reachable ? 20 : 14), height: active ? 22 : (reachable ? 20 : 14),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : color.withValues(alpha: .55),
          border: Border.all(color: reachable ? C.ink : const Color(0x00000000), width: 2),
          boxShadow: reachable ? [BoxShadow(color: color.withValues(alpha: .7), blurRadius: 12)] : null,
        ),
      ));
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.g, required this.at});
  final RouteGame g; final Offset Function(RouteNode) at;
  @override
  void paint(Canvas canvas, Size size) {
    final spec = g.spec;
    final faint = Paint()..color = const Color(0x88F4ECDF)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final walked = Paint()..color = const Color(0xFFB23A2A)..strokeWidth = 4..strokeCap = StrokeCap.round;
    for (final e in spec.edges) {
      final a = at(spec.node(e.a)), b = at(spec.node(e.b));
      _dash(canvas, a, b, faint);
      final mid = Offset.lerp(a, b, .5)!;
      final tp = TextPainter(text: TextSpan(text: '${e.days}', style: st(11, w: 700, color: C.ink).copyWith(shadows: const [Shadow(blurRadius: 4)])),
          textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
    for (var i = 1; i < g.path.length; i++) {
      canvas.drawLine(at(spec.node(g.path[i - 1])), at(spec.node(g.path[i])), walked);
    }
  }
  void _dash(Canvas c, Offset a, Offset b, Paint p) {
    final d = (b - a).distance; final dir = (b - a) / d;
    for (var t = 0.0; t < d; t += 10) { c.drawLine(a + dir * t, a + dir * math.min(t + 5, d), p); }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ---------------------------------------------------------------- базар
class _TradeView extends StatefulWidget {
  const _TradeView({required this.spec, required this.locale, required this.onDone, required this.done});
  final TradeSpec spec; final String locale; final void Function(GameOutcome) onDone; final bool done;
  @override
  State<_TradeView> createState() => _TradeViewState();
}

class _TradeViewState extends State<_TradeView> {
  late final TradeGame g = TradeGame(widget.spec);
  @override
  Widget build(BuildContext context) {
    final s = Str.of(widget.locale), l = widget.locale, spec = widget.spec;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xE6221A14), borderRadius: BorderRadius.circular(10), border: Border.all(color: C.goldDark)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s('game.need'), style: st(13, w: 700, color: C.gold)),
          const SizedBox(height: 6),
          for (final n in spec.needs.entries) Builder(builder: (_) {
            final good = spec.goods.firstWhere((x) => x.id == n.key);
            final have = g.cart[n.key] ?? 0, ok = have >= n.value;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 18, color: ok ? C.right : C.inkSoft),
              const SizedBox(width: 8),
              Expanded(child: Text(good.label.of(l), style: st(15))),
              Text('$have / ${n.value}', style: st(14, w: 600, color: ok ? C.right : C.inkSoft)),
            ]));
          }),
        ]),
      ),
      const SizedBox(height: 12),
      Text('${s('game.left')}: ${g.left} ${spec.currency.of(l)}', style: st(18, w: 700, color: C.gold)),
      const SizedBox(height: 8),
      for (final good in spec.goods)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: C.card.withValues(alpha: .95), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(good.label.of(l), style: st(15, w: 600)),
              Text('${good.price} ${spec.currency.of(l)}', style: st(12.5, color: C.inkSoft)),
            ])),
            IconButton(onPressed: widget.done || (g.cart[good.id] ?? 0) == 0 ? null : () => setState(() => g.remove(good.id)),
                icon: const Icon(Icons.remove_circle_outline, color: C.inkSoft)),
            SizedBox(width: 24, child: Text('${g.cart[good.id] ?? 0}', textAlign: TextAlign.center, style: st(17, w: 700))),
            IconButton(onPressed: widget.done || !g.canAdd(good.id) ? null : () => setState(() => g.add(good.id)),
                icon: const Icon(Icons.add_circle_outline, color: C.gold)),
          ]),
        )),
      const SizedBox(height: 6),
      if (!widget.done) GoldButton(label: s('game.deal'), onTap: () => widget.onDone(g.outcome)),
    ]);
  }
}

// ---------------------------------------------------------------- тактика
class _TacticsView extends StatefulWidget {
  const _TacticsView({required this.spec, required this.locale, required this.onDone, required this.done});
  final TacticsSpec spec; final String locale; final void Function(GameOutcome) onDone; final bool done;
  @override
  State<_TacticsView> createState() => _TacticsViewState();
}

class _TacticsViewState extends State<_TacticsView> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  TacticsMove? _move;
  @override
  void dispose() { _a.dispose(); super.dispose(); }

  Future<void> _pick(TacticsMove m) async {
    setState(() => _move = m);
    await _a.forward(from: 0);
    if (mounted) widget.onDone(m.outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.locale, spec = widget.spec;
    return Column(children: [
      Expanded(child: LayoutBuilder(builder: (context, c) => AnimatedBuilder(
        animation: _a,
        builder: (context, _) => Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _ArrowsPainter(arrows: _move?.arrows ?? const [], t: Curves.easeInOut.transform(_a.value),
              color: switch (_move?.outcome) { GameOutcome.win => C.right, GameOutcome.lose => C.wrong, _ => C.gold }))),
          for (final u in spec.units)
            Positioned(left: u.x * c.maxWidth - 60, top: u.y * c.maxHeight - 18, width: 120, child: Column(children: [
              Container(width: 26, height: 26, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: (u.enemy ? C.wrong : C.gold).withValues(alpha: .85), border: Border.all(color: C.ink, width: 1.5))),
              const SizedBox(height: 4),
              Text(u.label.of(l), textAlign: TextAlign.center, style: st(12, w: 600).copyWith(shadows: const [Shadow(blurRadius: 4)])),
            ])),
        ]),
      ))),
      if (!widget.done && _move == null)
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: Column(children: [
          for (final m in spec.moves) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(width: double.infinity, child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: C.gold), padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xCC221A14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => _pick(m),
              child: Text(m.label.of(l), style: st(15, w: 600), textAlign: TextAlign.center),
            )),
          ),
        ])),
    ]);
  }
}

class _ArrowsPainter extends CustomPainter {
  _ArrowsPainter({required this.arrows, required this.t, required this.color});
  final List<List<double>> arrows; final double t; final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (final a in arrows) {
      final from = Offset(a[0] * size.width, a[1] * size.height), to = Offset(a[2] * size.width, a[3] * size.height);
      final end = Offset.lerp(from, to, t)!;
      canvas.drawLine(from, end, p);
      if (t > .05) {
        final dir = (end - from) / math.max((end - from).distance, .001);
        final n = Offset(-dir.dy, dir.dx);
        final head = Path()..moveTo(end.dx + dir.dx * 10, end.dy + dir.dy * 10)
          ..lineTo(end.dx + n.dx * 8, end.dy + n.dy * 8)..lineTo(end.dx - n.dx * 8, end.dy - n.dy * 8)..close();
        canvas.drawPath(head, Paint()..color = color);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _ArrowsPainter o) => o.t != t || o.arrows != arrows;
}

// ---------------------------------------------------------------- залп
class _VolleyView extends StatefulWidget {
  const _VolleyView({required this.spec, required this.locale, required this.onDone, required this.done});
  final VolleySpec spec; final String locale; final void Function(GameOutcome) onDone; final bool done;
  @override
  State<_VolleyView> createState() => _VolleyViewState();
}

class _VolleyViewState extends State<_VolleyView> with SingleTickerProviderStateMixin {
  late final VolleyGame g = VolleyGame(widget.spec);
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
  int get _ms => (_t.value * const Duration(days: 1).inMilliseconds).round();
  @override
  void dispose() { _t.dispose(); super.dispose(); }

  void _shoot() {
    if (g.finished) return;
    setState(() => g.shoot(_ms));
    if (g.finished) { _t.stop(); widget.onDone(g.outcome); }
  }

  @override
  Widget build(BuildContext context) {
    final s = Str.of(widget.locale), spec = widget.spec;
    return Padding(padding: const EdgeInsets.fromLTRB(28, 8, 28, 20), child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < spec.rounds; i++) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Icon(i < g.shots.length ? (g.shots[i] ? Icons.check_circle_rounded : Icons.cancel_rounded) : Icons.circle_outlined,
              color: i < g.shots.length ? (g.shots[i] ? C.right : C.wrong) : C.inkSoft, size: 28),
        ),
      ]),
      const SizedBox(height: 16),
      Expanded(child: AnimatedBuilder(animation: _t, builder: (context, _) {
        final m = g.finished ? 0.0 : g.meter(_ms);
        return LayoutBuilder(builder: (context, c) {
          final h = c.maxHeight;
          return Center(child: SizedBox(width: 64, height: h, child: Stack(children: [
            Container(decoration: BoxDecoration(color: const Color(0xCC221A14), borderRadius: BorderRadius.circular(12), border: Border.all(color: C.goldDark))),
            // «вовремя» — золотая полоса
            Positioned(left: 0, right: 0, top: h * (1 - spec.window.$2), height: h * (spec.window.$2 - spec.window.$1),
                child: Container(color: C.gold.withValues(alpha: .35))),
            Positioned(left: 4, right: 4, top: h * (1 - m) - 3, height: 6,
                child: Container(decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(3)))),
          ])));
        });
      })),
      const SizedBox(height: 16),
      if (!widget.done) SizedBox(width: double.infinity, child: GoldButton(label: s('game.shoot'), height: 56, onTap: _shoot)),
    ]));
  }
}
