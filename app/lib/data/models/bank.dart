import '../../core/l10n.dart';
import 'question.dart';

/// Банк пробника ЕНТ (build/bank/bank.json). Вопросы школы, только kk.
/// Не привязан к сюжету: факта нет, в `Attempt.fact` пишется `ent.<тема ЕНТ>`.
class Bank {
  Bank({required this.questions, required this.contexts});
  final List<Question> questions;
  final List<BankContext> contexts;

  late final Map<String, Question> byId = {for (final q in questions) q.id: q};
  late final Map<String, BankContext> contextById = {for (final c in contexts) c.id: c};

  /// Годные вопросы контекста, в исходном порядке.
  List<Question> eligibleOf(BankContext c) => [
        for (final id in c.questionIds)
          if (byId[id] case final q? when q.eligible && q.format == QFormat.context && q.context == c.id) q,
      ];

  static const sourceId = 'school_tests_2026';

  factory Bank.fromJson(Map<String, dynamic> j) => Bank(
        contexts: [for (final c in j['contexts'] as List) BankContext.fromJson((c as Map).cast<String, dynamic>())],
        questions: [for (final q in j['questions'] as List) _question((q as Map).cast<String, dynamic>())],
      );

  static Question _question(Map<String, dynamic> j) {
    final id = j['id'] as String;
    final topic = j['topic'];
    final answer = (j['answer'] as num).toInt();
    final opts = j['options'] as List;
    return Question(
      id: id,
      fact: topic == null ? '' : 'ent.$topic',
      topic: topic == null ? null : 'ent.$topic',
      format: j['format'] == 'context' ? QFormat.context : QFormat.single,
      context: j['context'],
      difficulty: 2,
      stem: L10n.fromJson((j['stem'] as Map).cast<String, dynamic>()),
      options: [
        for (var i = 0; i < opts.length; i++)
          AnswerOption(id: '$id.$i', text: L10n.fromJson((opts[i] as Map).cast<String, dynamic>()), correct: i == answer),
      ],
      explain: const L10n({}),
      source: sourceId,
      image: j['image'],
      shuffle: j['shuffle'] != false,
      eligible: j['check'] != true && j['image_missing'] != true,
      season: (j['season'] as num?)?.toInt(),
    );
  }
}

/// Текст (документ, биография), карта/схема или оба. Вопросы к нему идут блоком.
class BankContext {
  const BankContext({required this.id, this.text, this.image, this.caption, required this.questionIds});
  final String id;
  final L10n? text;
  final String? image;
  final L10n? caption;
  final List<String> questionIds;
  bool get isImage => image != null && text == null;

  factory BankContext.fromJson(Map<String, dynamic> j) => BankContext(
        id: j['id'],
        text: j['text'] == null ? null : L10n.fromJson((j['text'] as Map).cast<String, dynamic>()),
        image: j['image'],
        caption: j['caption'] == null ? null : L10n.fromJson((j['caption'] as Map).cast<String, dynamic>()),
        questionIds: (j['questions'] as List).cast<String>(),
      );
}
