import 'dart:io' show File;
import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/local/progress_repository.dart';
import '../../data/models/bank.dart';
import '../../data/models/question.dart';
import '../../engine/awards.dart';
import '../../engine/mock_composer.dart';
import '../../engine/quiz_runner.dart';
import '../../widgets/art.dart';
import '../../widgets/common.dart';
import '../path/path_tab.dart' show LoadError;
import '../readiness/award_screen.dart';
import '../../widgets/scroll_buttons.dart';

/// Пробник ЕНТ на банке школы. Один экран для «Сынақ ҰБТ» (10 + 5 + 5) и «Жылдам жаттығу» (15 + 5).
///
/// Вопрос контекста никогда не показывается без своего текста или карты: перед блоком —
/// сам контекст целиком, на каждом вопросе блока — он же сверху, сворачиваемый.
/// Вопросы банка — на языке интерфейса, если есть перевод (иначе kk); объяснений у них нет.
class MockScreen extends StatefulWidget {
  const MockScreen({super.key, required this.services, required this.mode});
  final Services services;
  final MockMode mode;
  @override
  State<MockScreen> createState() => _MockScreenState();
}

class _MockScreenState extends State<MockScreen> {
  Services get _s => widget.services;
  MockMode get _m => widget.mode;

  double? _progress;
  Object? _error;
  MockVariant? _v;
  QuizRunner? _quiz;
  AnswerResult? _result;
  /// Варианты в том порядке, как их видел ученик, — разбор показывает тот же порядок и те же буквы.
  List<AnswerOption> _shown = const [];
  /// Показываем контекст целиком перед первым вопросом блока.
  bool _intro = false;
  /// Контекст над вопросом развёрнут. Сохраняется внутри блока.
  bool _ctxOpen = true;
  bool _recorded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _error = null; _progress = null; });
    try {
      final bank = await _s.content.bank(onProgress: (v) { if (mounted) setState(() => _progress = v); });
      final v = MockComposer.compose(bank, _m, random: Random(), recent: _s.store.recentBankQuestions());
      if (!mounted) return;
      setState(() { _v = v; _quiz = QuizRunner(v.questions); _intro = v.startsBlock(0); });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _answer(String optionId) {
    _shown = _quiz!.current()!.options;
    final r = _quiz!.answer(optionId);
    // В прогресс фактов серий банк не идёт: Attempt.fact = ent.<тема>, mastery таких фактов не знает.
    _s.store.addAttempt(_quiz!.attempts.last);
    setState(() => _result = r);
  }

  Future<void> _next() async {
    final q = _quiz!;
    setState(() {
      _result = null;
      if (!q.done && _v!.startsBlock(q.index)) { _intro = true; _ctxOpen = true; }
    });
    if (!q.done || _recorded) return;
    _recorded = true;
    await _s.store.addTest(TestResult(
      kind: _m.kind, correct: q.correctCount, total: q.total, at: DateTime.now(),
      questions: [for (final x in q.questions) x.id],
    ));
    final granted = <Award>[];
    if (_m == MockMode.mock) {
      for (final a in _s.awards.onTest(correct: q.correctCount, total: q.total)) {
        await _s.store.grantAward(a.id);
        granted.add(a);
      }
    }
    final streak = await _s.checkStreakAward();
    if (streak != null) granted.add(streak);
    _s.touch();
    if (!mounted) return;
    for (final a in granted) { await AwardScreen.show(context, _s, a, _s.store.awards()[a.id] ?? 1); }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = LoadError(services: _s, message: '$_error', onRetry: _load);
    } else if (_quiz == null) {
      body = _Loading(services: _s, progress: _progress, bytes: _s.content.commonSync?.bank?.bundle?.bytes);
    } else if (_result != null) {
      // разбор раньше итога: после 20-го ответа квиз уже done, но разбор последнего вопроса нужен
      body = _Feedback(services: _s, variant: _v!, index: _quiz!.index - 1, result: _result!, shown: _shown, onNext: _next);
    } else if (_quiz!.done) {
      body = _Score(services: _s, variant: _v!, quiz: _quiz!);
    } else if (_intro) {
      body = _ContextIntro(services: _s, variant: _v!, index: _quiz!.index, onGo: () => setState(() => _intro = false));
    } else {
      body = _Question(
        services: _s, variant: _v!, index: _quiz!.index, presented: _quiz!.current()!,
        ctxOpen: _ctxOpen, onToggle: () => setState(() => _ctxOpen = !_ctxOpen), onAnswer: _answer,
      );
    }
    return Scaffold(
      backgroundColor: C.ground,
      appBar: AppBar(backgroundColor: C.ground, foregroundColor: C.ink, elevation: 0, scrolledUnderElevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context))),
      // ключ — на каждый экран свой: новая страница начинается сверху
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
          child: ScrollButtons(key: ValueKey('${_quiz?.index}-$_intro-${_result != null}-${_error != null}'), child: body)))),
    );
  }
}

