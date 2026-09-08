import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/models/curriculum.dart';
import '../../engine/awards.dart';
import '../../widgets/common.dart';
import '../../widgets/ornament.dart';
import '../path/path_tab.dart' show LoadError;
import 'awards_meta.dart';

class ReadinessTab extends StatefulWidget {
  const ReadinessTab({super.key, required this.services});
  final Services services;
  @override
  State<ReadinessTab> createState() => _ReadinessTabState();
}

class _ReadinessTabState extends State<ReadinessTab> {
  late Future<List<Topic>> _data = widget.services.content.curriculum();
  Services get _s => widget.services;
  @override
  void initState() { super.initState(); _s.changes.addListener(_r); _s.locale.addListener(_r); }
  @override
  void dispose() { _s.changes.removeListener(_r); _s.locale.removeListener(_r); super.dispose(); }
  void _r() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return LoadError(services: _s, message: '${snap.error}', onRetry: () => setState(() => _data = _s.content.curriculum()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.gold));
          return _content(snap.data!);
        },
      );

  Widget _content(List<Topic> topics) {
    final s = _s.s; final l = _s.l;
    final attempts = _s.store.attempts();
    final active = topics.where((t) => !t.isPeriod && !t.planned).toList();
    final allFacts = active.expand((t) => t.factIds).toList();
    final total = _s.mastery.topic(allFacts, attempts);
    final have = _s.store.awards();
    final tests = _s.store.tests().reversed.take(3).toList();
    final periodTitle = topics.periods.firstOrNull?.title.of(l) ?? '';

    return ListView(padding: EdgeInsets.zero, children: [
      SkyHeader(height: 216, sun: true, sunRise: total, child: Positioned(left: 20, right: 20, top: MediaQuery.of(context).padding.top + 12, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s('ready.title'), style: st(12.5, w: 600, color: C.onSky, spacing: 1)),
        const SizedBox(height: 3),
        Text('${(total * 100).round()}%', style: st(54, w: 800, color: C.onSky, height: 1, spacing: -1)),
        const SizedBox(height: 3),
        Text('$periodTitle. ${s('ready.sub')}', style: st(12.5, color: C.onSkySoft, height: 1.4)),
      ]))),
      const HorizonLine(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(s('awards'), trailing: '${have.values.where((n) => n > 0).length} / ${Award.values.length}'),
        SizedBox(height: 92, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 2), children: [
          for (final a in Award.values) Padding(padding: const EdgeInsets.only(right: 12), child: SizedBox(width: 62, child: Column(children: [
            Medal(award: a, locked: (have[a.id] ?? 0) == 0),
            const SizedBox(height: 6),
            Text(awardMeta[a]!.name(l), style: st(11, color: (have[a.id] ?? 0) == 0 ? C.inkFaint : C.ink, height: 1.2), textAlign: TextAlign.center, maxLines: 2),
            if ((have[a.id] ?? 0) > 0) Text('×${have[a.id]}', style: st(11, w: 600, color: C.gold)),
          ]))),
        ])),
        const Divider(height: 26),
        for (final t in active) ...[
          SectionTitle(t.title.of(l), trailing: '${(_s.mastery.topic(t.factIds, attempts) * 100).round()}%'),
          for (final f in t.facts) Builder(builder: (_) {
            final v = _s.mastery.fact(f.id, attempts);
            final c = v >= .8 ? C.gold : v > 0 ? C.ember : const Color(0xFF5A4A3B);
            return Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
              const SizedBox(width: 12),
              Expanded(child: Text(f.text.of(l), style: st(14, color: v == 0 ? C.inkSoft : C.ink))),
              const SizedBox(width: 10),
              Text('${(v * 100).round()}%', style: st(13, color: C.inkSoft)),
            ]));
          }),
          const SizedBox(height: 10),
        ],
        SectionTitle(s('tests')),
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(child: i < tests.length
                ? GroundCard(padding: const EdgeInsets.all(11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [TextSpan(text: '${tests[i].correct}', style: st(21, w: 700)), TextSpan(text: ' / ${tests[i].total}', style: st(13, color: C.inkSoft))])),
                    const SizedBox(height: 2),
                    Text(ago(tests[i].at, s, DateTime.now()), style: st(11.5, color: C.inkSoft)),
                  ]))
                : Container(height: 64, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: C.cardHigh, style: BorderStyle.solid), borderRadius: BorderRadius.circular(12)), child: Text(s('not.yet'), style: st(11.5, color: C.inkFaint)))),
            if (i < 2) const SizedBox(width: 8),
          ],
        ]),
      ])),
    ]);
  }
}
