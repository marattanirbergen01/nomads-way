import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../data/models/question.dart';
import 'drill_screen.dart';

/// Қателіктермен жұмыс: вопросы, у которых по SRS наступила дата. До 20 за раз.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key, required this.services, required this.bank});
  final Services services; final List<Question> bank;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    final byId = {for (final q in bank) q.id: q};
    final due = services.scheduler.due(services.store.srs(), DateTime.now());
    final qs = [for (final id in due) if (byId[id] != null) byId[id]!].take(20).toList();
    return DrillScreen(services: services, questions: qs, label: s('review'), doneTitle: s('review.done'), doneCaption: s('review.sub'));
  }
}
