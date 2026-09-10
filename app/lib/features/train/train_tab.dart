import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/models/curriculum.dart';
import '../../widgets/common.dart';
import '../../widgets/ornament.dart';
import '../path/path_tab.dart' show LoadError;
import 'mock_test_screen.dart';
import 'review_screen.dart';

class TrainTab extends StatefulWidget {
  const TrainTab({super.key, required this.services});
  final Services services;
  @override
  State<TrainTab> createState() => _TrainTabState();
}

class _TrainTabState extends State<TrainTab> {
  late Future<(List<CatalogEntry>, List<Topic>)> _data = _load();
  Services get _s => widget.services;
  Future<(List<CatalogEntry>, List<Topic>)> _load() async => (await _s.content.catalog(), await _s.content.curriculum());

  @override
  void initState() { super.initState(); _s.changes.addListener(_r); _s.locale.addListener(_r); }
  @override
  void dispose() { _s.changes.removeListener(_r); _s.locale.removeListener(_r); super.dispose(); }
  void _r() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return LoadError(services: _s, message: '${snap.error}', onRetry: () => setState(() => _data = _load()));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: C.gold));
          final (catalog, topics) = snap.data!;
          return _content(catalog, topics);
        },
      );

  Widget _content(List<CatalogEntry> catalog, List<Topic> topics) {
    final s = _s.s; final l = _s.l;
    final ids = catalog.where((e) => !e.planned).map((e) => e.id).toList();
    final bank = _s.content.cachedQuestions(ids);
    final due = _s.scheduler.due(_s.store.srs(), DateTime.now()).where(bank.map((q) => q.id).toSet().contains).length;
    final mocks = _s.store.tests().where((t) => t.kind == 'mock').toList();
    final last = mocks.isEmpty ? null : mocks.last;
    final attempts = _s.store.attempts();
    final canMock = bank.length >= 10;

    return ListView(padding: EdgeInsets.zero, children: [
      SkyHeader(height: 186, sun: true, sunRise: .35, child: Positioned(left: 20, top: MediaQuery.of(context).padding.top + 14, right: 20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s('train.title'), style: st(26, w: 700, color: C.onSky)),
        const SizedBox(height: 6),
        Text(s('train.sub'), style: st(13, color: C.onSkySoft)),
      ]))),
      const HorizonLine(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GroundCard(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s('mock.title'), style: st(18, w: 700)), const SizedBox(height: 5),
              Text(s('mock.sub'), style: st(13, color: C.inkSoft, height: 1.45)),
            ])),
            const SizedBox(width: 12),
            const Icon(Icons.assignment_outlined, color: C.gold, size: 28),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: last == null
                ? Text(s('mock.none'), style: st(13, color: C.inkSoft))
                : Text.rich(TextSpan(children: [
                    TextSpan(text: '${s('mock.last')} ', style: st(13, color: C.inkSoft)),
                    TextSpan(text: '${last.correct} / ${last.total}', style: st(13, w: 600)),
                    TextSpan(text: ' · ${ago(last.at, s, DateTime.now())}', style: st(13, color: C.inkSoft)),
                  ]))),
            GoldButton(label: s('start'), height: 44, onTap: canMock ? () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MockTestScreen(services: _s, bank: bank)));
              _s.touch();
            } : null),
          ]),
        ])),
        const SizedBox(height: 12),
        GroundCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          onTap: due == 0 ? null : () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(services: _s, bank: bank)));
            _s.touch();
          },
          child: Row(children: [
            Container(width: 44, height: 44, decoration: const BoxDecoration(shape: BoxShape.circle, color: C.cardHigh), child: const Icon(Icons.replay_rounded, color: C.gold, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s('mistakes'), style: st(16, w: 600)), const SizedBox(height: 3),
              Text(due > 0 ? s('mistakes.n').replaceFirst('{n}', '$due') : s('mistakes.0'), style: st(13, color: C.inkSoft)),
            ])),
            const Chevron(),
          ]),
        ),
        const SizedBox(height: 18),
        SectionTitle(s('by.periods'), trailing: s('share.correct')),
        for (final p in topics.periods.where((p) => topics.periodActive(p.id))) ...[
          Builder(builder: (_) {
            final facts = topics.periodFacts(p.id).toList();
            final eps = catalog.where((e) => e.inPeriod(p.id) && !e.planned).length;
            final qn = bank.where((q) => q.topic != null && (q.topic == p.id || q.topic!.startsWith('${p.id}.'))).length;
            final v = _s.mastery.topic(facts, attempts);
            return GroundCard(padding: const EdgeInsets.all(12), child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Expanded(child: Text(p.title.of(l), style: st(15, w: 600))), Text('${s('readiness')} ${(v * 100).round()}%', style: st(13, w: 600, color: C.gold))]),
                const SizedBox(height: 4),
                Text('${facts.length} ${s('facts.n')} · $qn ${s('q.n')} · $eps ${s('series.n')}', style: st(12.5, color: C.inkSoft)),
                const SizedBox(height: 6), Bar(v),
              ])),
            ]));
          }),
          const SizedBox(height: 8),
        ],
      ])),
    ]);
  }
}
