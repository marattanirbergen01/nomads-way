import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/local/episode_store.dart';
import '../../data/models/curriculum.dart';
import '../../widgets/common.dart';
import '../../widgets/ornament.dart';
import '../story/story_screen.dart';

/// Заставка серии: обложка, годы, объём. Пока серия качается — полоса прогресса.
/// После установки игра идёт с диска, без сети.
class EpisodeIntroScreen extends StatefulWidget {
  const EpisodeIntroScreen({super.key, required this.entry, required this.services});
  final CatalogEntry entry;
  final Services services;
  @override
  State<EpisodeIntroScreen> createState() => _EpisodeIntroScreenState();
}

class _EpisodeIntroScreenState extends State<EpisodeIntroScreen> {
  InstallState _state = InstallState.unsupported;
  InstallState _common = InstallState.unsupported;
  double? _progress;
  String? _error;
  bool _busy = false;

  Services get _s => widget.services;
  CatalogEntry get _e => widget.entry;

  @override
  void initState() { super.initState(); _check(); }

  Future<void> _check() async {
    final st = await _s.episodes.state(_e);
    await _s.episodes.warm(_e.id);
    final c = _s.content.commonSync ?? await _s.content.common().catchError((_) => const CommonInfo(avatars: []));
    final cs = await _s.episodes.stateOf('common', c.bundle);
    if (mounted) setState(() { _state = st; _common = cs; });
  }

  bool get _needCommon => _common == InstallState.absent || _common == InstallState.outdated;

  Future<void> _download() async {
    setState(() { _busy = true; _error = null; _progress = 0; });
    try {
      final c = _s.content.commonSync;
      final cb = _needCommon ? c?.bundle : null;
      final total = (_e.bundle?.bytes ?? 0) + (cb?.bytes ?? 0);
      var done = 0;
      void report(double v, int bytes) { if (mounted) setState(() => _progress = total == 0 ? v : ((done + v * bytes) / total).clamp(0, 1)); }
      if (cb != null) {
        await _s.episodes.installBundle('common', cb, _s.content.baseUrl, onProgress: (v) => report(v, cb.bytes));
        done += cb.bytes;
      }
      await _s.episodes.install(_e, _s.content.baseUrl, onProgress: (v) => report(v, _e.bundle?.bytes ?? 0));
      // серия обновилась — старая позиция могла указывать на исчезнувшую сцену
      if (_state == InstallState.outdated) await _s.store.clearStory(_e.id);
      await _check();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() { _busy = false; _progress = null; });
    }
  }

  Future<void> _play() async {
    setState(() { _busy = true; _error = null; });
    try {
      final (ep, qs) = await _s.content.episode(_e.id);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => StoryScreen(episode: ep, questions: qs, services: _s, contentHash: _e.bundle?.contentHash)));
      _s.touch();
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s.s; final l = _s.l;
    final b = _e.bundle;
    final cont = _s.store.continueMeta(_e.id);
    final needsDownload = _state == InstallState.absent || _state == InstallState.outdated || (_needCommon && _state != InstallState.unsupported);
    final commonMb = _needCommon ? (_s.content.commonSync?.bundle?.mb ?? 0) : 0.0;

    return Scaffold(
      backgroundColor: C.ground,
      body: Stack(fit: StackFit.expand, children: [
        NetArt(url: _s.content.mediaUrl(_e.id, 'cover_${_e.id}'), file: _s.content.mediaFile(_e.id, 'cover_${_e.id}'), fallback: Container(color: C.cardHigh)),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xC7141010), Color(0x66141010), Color(0xD9221A14), Color(0xFA221A14)], stops: [0, .3, .68, 1]))),
        SafeArea(child: Column(children: [
          Align(alignment: Alignment.centerLeft, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: C.ink, size: 20))),
          const Spacer(),
          Padding(padding: const EdgeInsets.fromLTRB(28, 0, 28, 34), child: Column(children: [
            Text("NOMAD'S WAY", style: st(12, w: 800, color: const Color(0xFFE8D9BD), spacing: 3)),
            const SizedBox(height: 18),
            const OrnamentLine(),
            const SizedBox(height: 18),
            Text('${_e.number} · ${_e.title.of(l)}', style: st(30, w: 700, height: 1.12), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text([_e.era, '${_e.scenes} ${s('scene.of')} · ${_e.questions} ${s('q.n')}'].whereType<String>().join('  ·  '),
                style: st(13.5, color: const Color(0xFFE8D9BD))),
            const SizedBox(height: 28),
            if (_error != null) ...[
              Text(_error!, style: st(12.5, color: C.ember), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 14),
            ],
            if (_progress != null) ...[
              Bar(_progress!, height: 6),
              const SizedBox(height: 10),
              Text('${s('downloading')} ${(_progress! * 100).round()}%', style: st(13, color: C.inkSoft)),
            ] else if (needsDownload && b != null) ...[
              SizedBox(width: double.infinity, child: GoldButton(
                label: '${_state == InstallState.outdated || _common == InstallState.outdated ? s('update') : s('download')} · ${(b.mb + commonMb).toStringAsFixed(1)} МБ',
                height: 52, onTap: _busy ? null : _download)),
              const SizedBox(height: 10),
              Text(_state == InstallState.outdated ? s('updated.hint') : s('offline.hint'),
                  style: st(12.5, color: C.inkFaint, height: 1.4), textAlign: TextAlign.center),
            ] else ...[
              SizedBox(width: double.infinity, child: GoldButton(
                label: cont == null ? s('start') : '${s('continue.v')} · ${(cont.fraction * 100).round()}%',
                height: 52, onTap: _busy ? null : _play)),
              if (_state == InstallState.ready) ...[
                const SizedBox(height: 10),
                Text(s('ready.offline'), style: st(12.5, color: C.inkFaint)),
              ],
            ],
          ])),
        ])),
      ]),
    );
  }
}