// ---------------------------------------------------------------- загрузка банка

class _Loading extends StatelessWidget {
  const _Loading({required this.services, required this.progress, this.bytes});
  final Services services; final double? progress; final int? bytes;
  @override
  Widget build(BuildContext context) {
    final mb = bytes == null ? '' : ' · ${(bytes! / 1024 / 1024).toStringAsFixed(1)} МБ';
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${services.s('bank.loading')}$mb', style: st(15, color: C.inkSoft), textAlign: TextAlign.center),
      const SizedBox(height: 14),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress, minHeight: 6, color: C.gold, backgroundColor: C.card),
      ),
    ])));
  }
}

// ---------------------------------------------------------------- шапка задания

class _Head extends StatelessWidget {
  const _Head({required this.services, required this.variant, required this.index});
  final Services services; final MockVariant variant; final int index;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    final block = variant.blockOf(index);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _Tag(variant.mode == MockMode.mock ? s('mock') : s('quick')),
        if (block != null) ...[const SizedBox(width: 8), _Tag('${s('ctx')} ${block + 1}', filled: true)],
        const Spacer(),
        Text('${index + 1} / ${variant.questions.length}', style: st(14, w: 600, color: C.inkSoft)),
      ]),
      // перевод банка — черновик и может быть не у всех вопросов: тогда честно говорим, что вопрос на казахском
      if (!services.s.isKk && !variant.questions[index].stem.has(services.l)) ...[
        const SizedBox(height: 8),
        Text(s('bank.kk.only'), style: st(12, color: C.inkFaint)),
      ],
    ]);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.filled = false});
  final String text; final bool filled;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? C.gold : null,
          border: Border.all(color: C.gold), borderRadius: BorderRadius.circular(4)),
        child: Text(text.toUpperCase(), style: st(11, w: 600, color: filled ? C.ground : C.gold, spacing: 1.2)),
      );
}

// ---------------------------------------------------------------- контекст

/// Контекст целиком перед блоком: «Мәтін 1 · 11–15 тапсырмалар».
class _ContextIntro extends StatelessWidget {
  const _ContextIntro({required this.services, required this.variant, required this.index, required this.onGo});
  final Services services; final MockVariant variant; final int index; final VoidCallback onGo;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    final b = variant.blockOf(index)!;
    final c = variant.contexts[b];
    final from = index + 1, to = index + MockMode.perContext;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), children: [
      _Head(services: services, variant: variant, index: index),
      const SizedBox(height: 18),
      Text('${s('ctx')} ${b + 1}', style: st(24, w: 700)),
      const SizedBox(height: 4),
      Text('$from–$to ${s('tasks')}', style: st(14, color: C.inkSoft)),
      const SizedBox(height: 16),
      _ContextBody(services: services, context: c),
      const SizedBox(height: 16),
      Text(c.isImage ? s('ctx.intro.map') : s('ctx.intro'), style: st(13, color: C.inkSoft, height: 1.45)),
      const SizedBox(height: 20),
      GoldButton(label: s('to.questions'), onTap: onGo),
    ]);
  }
}

