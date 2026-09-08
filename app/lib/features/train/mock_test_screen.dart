import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../data/models/question.dart';
import '../../engine/quiz_runner.dart';
import 'drill_screen.dart';

/// Сынақ ҰБТ: 10 одиночных + 10 по контексту из всех загруженных серий.
class MockTestScreen extends StatelessWidget {
  const MockTestScreen({super.key, required this.services, required this.bank});
  final Services services; final List<Question> bank;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    return DrillScreen(
      services: services,
      questions: QuizRunner.composeFinal(bank, single: 10, context: 10),
      label: s('mock'), doneTitle: s('mock.title'), doneCaption: s('ep.done.sub'), recordAsMock: true,
    );
  }
}
