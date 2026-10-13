import 'dart:math';
import '../data/models/bank.dart';
import '../data/models/question.dart';

/// Два режима на банке школы.
/// mock  — «Сынақ ҰБТ», копия ЕНТ по спецификации НЦТ: 10 одиночных + 2 контекста по 5.
/// quick — «Жылдам жаттығу»: 15 одиночных + 1 контекст по 5.
enum MockMode {
  mock(singles: 10, contexts: 2, kind: 'mock'),
  quick(singles: 15, contexts: 1, kind: 'quick');

  const MockMode({required this.singles, required this.contexts, required this.kind});
  final int singles;
  final int contexts;
  /// Ключ в истории тестов (`TestResult.kind`).
  final String kind;
  static const perContext = 5;
  int get total => singles + contexts * perContext;
}

/// Готовый вариант. Вопросы контекста идут блоком сразу после одиночных и не отрываются от текста.
class MockVariant {
  MockVariant({required this.mode, required this.questions, required this.contexts});
  final MockMode mode;
  final List<Question> questions;
  /// Контексты в порядке блоков: [0] — «Мәтін 1» (задания 11–15), [1] — «Мәтін 2».
  final List<BankContext> contexts;

  /// Номер блока контекста для задания i (0-based): 0, 1… или null у одиночных.
  int? blockOf(int i) => i < mode.singles ? null : (i - mode.singles) ~/ MockMode.perContext;
  BankContext? contextOf(int i) => switch (blockOf(i)) { final b? => contexts[b], null => null };
  /// Первое задание блока — перед ним показывается сам текст или карта.
  bool startsBlock(int i) => blockOf(i) != null && (i - mode.singles) % MockMode.perContext == 0;
}

class MockComposer {
  /// Не больше стольких одиночных вопросов на одну тему ЕНТ — чтобы вариант шёл по всему курсу.
  static const maxPerTopic = 2;

  static int eligibleSingles(Bank b) => b.questions.where((q) => q.eligible && q.format == QFormat.single).length;
  static List<BankContext> eligibleContexts(Bank b) =>
      [for (final c in b.contexts) if (b.eligibleOf(c).length >= MockMode.perContext) c];

  static bool canCompose(Bank b, MockMode m) =>
      eligibleSingles(b) >= m.singles && eligibleContexts(b).length >= m.contexts;

  static MockVariant composeMock(Bank bank, {required Random random, Set<String> recent = const {}}) =>
      compose(bank, MockMode.mock, random: random, recent: recent);

  static MockVariant composeQuick(Bank bank, {required Random random, Set<String> recent = const {}}) =>
      compose(bank, MockMode.quick, random: random, recent: recent);

  /// [recent] — вопросы последних вариантов ученика: берутся, только если других не хватает.
  static MockVariant compose(Bank bank, MockMode mode, {required Random random, Set<String> recent = const {}}) {
    if (!canCompose(bank, mode)) throw StateError('в банке не хватает вопросов для ${mode.name}');

    // ---- одиночные: сперва свежие, потом уже встречавшиеся; тема — не больше maxPerTopic
    final singles = bank.questions.where((q) => q.eligible && q.format == QFormat.single).toList()..shuffle(random);
    final ordered = [...singles.where((q) => !recent.contains(q.id)), ...singles.where((q) => recent.contains(q.id))];
    final picked = <Question>[];
    final perTopic = <String, int>{};
    for (final q in ordered) {
      if (picked.length == mode.singles) break;
      final t = q.topic;
      if (t != null && (perTopic[t] ?? 0) >= maxPerTopic) continue;
      picked.add(q);
      if (t != null) perTopic[t] = (perTopic[t] ?? 0) + 1;
    }
    // банк мал для ограничения по темам — добираем без него, но без повторов
    for (final q in ordered) {
      if (picked.length == mode.singles) break;
      if (!picked.contains(q)) picked.add(q);
    }

    // ---- контексты: разные, случайные, свежие вперёд; из каждого — случайные 5 в случайном порядке
    final ctx = eligibleContexts(bank)..shuffle(random);
    bool seen(BankContext c) => c.questionIds.any(recent.contains);
    final chosen = [...ctx.where((c) => !seen(c)), ...ctx.where(seen)].take(mode.contexts).toList();
    final blocks = <Question>[
      for (final c in chosen) ...(bank.eligibleOf(c)..shuffle(random)).take(MockMode.perContext),
    ];

    return MockVariant(mode: mode, questions: [...picked, ...blocks], contexts: chosen);
  }
}