/// Текст, картинка с подписью, или оба.
class _ContextBody extends StatelessWidget {
  const _ContextBody({required this.services, required this.context, this.maxTextHeight});
  final Services services; final BankContext context; final double? maxTextHeight;
  @override
  Widget build(BuildContext ctx) {
    final c = context;
    final text = c.text == null ? null : Text(c.text!.of(services.l), style: st(16, height: 1.55));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.image != null) ...[
        BankImage(services: services, path: c.image!),
        if (c.caption != null) ...[
          const SizedBox(height: 6),
          Text(c.caption!.of(services.l), style: st(12.5, color: C.inkSoft), textAlign: TextAlign.center),
        ],
        if (text != null) const SizedBox(height: 12),
      ],
      if (text != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: C.card, borderRadius: BorderRadius.circular(8)),
          child: maxTextHeight == null
              ? text
              : ConstrainedBox(constraints: BoxConstraints(maxHeight: maxTextHeight!), child: Scrollbar(child: SingleChildScrollView(primary: false, child: text))),
        ),
    ]);
  }
}

/// Контекст над вопросом: сворачивается, чтобы не мешать вариантам, но всегда под рукой.
class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.services, required this.context, required this.number, required this.open, required this.onToggle});
  final Services services; final BankContext context; final int number; final bool open; final VoidCallback onToggle;
  @override
  Widget build(BuildContext ctx) {
    final s = services.s;
    final c = context;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: C.gold.withValues(alpha: .45)), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              Icon(c.isImage ? Icons.map_outlined : Icons.article_outlined, color: C.gold, size: 19),
              const SizedBox(width: 8),
              Expanded(child: Text('${c.isImage ? s('ctx.map') : s('ctx')} $number', style: st(14, w: 600, color: C.gold))),
              Text(open ? s('ctx.hide') : s('ctx.show'), style: st(13, color: C.inkSoft)),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: C.inkSoft),
            ]),
          ),
        ),
        if (open) Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: _ContextBody(services: services, context: c, maxTextHeight: 240),
        ),
      ]),
    );
  }
}

/// Карта или схема банка. По нажатию — на весь экран с увеличением: подписи на картах мелкие.
class BankImage extends StatelessWidget {
  const BankImage({super.key, required this.services, required this.path, this.height = 220});
  final Services services; final String path; final double height;
  @override
  Widget build(BuildContext context) {
    final file = services.content.bankImageFile(path);
    final url = services.content.bankImageUrl(path);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _ZoomView(file: file, url: url, hint: services.s('tap.zoom')),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      )),
      child: Stack(children: [
        Container(
          height: height,
          decoration: BoxDecoration(color: const Color(0xFFF4EEDF), borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Art(file: file, url: url, fit: BoxFit.contain, height: height),
        ),
        Positioned(right: 8, bottom: 8, child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: C.ground.withValues(alpha: .75), shape: BoxShape.circle),
          child: const Icon(Icons.zoom_in_rounded, color: C.gold, size: 20),
        )),
      ]),
    );
  }
}

class _ZoomView extends StatefulWidget {
  const _ZoomView({required this.file, required this.url, required this.hint});
  final File? file; final String url; final String hint;
  @override
  State<_ZoomView> createState() => _ZoomViewState();
}

class _ZoomViewState extends State<_ZoomView> {
  final _tc = TransformationController();
  TapDownDetails? _tap;

  void _doubleTap() {
    if (_tc.value.getMaxScaleOnAxis() > 1.01) { _tc.value = Matrix4.identity(); return; }
    final p = _tap?.localPosition ?? Offset.zero;
    const k = 2.6;
    _tc.value = Matrix4.identity()..translateByDouble(-p.dx * (k - 1), -p.dy * (k - 1), 0, 1)..scaleByDouble(k, k, 1, 1);
  }

  @override
  void dispose() { _tc.dispose(); super.dispose(); }

