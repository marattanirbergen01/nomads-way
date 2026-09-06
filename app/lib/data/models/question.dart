import '../../core/l10n.dart';

enum QFormat { single, context }

class Question {
  Question({
    required this.id, required this.fact, required this.topic, required this.format, this.context,
    required this.difficulty, required this.stem, required this.options, required this.explain, required this.source,
  });
  final String id;
  final String fact;
  final String? topic;
  final QFormat format;
  final String? context;
  final int difficulty;
  final L10n stem;
  final List<AnswerOption> options;
  final L10n explain;
  final String source;

  AnswerOption get correct => options.firstWhere((o) => o.correct);

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id'],
        fact: j['fact'],
        topic: j['topic'],
        format: j['format'] == 'context' ? QFormat.context : QFormat.single,
        context: j['context'],
        difficulty: j['difficulty'],
        stem: L10n.fromJson(j['stem']),
        options: [for (final o in j['options']) AnswerOption.fromJson(o)],
        explain: L10n.fromJson(j['explain']),
        source: j['source'],
      );
}

class AnswerOption {
  AnswerOption({required this.id, required this.text, required this.correct});
  final String id;
  final L10n text;
  final bool correct;
  factory AnswerOption.fromJson(Map<String, dynamic> j) => AnswerOption(id: j['id'], text: L10n.fromJson(j['text']), correct: j['correct'] == true);
}
