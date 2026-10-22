import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../engine/games/game_spec.dart';
import '../../widgets/art.dart';
import '../../widgets/sfx.dart';

/// Мини-игра на весь экран (эксперимент, ветка experiment/minigames).
/// Возвращает исход через Navigator.pop. «Өткізу» — частичный успех: проигрыш сюжет не блокирует.
///
/// Движение и звук — по эталону сессии «Анимация»: content/media/s1/app/games/game_motion_spec.md
/// (кривые и тайминги оттуда без изменений). Значки и звуки — assets/games/.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.spec, required this.locale, this.artUrl, this.artFile, this.sound = true});
  final GameSpec spec;
  final String locale;
  /// Картинка игры: своя (`art` у игры — «чистая» карта, схема поля) или кадр сцены.
  final String? artUrl;
  final File? artFile;
  final bool sound;

  static Future<GameOutcome> play(BuildContext context, GameSpec spec, String locale, {String? artUrl, File? artFile, bool sound = true}) async =>
      await Navigator.of(context).push<GameOutcome>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GameScreen(spec: spec, locale: locale, artUrl: artUrl, artFile: artFile, sound: sound),
      )) ??
      GameOutcome.partial;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

// ---- кривые эталона (общие с плашками)
const _backOut = Cubic(0.34, 1.56, 0.64, 1);
const _draw = Cubic(0.45, 0, 0.25, 1);
const _pulse = Cubic(0.2, 0, 0.2, 1);
const _fadeIn = Cubic(0.25, 0.1, 0.25, 1);
const _exit = Cubic(0.42, 0, 1, 1);
const _shot = Cubic(0.3, 0, 0.2, 1);
const _routeRed = Color(0xFF8E2F22);
const _raidRed = Color(0xFFB23A2A);

double _ph(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _GameScreenState extends State<GameScreen> {
  GameOutcome? _result;
  late final Sfx sfx = Sfx(widget.sound);
  Str get s => Str.of(widget.locale);
  String get l => widget.locale;

  void _finish(GameOutcome o, {bool sound = true}) {
    if (_result != null) return;
    if (sound && o != GameOutcome.partial) sfx.game(o == GameOutcome.win ? 'win' : 'lose');
    setState(() => _result = o);
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final done = _result != null;
    final body = switch (spec) {
      RouteSpec r => _RouteView(spec: r, locale: l, sfx: sfx, onDone: _finish, done: done, artUrl: widget.artUrl, artFile: widget.artFile),
      TradeSpec t => _TradeView(spec: t, locale: l, sfx: sfx, onDone: _finish, done: done),
      TacticsSpec t => _TacticsView(spec: t, locale: l, sfx: sfx, onDone: _finish, done: done, artUrl: widget.artUrl, artFile: widget.artFile),
      VolleySpec v => _VolleyView(spec: v, locale: l, sfx: sfx, onDone: _finish, done: done),
    };
    final framed = spec is RouteSpec || spec is TacticsSpec; // картинка внутри поля игры
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: C.ground,
        body: Stack(fit: StackFit.expand, children: [
          if (!framed && (widget.artUrl != null || widget.artFile != null))
            Opacity(opacity: .35, child: Art(url: widget.artUrl, file: widget.artFile, width: double.infinity, height: double.infinity)),
          SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(spec.title.of(l).toUpperCase(), style: st(13, w: 700, color: C.gold, spacing: 1.6))),
                  if (!done)
                    TextButton(onPressed: () => _finish(GameOutcome.partial), child: Text(s('game.skip'), style: st(14, color: C.inkSoft))),
                ]),
                const SizedBox(height: 4),
                Text(spec.prompt.of(l), style: st(15, height: 1.4).copyWith(shadows: const [Shadow(blurRadius: 6)])),
              ]),
            ),
            Expanded(child: body),
            if (done) _ResultBar(outcome: _result!, spec: spec, locale: l, onNext: () => Navigator.of(context).pop(_result)),
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