  static Widget _broken(BuildContext _, Object __, StackTrace? ___) =>
      const Icon(Icons.broken_image_outlined, color: C.inkSoft, size: 48);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF14100C),
        body: Stack(children: [
          Positioned.fill(child: GestureDetector(
            onDoubleTapDown: (d) => _tap = d,
            onDoubleTap: _doubleTap,
            child: InteractiveViewer(
              transformationController: _tc, minScale: 1, maxScale: 6,
              // без cacheWidth: при увеличении нужны все пиксели карты (они до 1600 px)
              child: Center(child: widget.file != null
                  ? Image.file(widget.file!, fit: BoxFit.contain, errorBuilder: _broken)
                  : Image.network(widget.url, fit: BoxFit.contain, errorBuilder: _broken)),
            ),
          )),
          // карты светлые: без подложки светлый крестик на них не виден
          Positioned(top: MediaQuery.of(context).padding.top + 8, right: 12, child: Material(
            color: C.ground.withValues(alpha: .8), shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: C.ink, size: 26),
              onPressed: () => Navigator.pop(context),
            ),
          )),
        ]),
      );
}

// ---------------------------------------------------------------- вопрос

const _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

class _Question extends StatelessWidget {
  const _Question({
    required this.services, required this.variant, required this.index, required this.presented,
    required this.ctxOpen, required this.onToggle, required this.onAnswer,
  });
  final Services services; final MockVariant variant; final int index; final Presented presented;
  final bool ctxOpen; final VoidCallback onToggle; final void Function(String) onAnswer;

  @override
  Widget build(BuildContext context) {
    final q = presented.question;
    final c = variant.contextOf(index);
    return ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), children: [
      _Head(services: services, variant: variant, index: index),
      const SizedBox(height: 14),
      if (c != null) ...[
        _ContextCard(services: services, context: c, number: variant.blockOf(index)! + 1, open: ctxOpen, onToggle: onToggle),
        const SizedBox(height: 16),
      ],
      if (q.image != null) ...[
        BankImage(services: services, path: q.image!),
        const SizedBox(height: 14),
      ],
      Text(q.stem.of(services.l), style: st(20, w: 600, height: 1.3)),
      const SizedBox(height: 18),
      for (var i = 0; i < presented.options.length; i++) ...[
        _Option(letter: _letters[i], text: presented.options[i].text.of(services.l), onTap: () => onAnswer(presented.options[i].id)),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

enum _Mark { none, right, wrong, dim }

class _Option extends StatelessWidget {
  const _Option({required this.letter, required this.text, this.onTap, this.mark = _Mark.none, this.tag});
  final String letter; final String text; final VoidCallback? onTap; final _Mark mark;
  /// Подпись словами под текстом варианта: «Дұрыс жауап» / «Сіздің жауабыңыз» — различимо и без цвета.
  final String? tag;
  @override
  Widget build(BuildContext context) {
    final tone = switch (mark) { _Mark.right => C.right, _Mark.wrong => C.wrong, _ => null };
    final fill = tone == null ? C.card : Color.alphaBlend(tone.withValues(alpha: .16), C.card);
    final icon = switch (mark) {
      _Mark.right => const Icon(Icons.check_circle_rounded, color: C.right, size: 24),
      _Mark.wrong => const Icon(Icons.cancel_rounded, color: C.wrong, size: 24),
      _ => null,
    };
    return Opacity(
      opacity: mark == _Mark.dim ? .5 : 1,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: tone ?? Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Text(letter, style: st(15, w: 700, color: tone ?? C.gold)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: st(16, height: 1.35)),
                if (tag != null) ...[
                  const SizedBox(height: 3),
                  Text(tag!, style: st(12, w: 600, color: tone ?? C.inkSoft)),
                ],
              ])),
              if (icon != null) ...[const SizedBox(width: 8), icon],
            ]),
          ),
        ),
      ),
    );
  }
}

