import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/models/curriculum.dart';
import '../../widgets/common.dart';
import '../../widgets/ornament.dart';

class PeriodScreen extends StatefulWidget {
  const PeriodScreen({super.key, required this.period, required this.topics, required this.catalog, required this.services, required this.openEpisode});
  final Topic period; final List<Topic> topics; final List<CatalogEntry> catalog; final Services services;
  final Future<void> Function(String id) openEpisode;
  @override
  State<PeriodScreen> createState() => _PeriodScreenState();
}

class _PeriodScreenState extends State<PeriodScreen> {
  Services get _s => widget.services;
  @override
  void initState() { super.initState(); _s.changes.addListener(_r); }
  @override
  void dispose() { _s.changes.removeListener(_r); super.dispose(); }
  void _r() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final s = _s.s; final l = _s.l;
    final eps = widget.catalog.where((e) => e.inPeriod(widget.period.id)).toList()..sort((a, b) => a.number.compareTo(b.number));
    final done = eps.where((e) => !e.planned && _s.store.result(e.id) != null).length;
    return Scaffold(body: ListView(padding: EdgeInsets.zero, children: [
      SizedBox(height: 200, child: Stack(fit: StackFit.expand, children: [
        NetArt(url: _s.content.mediaUrl('s1e01', 'cover_season1'), alignment: const Alignment(0, -.4), fallback: Container(color: C.skyTop)),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x73141010), Color(0x00141010), Color(0xE6221A14)], stops: [0, .4, 1]))),
        Positioned(left: 4, top: MediaQuery.of(context).padding.top, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: C.ink))),
        Positioned(left: 20, right: 20, bottom: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text([s('period'), widget.period.era].whereType<String>().join(' · ').toUpperCase(), style: st(12, w: 600, color: const Color(0xFFE8D9BD), spacing: 1.2)),
          const SizedBox(height: 4),
          Text(widget.period.title.of(l), style: st(26, w: 700, height: 1.1)),
          const SizedBox(height: 4),
          Text('${eps.length} ${s('series.n')} · $done-і ${s('passed.1')}', style: st(13, color: const Color(0xFFE8D9BD))),
        ])),
      ])),
      const HorizonLine(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in eps) ...[_EpisodeCard(index: e.number, e: e, services: _s, onTap: e.planned ? null : () => widget.openEpisode(e.id)), const SizedBox(height: 10)],
        const SizedBox(height: 4),
        GroundCard(outlined: true, child: Row(children: [
          const Icon(Icons.list_alt_rounded, color: C.gold), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s('period.test'), style: st(15, w: 600)), const SizedBox(height: 3),
            Text(s('period.test.sub'), style: st(12.5, color: C.inkSoft)),
          ])),
        ])),
      ])),
    ]));
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.index, required this.e, required this.services, required this.onTap});
  final int index; final CatalogEntry e; final Services services; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final s = services.s; final l = services.l;
    if (e.planned) {
      return GroundCard(outlined: true, dim: true, padding: const EdgeInsets.all(12), child: Row(children: [
        Container(width: 72, height: 72, decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.lock_outline_rounded, color: C.locked, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$index · ${e.title.of(l)}', style: st(17, w: 600)),
          const SizedBox(height: 5),
          Text([e.era, s('soon')].whereType<String>().join(' · '), style: st(12.5, color: C.inkSoft)),
        ])),
      ]));
    }
    final res = services.store.result(e.id);
    final cont = services.store.continueMeta(e.id);
    final n = services.store.completions(e.id);
    return GroundCard(onTap: onTap, padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(borderRadius: BorderRadius.circular(10), child: NetArt(url: services.content.mediaUrl(e.id, 'cover_${e.id}'), width: 72, height: 72)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$index · ${e.title.of(l)}', style: st(17, w: 600)),
        const SizedBox(height: 5),
        Text([e.era, '${e.scenes} ${s('scene.of')} · ${e.questions} ${s('q.n')}'].whereType<String>().join(' · '), style: st(12.5, color: C.inkSoft)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (res != null) Pill('${s('last.test')} ${res.correct}/${res.total}'),
          if (n > 0) Pill('$n ${s('times')}'),
          if (cont != null) Pill('${s('continue.v').toLowerCase()} · ${(cont.fraction * 100).round()}%', gold: true),
          if (res == null && cont == null) Pill(s('start').toLowerCase(), gold: true),
        ]),
      ])),
    ]));
  }
}