/// Кадр 4:7 с картинкой игры, внутри — слои поля (точки, отряды, стрелки) в долях кадра.
/// [view] — увеличенный участок кадра (x0, y0, x1, y1); слои получают функцию перевода долей кадра в точки экрана.
class _Frame extends StatelessWidget {
  const _Frame({required this.artUrl, required this.artFile, required this.builder, this.view = const (0.0, 0.0, 1.0, 1.0)});
  final String? artUrl; final File? artFile;
  final (double, double, double, double) view;
  final Widget Function(double w, double h, Offset Function(double x, double y) at) builder;
  @override
  Widget build(BuildContext context) {
    final (x0, y0, x1, y1) = view;
    final vw = x1 - x0, vh = y1 - y0;
    return Center(child: AspectRatio(aspectRatio: (vw * 4) / (vh * 7), child: LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final imgW = w / vw, imgH = h / vh;
      Offset at(double x, double y) => Offset((x - x0) * imgW, (y - y0) * imgH);
      return ClipRect(child: Stack(clipBehavior: Clip.none, children: [
        if (artUrl != null || artFile != null)
          Positioned(left: -x0 * imgW, top: -y0 * imgH, width: imgW, height: imgH,
              child: Art(url: artUrl, file: artFile, fit: BoxFit.fill, width: imgW, height: imgH, logicalWidth: imgW)),
        Positioned.fill(child: builder(w, h, at)),
      ]));
    })));
  }
}