/// После ответа: верно/неверно и правильный вариант прямо в списке. Пустого блока объяснения нет.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.services, required this.variant, required this.index, required this.result, required this.shown, required this.onNext});
  final Services services; final MockVariant variant; final int index; final AnswerResult result;
  final List<AnswerOption> shown; final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    final q = result.question;
    final ok = result.correct;
    return ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), children: [
      _Head(services: services, variant: variant, index: index),
      const SizedBox(height: 16),
      Text(ok ? s('correct') : s('wrong'), style: st(26, w: 700, color: ok ? C.right : C.wrong)),
      const SizedBox(height: 10),
      Text(q.stem.of(services.l), style: st(16, w: 600, height: 1.35, color: C.inkSoft)),
      const SizedBox(height: 14),
      for (var i = 0; i < shown.length; i++) ...[
        _Option(
          letter: _letters[i], text: shown[i].text.of(services.l),
          mark: shown[i].correct ? _Mark.right : shown[i].id == result.chosen.id ? _Mark.wrong : _Mark.dim,
          tag: shown[i].correct ? s('tag.right') : shown[i].id == result.chosen.id ? s('tag.yours') : null,
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 14),
      GoldButton(label: s('next'), onTap: onNext),
    ]);
  }
}

// ---------------------------------------------------------------- итог

class _Score extends StatelessWidget {
  const _Score({required this.services, required this.variant, required this.quiz});
  final Services services; final MockVariant variant; final QuizRunner quiz;
  @override
  Widget build(BuildContext context) {
    final s = services.s;
    final m = variant.mode;
    final ok = [for (final a in quiz.attempts) a.correct];
    final first = ok.take(m.singles).where((x) => x).length;
    final second = ok.skip(m.singles).where((x) => x).length;
    final wrong = [for (var i = 0; i < ok.length; i++) if (!ok[i]) i];
    return ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 24), children: [
      Text(m == MockMode.mock ? s('mock.title') : s('quick.title'), style: st(22, w: 600), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('${quiz.correctCount} / ${quiz.total}', style: st(56, w: 800, color: C.gold), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _Part(range: '1–${m.singles}', title: s('part.single'), got: first, of: m.singles)),
        const SizedBox(width: 10),
        Expanded(child: _Part(range: '${m.singles + 1}–${m.total}', title: s('part.ctx'), got: second, of: m.total - m.singles)),
      ]),
      const SizedBox(height: 22),
      if (wrong.isEmpty)
        Text(s('no.mistakes'), style: st(16, w: 600, color: C.gold), textAlign: TextAlign.center)
      else ...[
        SectionTitle(s('mistakes.list'), trailing: '${wrong.length}'),
        for (final i in wrong) Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GroundCard(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([
              '${s('task')} ${i + 1}',
              if (variant.blockOf(i) != null) '${s('ctx')} ${variant.blockOf(i)! + 1}',
            ].join(' · '), style: st(12, w: 600, color: C.inkSoft)),
            const SizedBox(height: 6),
            Text(quiz.questions[i].stem.of(services.l), style: st(15, w: 600, height: 1.35)),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${s('your.answer')} ', style: st(13, color: C.inkSoft)),
              TextSpan(text: quiz.picks[i].text.of(services.l), style: st(13.5, color: C.wrong)),
            ])),
            const SizedBox(height: 3),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${s('right.answer')} ', style: st(13, color: C.inkSoft)),
              TextSpan(text: quiz.questions[i].correct.text.of(services.l), style: st(13.5, w: 600, color: C.right)),
            ])),
          ])),
        ),
      ],
      const SizedBox(height: 16),
      GoldButton(label: s('done'), onTap: () => Navigator.of(context).pop()),
    ]);
  }
}

class _Part extends StatelessWidget {
  const _Part({required this.range, required this.title, required this.got, required this.of});
  final String range; final String title; final int got; final int of;
  @override
  Widget build(BuildContext context) => GroundCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(range, style: st(12, w: 600, color: C.inkSoft)),
          Text(title, style: st(13, color: C.inkSoft)),
          const SizedBox(height: 6),
          Text.rich(TextSpan(children: [
            TextSpan(text: '$got', style: st(24, w: 700)),
            TextSpan(text: ' / $of', style: st(14, color: C.inkSoft)),
          ])),
        ]),
      );
}
