import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../data/models/curriculum.dart';
import '../episode/episode_screen.dart';
import '../progress/progress_screen.dart';
import '../review/review_screen.dart';

/// Главный экран: серии сезона, повторение, готовность. Всё, что игрок открывает каждый день.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});
  final Services services;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<(List<CatalogEntry>, List<Topic>)> _data = _load();
  String? _busyEpisode;

  Services get _s => widget.services;
  String get _l => _s.locale.code;

  Future<(List<CatalogEntry>, List<Topic>)> _load() async => (await _s.content.catalog(), await _s.content.curriculum());
  void _refresh() => setState(() => _data = _load());

  Future<void> _open(CatalogEntry e) async {
    setState(() => _busyEpisode = e.id);
    try {
      final (ep, qs) = await _s.content.episode(e.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EpisodeScreen(episode: ep, questions: qs, services: _s)));
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    } finally {
      if (mounted) setState(() => _busyEpisode = null);
    }
  }

  Future<void> _cdnDialog() async {
    final c = TextEditingController(text: _s.content.baseUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CDN'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t(_l, kk: 'Болдырмау', ru: 'Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) { _s.content.baseUrl = v; _refresh(); }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _s.locale,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text("Nomad's Way"),
            actions: [
              IconButton(onPressed: _cdnDialog, icon: const Icon(Icons.cloud_outlined), tooltip: 'CDN'),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'kk', label: Text('ҚАЗ')), ButtonSegment(value: 'ru', label: Text('РУС'))],
                  selected: {_l},
                  onSelectionChanged: (s) => _s.locale.set(s.first),
                ),
              ),
            ],
          ),
          body: FutureBuilder(
            future: _data,
            builder: (context, snap) {
              if (snap.hasError) return _Error(message: '${snap.error}', locale: _l, onRetry: _refresh);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final (catalog, topics) = snap.data!;
              return _content(catalog, topics);
            },
          ),
        ),
      );

  Widget _content(List<CatalogEntry> catalog, List<Topic> topics) {
    final cs = Theme.of(context).colorScheme;
    final attempts = _s.store.attempts();
    final due = _s.scheduler.due(_s.store.srs(), DateTime.now());
    final cachedQ = _s.content.cachedQuestions(catalog.map((e) => e.id)).map((q) => q.id).toSet();
    final dueCount = due.where(cachedQ.contains).length;
    final active = topics.where((tp) => tp.status != 'planned').toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ---- повторение
            Card.filled(
              color: dueCount > 0 ? cs.primaryContainer : cs.surfaceContainer,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                title: Text(t(_l, kk: 'Қайталау', ru: 'Повторить слабое')),
                subtitle: Text(dueCount > 0
                    ? t(_l, kk: '$dueCount сұрақ күтіп тұр', ru: '$dueCount вопросов ждут')
                    : t(_l, kk: 'Бүгінге бәрі қайталанды', ru: 'На сегодня всё повторено')),
                trailing: const Icon(Icons.chevron_right),
                onTap: dueCount == 0 ? null : () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewScreen(services: _s, catalogIds: catalog.map((e) => e.id).toList())));
                  setState(() {});
                },
              ),
            ),
            const SizedBox(height: 20),

            // ---- готовность
            _SectionTitle(t(_l, kk: 'ҰБТ-ға дайындық', ru: 'Готовность к ЕНТ'), action: TextButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgressScreen(services: _s, topics: topics)));
                setState(() {});
              },
              child: Text(t(_l, kk: 'Толығырақ', ru: 'Подробнее')),
            )),
            for (final tp in active) _TopicBar(title: tp.title.of(_l), value: _s.mastery.topic(tp.factIds, attempts)),
            const SizedBox(height: 20),

            // ---- серии
            _SectionTitle(t(_l, kk: '1-маусым · Қазақ хандығы', ru: 'Сезон 1 · Казахское ханство')),
            for (final e in catalog) _EpisodeTile(
              entry: e, locale: _l,
              result: _s.store.result(e.id),
              inProgress: _s.store.storySnapshot(e.id) != null,
              busy: _busyEpisode == e.id,
              onTap: () => _open(e),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.action});
  final String text; final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) action!,
        ]),
      );
}

class _TopicBar extends StatelessWidget {
  const _TopicBar({required this.title, required this.value});
  final String title; final double value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.bodyMedium)),
            Text('${(value * 100).round()}%', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: value, minHeight: 6)),
        ]),
      );
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.entry, required this.locale, required this.result, required this.inProgress, required this.busy, required this.onTap});
  final CatalogEntry entry; final String locale; final dynamic result; final bool inProgress; final bool busy; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String status;
    if (result != null) {
      status = '${result.correct} / ${result.total}';
    } else if (inProgress) {
      status = t(locale, kk: 'Жалғастыру', ru: 'Продолжить');
    } else {
      status = t(locale, kk: 'Бастау', ru: 'Начать');
    }
    return Card.outlined(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: CircleAvatar(backgroundColor: cs.surfaceContainerHighest, child: Text(entry.id.replaceFirst(RegExp(r'^s\d+e0?'), ''))),
        title: Text(entry.title.of(locale)),
        subtitle: Text([entry.era, t(locale, kk: '${entry.scenes} сахна · ${entry.questions} сұрақ', ru: '${entry.scenes} сцены · ${entry.questions} вопросов')].whereType<String>().join(' · ')),
        trailing: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(status, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        onTap: busy ? null : onTap,
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.locale, required this.onRetry});
  final String message; final String locale; final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t(locale, kk: 'Контент жүктелмеді', ru: 'Контент не загрузился'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(t(locale, kk: 'tools/serve.py іске қосылғанын тексеріңіз', ru: 'Проверьте, что запущен tools/serve.py'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: Text(t(locale, kk: 'Қайталау', ru: 'Повторить'))),
          ]),
        ),
      );
}
