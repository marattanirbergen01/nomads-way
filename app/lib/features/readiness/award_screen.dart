import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:video_player/video_player.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../engine/awards.dart';
import 'awards_meta.dart';

/// Награда на весь экран. Основной вид — ролик раскрытия (marketing/awards-motion, 2,6 с):
/// горизонт сворачивается в медаль, знак проявляется, название и описание пишутся.
/// Когда ролик доиграл, снизу появляются счётчик и кнопка. Тап по экрану — сразу в конец.
/// Если видео не запустилось (старое устройство, тесты) — прежний статичный экран.
class AwardScreen extends StatefulWidget {
  const AwardScreen({super.key, required this.award, required this.count, required this.services});
  final Award award; final int count; final Services services;

  static Future<void> show(BuildContext context, Services s, Award a, int count) =>
      Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => AwardScreen(award: a, count: count, services: s),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ));

  @override
  State<AwardScreen> createState() => _AwardScreenState();
}

/// Цвет краёв кадра ролика: им заливаются поля на экранах выше 9:16, чтобы шва не было видно.
const _videoEdge = Color(0xFF15100C);

class _AwardScreenState extends State<AwardScreen> {
  VideoPlayerController? _v;
  bool _ready = false;   // ролик загружен и играет
  bool _failed = false;  // не удалось — показываем статичный экран
  bool _done = false;    // ролик доиграл: показать счётчик и кнопку
  Timer? _safety;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final v = VideoPlayerController.asset('assets/awards/${awardMeta[widget.award]!.video}.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _v = v;
    try {
      await v.initialize().timeout(const Duration(seconds: 4));
      if (!mounted) return;
      await v.setVolume(widget.services.store.sound ? 1 : 0);
      v.addListener(_tick);
      try {
        await v.play();
      } catch (_) {
        // браузер может запретить автозапуск со звуком — играем без звука
        await v.setVolume(0);
        await v.play();
      }
      if (!mounted) return;
      setState(() => _ready = true);
      // страховка: если конец ролика не пришёл событием, всё равно показать кнопку
      _safety = Timer(v.value.duration + const Duration(milliseconds: 400), _finish);
    } catch (_) {
      if (mounted) setState(() { _failed = true; _done = true; });
    }
  }

  void _tick() {
    final v = _v!.value;
    if (v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 60)) _finish();
  }

  void _finish() { if (mounted && !_done) setState(() => _done = true); }

  void _skip() {
    final v = _v;
    if (_done || v == null || !_ready) return;
    v.seekTo(v.value.duration);
    v.pause();
    _finish();
  }

  @override
  void dispose() {
    _safety?.cancel();
    _v?.removeListener(_tick);
    _v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _StaticAward(award: widget.award, count: widget.count, services: widget.services);
    final s = widget.services.s;
    final v = _v;
    return AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: Scaffold(
      backgroundColor: _videoEdge,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skip,
        child: Stack(children: [
          if (_ready && v != null)
            // contain: на телефонах выше 9:16 по краям поля цвета кадра, текст ролика не обрезается
            Positioned.fill(child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: Stack(children: [
                Positioned.fill(child: VideoPlayer(v)),
                // края кадра растворяются в полях — без видимого шва на высоких экранах
                Positioned(left: 0, right: 0, top: 0, height: v.value.size.height * .06, child: const _Fade(top: true)),
                Positioned(left: 0, right: 0, bottom: 0, height: v.value.size.height * .06, child: const _Fade(top: false)),
              ])),
            )),
          Positioned(left: 24, right: 24, bottom: 0, child: SafeArea(top: false, child: Center(child: ConstrainedBox(
            // на планшете и в браузере на компьютере кнопка не тянется на всю ширину
            constraints: const BoxConstraints(maxWidth: 480), child: AnimatedOpacity(
            opacity: _done ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: IgnorePointer(ignoring: !_done, child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _CountChip(text: s('award.n').replaceFirst('{n}', '${widget.count}')),
                const SizedBox(height: 18),
                SizedBox(width: double.infinity, child: GoldButton(label: s('award.ok'), height: 52, onTap: () => Navigator.of(context).pop())),
              ]),
            )),
          ))))),
        ]),
      ),
    ));
  }
}

class _Fade extends StatelessWidget {
  const _Fade({required this.top});
  final bool top;
  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: const [_videoEdge, Color(0x0015100C)],
      )));
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: C.goldDark), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: st(13, w: 600, color: C.gold)),
      );
}

/// Прежний статичный экран награды — запасной, если ролик не запустился.
class _StaticAward extends StatelessWidget {
  const _StaticAward({required this.award, required this.count, required this.services});
  final Award award; final int count; final Services services;

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
                _CountChip(text: s('award.n').replaceFirst('{n}', '$count')),
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
