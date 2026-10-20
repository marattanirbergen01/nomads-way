import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/local/progress_repository.dart';
import '../../data/models/curriculum.dart';
import '../../widgets/common.dart';
import '../../widgets/ornament.dart';
import 'episode_intro_screen.dart';
import 'period_screen.dart';
import '../../widgets/scroll_buttons.dart';

/// Жол: баннер сезона, «Жалғастыру», периоды программы.
class PathTab extends StatefulWidget {
  const PathTab({super.key, required this.services});
  final Services services;
  @override
  State<PathTab> createState() => _PathTabState();
}

class _PathTabState extends State<PathTab> {
  late Future<(List<CatalogEntry>, List<Topic>)> _data = _load();
  String? _busy;
  Services get _s => widget.services;

  Future<(List<CatalogEntry>, List<Topic>)> _load() async => (await _s.content.catalog(), await _s.content.curriculum());
  void _refresh() => setState(() => _data = _load());

  @override
  void initState() { super.initState(); _s.changes.addListener(_onChange); _s.locale.addListener(_onChange); }
  @override
  void dispose() { _s.changes.removeListener(_onChange); _s.locale.removeListener(_onChange); super.dispose(); }
  void _onChange() { if (mounted) setState(() {}); }

  Future<void> openEntry(CatalogEntry e) async {
    setState(() => _busy = e.id);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EpisodeIntroScreen(entry: e, services: _s)));
    if (mounted) setState(() => _busy = null);
    _s.touch();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return LoadError(services: _s, message: '${snap.error}', onRetry: _refresh);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.gold));
          final (catalog, topics) = snap.data!;
          return ScrollButtons(child: _content(catalog, topics));
        },
      );

  Widget _content(List<CatalogEntry> catalog, List<Topic> topics) {
    final s = _s.s; final l = _s.l;
    final periods = topics.periods;
    // серия, которую продолжаем — самая свежая по мета
    final live = catalog.where((e) => !e.planned).toList();
    final conts = [for (final e in live) _s.store.continueMeta(e.id)].whereType<ContinueMeta>().toList()..sort((a, b) => b.at.compareTo(a.at));
    final cont = conts.firstOrNull;
    final contEntry = cont == null ? null : catalog.where((e) => e.id == cont.ep).firstOrNull;
    final season = periods.firstOrNull;
    final done = live.where((e) => _s.store.result(e.id) != null).length;

    return ListView(padding: EdgeInsets.zero, children: [
      // ---- небо: баннер сезона
      SizedBox(height: 332, child: Stack(fit: StackFit.expand, children: [
        NetArt(url: _s.content.mediaUrl('s1e01', 'cover_season1'), fallback: Container(color: C.skyTop)),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x6B141010), Color(0x00141010), Color(0x00221A14), Color(0xE0221A14)], stops: [0, .34, .52, 1]))),
        Positioned(left: 20, top: MediaQuery.of(context).padding.top + 16, child: Text("NOMAD'S WAY", style: st(21, w: 800, spacing: 3.4))),
        Positioned(left: 20, right: 20, bottom: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s('season1'), style: st(12, w: 600, color: const Color(0xFFE8D9BD), spacing: 1.4)),
          const SizedBox(height: 7),
          Text(season?.title.of(l) ?? '', style: st(30, w: 700, height: 1.08)),
          const SizedBox(height: 7),
          Text('${live.length} ${s('series.n')} · $done-і ${s('passed.1')}', style: st(13, color: const Color(0xFFE8D9BD))),
        ])),
      ])),
      const HorizonLine(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (cont != null && contEntry != null) ...[
            GroundCard(
              padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
              onTap: () => openEntry(contEntry),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: NetArt(url: _s.content.mediaUrl(contEntry.id, 'cover_${contEntry.id}'), width: 64, height: 64)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s('continue'), style: st(11, w: 600, color: C.gold, spacing: 1.1)),
                  const SizedBox(height: 4),
                  Text(contEntry.title.of(l), style: st(17, w: 600)),
                  const SizedBox(height: 4),
                  Text('${(cont.fraction * 100).round()}%', style: st(13, color: C.inkSoft)),
                ])),
                Container(width: 44, height: 44, decoration: const BoxDecoration(shape: BoxShape.circle, color: C.gold),
                    child: _busy == contEntry.id
                        ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: C.ground))
                        : const Icon(Icons.play_arrow_rounded, color: C.ground, size: 26)),
              ]),
            ),
            const SizedBox(height: 18),
          ],
          SectionTitle(s('periods'), trailing: s('ent.sub')),
          for (final p in periods) _PeriodRow(
            period: p, topics: topics, catalog: catalog, services: _s,
            onTap: topics.periodActive(p.id) ? () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeriodScreen(period: p, topics: topics, catalog: catalog, services: _s, openEntry: openEntry)));
              _s.touch();
            } : null,
          ),
        ]),
      ),
    ]);
  }
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.period, required this.topics, required this.catalog, required this.services, this.onTap});
  final Topic period; final List<Topic> topics; final List<CatalogEntry> catalog; final Services services; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final s = services.s; final l = services.l;
    final active = topics.periodActive(period.id);
    final eps = catalog.where((e) => e.inPeriod(period.id) && !e.planned).toList();
    final all = catalog.where((e) => e.inPeriod(period.id)).length;
    final done = eps.where((e) => services.store.result(e.id) != null).length;
    final passes = eps.fold(0, (n, e) => n + services.store.completions(e.id));
    final allDone = eps.isNotEmpty && done == eps.length;
    final dot = !active ? C.locked : (allDone ? C.ember : C.goldBright);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GroundCard(
        onTap: onTap, dim: !active, outlined: !active,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Dot(dot, glow: active && !allDone),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(period.title.of(l), style: st(15, w: 600))),
              if (active) Text('$done / ${all == 0 ? eps.length : all}', style: st(13, w: 600, color: C.gold)),
            ]),
            const SizedBox(height: 4),
            Text(active
                ? [period.era, '${all == 0 ? eps.length : all} ${s('series.n')} · $done-і ${s('passed.1')}', if (passes > 0) '$passes ${s('times')}'].whereType<String>().join(' · ')
                : [period.era, s('soon')].whereType<String>().join(' · '),
                style: st(12.5, color: C.inkSoft)),
            if (active) ...[const SizedBox(height: 6), Bar(all == 0 ? 0 : done / all)],
          ])),
          if (active) ...[const SizedBox(width: 8), const Chevron()],
        ]),
      ),
    );
  }
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.services, required this.message, required this.onRetry});
  final Services services; final String message; final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(s('load.err'), style: st(17, w: 600)),
      const SizedBox(height: 8),
      Text(s('load.hint'), style: st(13, color: C.inkSoft), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text(message, style: st(11, color: C.inkFaint), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 16),
      GoldButton(label: s('load.retry'), onTap: onRetry),
    ])));
  }
}