// ---------------------------------------------------------------- путь кочевья
class _RouteView extends StatefulWidget {
  const _RouteView({required this.spec, required this.locale, required this.sfx, required this.onDone, required this.done, this.artUrl, this.artFile});
  final RouteSpec spec; final String locale; final Sfx sfx; final void Function(GameOutcome, {bool sound}) onDone; final bool done;
  final String? artUrl; final File? artFile;
  @override
  State<_RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends State<_RouteView> with TickerProviderStateMixin {
  late final RouteGame g = RouteGame(widget.spec);
  late final List<RouteNode> _byDistance = [...widget.spec.nodes]..sort((a, b) => _dist(a).compareTo(_dist(b)));
  late final AnimationController _intro = AnimationController(vsync: this,
      duration: Duration(milliseconds: 280 + 60 * (widget.spec.nodes.length - 1)))..forward();
  /// Рост последнего отрезка (шаг) или его откат (отмена).
  late final AnimationController _seg = AnimationController(vsync: this, value: 1);
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  String? _ringAt;
  bool _busy = false;

  double _dist(RouteNode n) { final s = widget.spec.node(widget.spec.start); return math.sqrt(math.pow(n.x - s.x, 2) + math.pow(n.y - s.y, 2)); }

  @override
  void dispose() { _intro.dispose(); _seg.dispose(); _ring.dispose(); super.dispose(); }

  Future<void> _go(RouteNode n) async {
    if (_busy || widget.done || !g.canGo(n.id)) return;
    final days = widget.spec.days(g.at, n.id)!;
    _busy = true;
    setState(() => g.go(n.id));
    widget.sfx.game('step');
    _seg.duration = Duration(milliseconds: (120 * days).clamp(300, 700));
    await _seg.forward(from: 0);
    if (!mounted) return;
    // прибытие: расходящееся кольцо; набег — красное и тревожный рог
    if (n.kind == 'enemy') widget.sfx.game('raid');
    setState(() => _ringAt = n.id);
    await _ring.forward(from: 0);
    _busy = false;
    if (!mounted) return;
    if (g.finished) widget.onDone(g.outcome);
  }

  Future<void> _undo() async {
    if (_busy || g.path.length < 2) return;
    _busy = true;
    _seg.duration = const Duration(milliseconds: 200);
    await _seg.reverse(from: 1);
    if (!mounted) return;
    setState(g.undo);
    _seg.value = 1;
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final s = Str.of(widget.locale), spec = widget.spec;
    return Column(children: [
      Expanded(child: _Frame(artUrl: widget.artUrl, artFile: widget.artFile, view: spec.view, builder: (w, h, frameAt) {
        Offset at(RouteNode n) => frameAt(n.x, n.y);
        return AnimatedBuilder(
          animation: Listenable.merge([_intro, _seg, _ring]),
          builder: (context, _) {
            final introMs = _intro.value * _intro.duration!.inMilliseconds;
            return Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: CustomPaint(painter: _RoutePainter(g: g, at: at, w: w, seg: _draw.transform(_seg.value)))),
              if (_ringAt != null && _ring.isAnimating)
                Builder(builder: (_) {
                  final n = spec.node(_ringAt!), p = _pulse.transform(_ring.value), r = 18 + 12 * p;
                  return Positioned(left: at(n).dx - r, top: at(n).dy - r, width: 2 * r, height: 2 * r,
                      child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(
                          color: (n.kind == 'enemy' ? _raidRed : C.gold).withValues(alpha: .6 * (1 - p)), width: 2))));
                }),
              for (final n in spec.nodes)
                Builder(builder: (_) {
                  final i = _byDistance.indexOf(n);
                  final p = _ph(introMs, i * 60.0, i * 60.0 + 280);
                  final reachable = !widget.done && g.canGo(n.id);
                  final icon = n.id == spec.goal ? 'node_goal' : 'node_${n.kind}';
                  return Positioned(
                    left: at(n).dx - 22, top: at(n).dy - 22, width: 44, height: 44,
                    child: GestureDetector(
                      onTap: () => _go(n),
                      child: Opacity(opacity: _fadeIn.transform(p), child: Transform.scale(
                        scale: 0.6 + 0.4 * _backOut.transform(p),
                        child: Container(
                          decoration: reachable ? BoxDecoration(shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: C.gold.withValues(alpha: .65), blurRadius: 14)]) : null,
                          child: Opacity(opacity: g.path.contains(n.id) || reachable || n.id == g.at ? 1 : .75,
                              child: Image.asset('assets/games/$icon.png', width: 34, height: 34)),
                        ),
                      )),
                    ),
                  );
                }),
              for (final n in spec.nodes) _label(n, at(n)),
            ]);
          },
        );
      })),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Row(children: [
          Text('${g.daysUsed} / ${spec.daysLimit} ${s('game.days')}',
              style: st(16, w: 700, color: g.daysUsed > spec.daysLimit ? C.wrong : C.gold)),
          const Spacer(),
          if (!widget.done && g.path.length > 1)
            TextButton.icon(onPressed: _undo, icon: const Icon(Icons.undo_rounded, color: C.inkSoft),
                label: Text(s('game.undo'), style: st(14, color: C.inkSoft))),
        ]),
      ),
    ]);
  }

  /// Подпись точки — сбоку или над/под ней (label_at), чтобы тесные точки не перекрывались.
  Widget _label(RouteNode n, Offset p) {
    const w = 140.0, gap = 22.0;
    final text = Text(n.label.of(widget.locale), maxLines: 1,
        textAlign: switch (n.labelAt) { 'left' => TextAlign.right, 'right' => TextAlign.left, _ => TextAlign.center },
        style: st(11.5, w: 600, color: C.ink).copyWith(shadows: const [Shadow(blurRadius: 4), Shadow(blurRadius: 8)]));
    return switch (n.labelAt) {
      'above' => Positioned(left: p.dx - w / 2, top: p.dy - gap - 16, width: w, child: text),
      'left' => Positioned(left: p.dx - gap - w, top: p.dy - 8, width: w, child: text),
      'right' => Positioned(left: p.dx + gap, top: p.dy - 8, width: w, child: text),
      _ => Positioned(left: p.dx - w / 2, top: p.dy + gap, width: w, child: text),
    };
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.g, required this.at, required this.w, required this.seg});
  final RouteGame g; final Offset Function(RouteNode) at; final double w;
  /// Доля последнего отрезка пути (рост при шаге, откат при отмене).
  final double seg;
  @override
  void paint(Canvas canvas, Size size) {
    final spec = g.spec;
    // возможные дороги — тонкий светлый пунктир с числом дней
    final faint = Paint()..color = const Color(0x88F4ECDF)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    for (final e in spec.edges) {
      final a = at(spec.node(e.a)), b = at(spec.node(e.b));
      _dash(canvas, a, b, faint, 6, 6);
      final mid = Offset.lerp(a, b, .5)!;
      final tp = TextPainter(text: TextSpan(text: '${e.days}', style: st(11, w: 700, color: C.ink).copyWith(shadows: const [Shadow(blurRadius: 4)])),
          textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
    // пройденный путь — как маршрут на анимированной карте: #8E2F22, мягкий край, пунктир 16/12 при 1080
    final k = w / 1080, dash = 16 * k * 3, gap = 12 * k * 3;
    final glow = Paint()..color = _routeRed.withValues(alpha: .45)..strokeWidth = 9 * k * 3..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    final line = Paint()..color = _routeRed..strokeWidth = 6 * k * 3..strokeCap = StrokeCap.round;
    for (var i = 1; i < g.path.length; i++) {
      final a = at(spec.node(g.path[i - 1])), b0 = at(spec.node(g.path[i]));
      final b = i == g.path.length - 1 ? Offset.lerp(a, b0, seg)! : b0;
      _dash(canvas, a, b, glow, dash, gap);
      _dash(canvas, a, b, line, dash, gap);
    }
  }
  void _dash(Canvas c, Offset a, Offset b, Paint p, double on, double off) {
    final d = (b - a).distance;
    if (d < .5) return;
    final dir = (b - a) / d;
    for (var t = 0.0; t < d; t += on + off) { c.drawLine(a + dir * t, a + dir * math.min(t + on, d), p); }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

// ---------------------------------------------------------------- базар
class _TradeView extends StatefulWidget {
  const _TradeView({required this.spec, required this.locale, required this.sfx, required this.onDone, required this.done});
  final TradeSpec spec; final String locale; final Sfx sfx; final void Function(GameOutcome, {bool sound}) onDone; final bool done;
  @override
  State<_TradeView> createState() => _TradeViewState();
}

class _TradeViewState extends State<_TradeView> {
  late final TradeGame g = TradeGame(widget.spec);
  final _bump = <String, int>{};

  void _change(String id, bool add) {
    final before = g.cart[id] ?? 0;
    setState(() { add ? g.add(id) : g.remove(id); });
    if ((g.cart[id] ?? 0) != before) {
      widget.sfx.game('trade');
      setState(() => _bump[id] = (_bump[id] ?? 0) + 1);
    }
  }

  Future<void> _deal() async {
    widget.sfx.game('deal');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted) widget.onDone(g.outcome);
  }

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
      // остаток: старое число уезжает вверх и гаснет, новое приходит снизу
      Row(children: [
        Image.asset('assets/games/cur_sheep.png', width: 32, height: 32),
        const SizedBox(width: 8),
        Text('${s('game.left')}: ', style: st(18, w: 700, color: C.gold)),
        ClipRect(child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160), reverseDuration: const Duration(milliseconds: 120),
          switchInCurve: _backOut, switchOutCurve: _exit,
          transitionBuilder: (child, a) {
            final incoming = child.key == ValueKey(g.left);
            return FadeTransition(opacity: a, child: SlideTransition(
                position: Tween(begin: Offset(0, incoming ? .6 : -.6), end: Offset.zero).animate(a), child: child));
          },
          child: Text('${g.left}', key: ValueKey(g.left), style: st(18, w: 700, color: C.gold)),
        )),
        Text(' ${spec.currency.of(l)}', style: st(18, w: 700, color: C.gold)),
      ]),
      const SizedBox(height: 8),
      for (final good in spec.goods)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: C.card.withValues(alpha: .95), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            // нажатие: значок 1 → 0,92 → 1 за 160 мс
            TweenAnimationBuilder<double>(
              key: ValueKey('${good.id}-${_bump[good.id] ?? 0}'),
              tween: Tween(begin: 0, end: 1), duration: Duration(milliseconds: (_bump[good.id] ?? 0) == 0 ? 0 : 160),
              builder: (_, t, child) => Transform.scale(
                  scale: t < .5 ? 1 - .08 * _fadeIn.transform(t * 2) : .92 + .08 * _backOut.transform((t - .5) * 2), child: child),
              child: good.icon == null
                  ? const SizedBox(width: 40, height: 40)
                  : Image.asset('assets/games/${good.icon}.png', width: 40, height: 40),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(good.label.of(l), style: st(15, w: 600)),
              Text('${good.price} ${spec.currency.of(l)}', style: st(12.5, color: C.inkSoft)),
            ])),
            IconButton(onPressed: widget.done || (g.cart[good.id] ?? 0) == 0 ? null : () => _change(good.id, false),
                icon: const Icon(Icons.remove_circle_outline, color: C.inkSoft)),
            SizedBox(width: 24, child: Text('${g.cart[good.id] ?? 0}', textAlign: TextAlign.center, style: st(17, w: 700))),
            IconButton(onPressed: widget.done || !g.canAdd(good.id) ? null : () => _change(good.id, true),
                icon: const Icon(Icons.add_circle_outline, color: C.gold)),
          ]),
        )),
      const SizedBox(height: 6),
      if (!widget.done) GoldButton(label: s('game.deal'), onTap: _deal),
    ]);
  }
}

