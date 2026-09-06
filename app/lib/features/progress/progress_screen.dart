import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../data/models/curriculum.dart';

/// Готовность по темам и фактам. Экран, который откроет родитель, — число должно быть честным.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.services, required this.topics});
  final Services services;
  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final l = services.locale.code;
    final attempts = services.store.attempts();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t(l, kk: 'ҰБТ-ға дайындық', ru: 'Готовность к ЕНТ'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final tp in topics) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Row(children: [
                    Expanded(child: Text(tp.title.of(l), style: Theme.of(context).textTheme.titleMedium)),
                    if (tp.status == 'planned')
                      Text(t(l, kk: 'жақында', ru: 'скоро'), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant))
                    else
                      Text('${(services.mastery.topic(tp.factIds, attempts) * 100).round()}%', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.primary)),
                  ]),
                ),
                if (tp.status != 'planned')
                  for (final f in tp.facts) _FactRow(text: f.text.of(l), value: services.mastery.fact(f.id, attempts)),
              ],
              const SizedBox(height: 16),
              Text(
                t(l,
                    kk: 'Пайыз — соңғы үш жауап бойынша есептеледі, жаңа жауаптар салмақтырақ. Жауап берілмеген факт 0% деп саналады.',
                    ru: 'Процент считается по последним трём ответам, свежие весят больше. Факт без ответов считается за 0%.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.text, required this.value});
  final String text; final double value;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = value >= 0.8 ? cs.primary : value > 0 ? cs.tertiary : cs.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 5, right: 12), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(width: 12),
        Text('${(value * 100).round()}%', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