// ---------------------------------------------------------------- тактика
class _TacticsView extends StatefulWidget {
  const _TacticsView({required this.spec, required this.locale, required this.sfx, required this.onDone, required this.done, this.artUrl, this.artFile});
  final TacticsSpec spec; final String locale; final Sfx sfx; final void Function(GameOutcome, {bool sound}) onDone; final bool done;
  final String? artUrl; final File? artFile;
  @override
  State<_TacticsView> createState() => _TacticsViewState();
}

class _TacticsViewState extends State<_TacticsView> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this);
  TacticsMove? _move;
  @override
  void dispose() { _a.dispose(); super.dispose(); }

  /// Стрелки растут по 700 мс, порядок — как в описании (центр, левое, правое), шаг 120 мс.
  Future<void> _pick(TacticsMove m) async {
    setState(() => _move = m);
    widget.sfx.game('horn');
    _a.duration = Duration(milliseconds: math.max(1, (m.arrows.length - 1) * 120 + 700));
    await _a.forward(from: 0);
    if (mounted) widget.onDone(m.outcome);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.locale, spec = widget.spec;
    final color = switch (_move?.outcome) { GameOutcome.win => C.right, GameOutcome.lose => C.wrong, _ => C.gold };
    return Column(children: [
      Expanded(child: _Frame(artUrl: widget.artUrl, artFile: widget.artFile, builder: (w, h, _) => AnimatedBuilder(
        animation: _a,
        builder: (context, _) => Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: _ArrowsPainter(arrows: _move?.arrows ?? const [],
              ms: _a.value * (_a.duration?.inMilliseconds ?? 0), color: color))),
          for (final u in spec.units)
            Positioned(left: u.x * w - 60, top: u.y * h - 24, width: 120, child: Column(children: [
              Image.asset('assets/games/${u.enemy ? 'unit_enemy' : 'unit_ours'}.png', width: 44, height: 44),
              const SizedBox(height: 2),
              Text(u.label.of(l), textAlign: TextAlign.center, maxLines: 1,
                  style: st(12, w: 600).copyWith(shadows: const [Shadow(blurRadius: 4), Shadow(blurRadius: 8)])),
            ])),
        ]),
      ))),
      if (!widget.done && _move == null)
        Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Column(children: [
          for (final m in spec.moves) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(width: double.infinity, child: OutlinedButton(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: C.gold), padding: const EdgeInsets.symmetric(vertical: 13),
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
  _ArrowsPainter({required this.arrows, required this.ms, required this.color});
  final List<List<double>> arrows; final double ms; final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    for (var i = 0; i < arrows.length; i++) {
      final a = arrows[i];
      final start = i * 120.0, grow = _draw.transform(_ph(ms, start, start + 700));
      if (grow <= 0) continue;
      final from = Offset(a[0] * size.width, a[1] * size.height), to = Offset(a[2] * size.width, a[3] * size.height);
      final end = Offset.lerp(from, to, grow)!;
      canvas.drawLine(from, end, p);
      // наконечник — последние 120 мс роста, 0,6 → 1 (backOut)
      final hp = _ph(ms, start + 580, start + 700);
      if (hp > 0) {
        final k = 0.6 + 0.4 * _backOut.transform(hp);
        final dir = (to - from) / math.max((to - from).distance, .001);
        final n = Offset(-dir.dy, dir.dx);
        final head = Path()
          ..moveTo(end.dx + dir.dx * 12 * k, end.dy + dir.dy * 12 * k)
          ..lineTo(end.dx + n.dx * 9 * k, end.dy + n.dy * 9 * k)
          ..lineTo(end.dx - n.dx * 9 * k, end.dy - n.dy * 9 * k)
          ..close();
        canvas.drawPath(head, Paint()..color = color);
      }
    }
  }
  @override
  bool shouldRepaint(covariant _ArrowsPainter o) => o.ms != ms || o.arrows != arrows || o.color != color;
}

// ---------------------------------------------------------------- залп
class _VolleyView extends StatefulWidget {
  const _VolleyView({required this.spec, required this.locale, required this.sfx, required this.onDone, required this.done});
  final VolleySpec spec; final String locale; final Sfx sfx; final void Function(GameOutcome, {bool sound}) onDone; final bool done;
  @override
  State<_VolleyView> createState() => _VolleyViewState();
}

class _VolleyViewState extends State<_VolleyView> with TickerProviderStateMixin {
  late final VolleyGame g = VolleyGame(widget.spec);
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
  /// Полёт стрелы и итог выстрела: 0–260 мс полёт, дальше 300 мс кольцо (попадание) или падение и дрожь (промах).
  late final AnimationController _shotA = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  bool? _lastHit;
  double _frozen = 0;
  int get _ms => (_t.value * const Duration(days: 1).inMilliseconds).round();
  @override
  void dispose() { _t.dispose(); _shotA.dispose(); super.dispose(); }

  Future<void> _shoot() async {
    if (g.finished || _shotA.isAnimating) return;
    final m = g.meter(_ms);
    final hit = g.shoot(_ms);
    widget.sfx.game('bow');
    setState(() { _lastHit = hit; _frozen = m; });
    if (g.finished) _t.stop();
    Future<void>.delayed(const Duration(milliseconds: 260), () => widget.sfx.game(hit ? 'hit' : 'miss'));
    await _shotA.forward(from: 0);
    if (mounted && g.finished) widget.onDone(g.outcome);
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
      const SizedBox(height: 12),
      Expanded(child: AnimatedBuilder(animation: Listenable.merge([_t, _shotA]), builder: (context, _) {
        final m = g.finished || _shotA.isAnimating ? _frozen : g.meter(_ms);
        final sm = _shotA.value * 560;
        // промах: дрожь шкалы ±4 pt дважды за 160 мс после полёта
        final shake = _lastHit == false && sm > 260 && sm < 420 ? 4 * math.sin((sm - 260) / 160 * 4 * math.pi) : 0.0;
        return LayoutBuilder(builder: (context, c) {
          final h = math.min(c.maxHeight, 360.0), w = h * 64 / 360;
          return Center(child: Transform.translate(offset: Offset(shake, 0), child: SizedBox(width: w + 120, height: h, child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: 60, top: 0, width: w, height: h, child: Stack(children: [
              Positioned.fill(child: Image.asset('assets/games/volley_bow.png', fit: BoxFit.fill)),
              // золотая полоса окна — #F1C453 35 %
              Positioned(left: w * .2, right: w * .2, top: h * (1 - spec.window.$2), height: h * (spec.window.$2 - spec.window.$1),
                  child: Container(color: const Color(0xFFF1C453).withValues(alpha: .35))),
              Positioned(left: w * .12, right: w * .12, top: h * (1 - m) - 3, height: 6,
                  child: Container(decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(3)))),
            ])),
            // стрела уходит вверх на 120 pt и гаснет (shot); промах — падает на 24 pt и гаснет (exit)
            if (_shotA.isAnimating) Builder(builder: (_) {
              final fly = _shot.transform(_ph(sm, 0, 260));
              final fall = _lastHit == false ? _exit.transform(_ph(sm, 260, 460)) : 0.0;
              final y = h * (1 - m) - 40 - 120 * fly + 24 * fall;
              final op = sm < 260 ? 1 - .6 * fly : (_lastHit == true ? 0.0 : (1 - fall) * .4);
              return Positioned(left: 60 + w / 2 - 12, top: y, width: 24, height: 80,
                  child: Opacity(opacity: op.clamp(0.0, 1.0), child: Image.asset('assets/games/volley_arrow.png', fit: BoxFit.contain)));
            }),
            // попадание — кольцо #F1C453 20 → 40 pt
            if (_shotA.isAnimating && _lastHit == true && sm > 260) Builder(builder: (_) {
              final p = _pulse.transform(_ph(sm, 260, 560)), r = 10 + 10 * p;
              return Positioned(left: 60 + w / 2 - r * 2, top: h * (1 - m) - 160 - r * 2, width: r * 4, height: r * 4,
                  child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFF1C453).withValues(alpha: 1 - p), width: 2))));
            }),
          ]))));
        });
      })),
      const SizedBox(height: 16),
      if (!widget.done) SizedBox(width: double.infinity, child: GoldButton(label: s('game.shoot'), height: 56, onTap: _shoot)),
    ]));
  }
}
