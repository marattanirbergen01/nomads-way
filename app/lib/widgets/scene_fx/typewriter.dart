import 'package:flutter/widgets.dart';

/// Управление печатью снаружи: по первому тапу допечатать, по второму — дальше.
class TypewriterController extends ChangeNotifier {
  _TypewriterTextState? _state;

  bool get isDone => _state?._done ?? true;

  void complete() => _state?._complete();

  void _changed() => notifyListeners();
}

/// Текст, который печатается по буквам, с паузами на знаках препинания.
///
/// Невидимый хвост строки рисуется прозрачным, поэтому вёрстка не прыгает:
/// переносы строк сразу стоят там, где будут в конце.
class TypewriterText extends StatefulWidget {
  const TypewriterText(
    this.text, {
    super.key,
    this.style,
    this.controller,
    this.charsPerSecond = 38,
    this.delay = Duration.zero,
    this.onDone,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TypewriterController? controller;
  final double charsPerSecond;

  /// Пауза перед первой буквой (на ударных репликах — длиннее).
  final Duration delay;
  final VoidCallback? onDone;
  final TextAlign textAlign;

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.controller?._changed();
        widget.onDone?.call();
      }
    });
  late List<String> _chars;
  late List<double> _at; // момент появления каждой буквы, мс
  bool get _done => _c.isCompleted;
  bool _prepared = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prepared) _prepare();
  }

  @override
  void didUpdateWidget(TypewriterText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.text != widget.text) _prepare();
  }

  void _prepare() {
    _prepared = true;
    _chars = widget.text.characters.toList();
    _at = List.filled(_chars.length, 0);
    final step = 1000 / widget.charsPerSecond;
    var t = widget.delay.inMilliseconds.toDouble();
    for (var i = 0; i < _chars.length; i++) {
      _at[i] = t;
      t += step * _pause(_chars[i], i + 1 < _chars.length ? _chars[i + 1] : '');
    }
    _c
      ..duration = Duration(milliseconds: t.ceil())
      ..value = 0;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce || _chars.isEmpty) {
      _c.value = 1;
      widget.onDone?.call();
    } else {
      _c.forward();
    }
  }

  /// Множитель паузы после буквы. Многоточие тянется, тире даёт вдох.
  static double _pause(String ch, String next) {
    if (next.trim().isNotEmpty && ch != '…') return 1; // «т.е.», «1510.», числа
    return switch (ch) {
      '…' => 14,
      '.' || '!' || '?' => 9,
      ',' || ';' || ':' => 4,
      '—' || '–' => 5,
      _ => 1,
    };
  }

  void _complete() {
    if (!_done) _c.value = 1;
  }

  int _visible() {
    final ms = _c.value * (_c.duration?.inMilliseconds ?? 0);
    var lo = 0, hi = _at.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_at[mid] <= ms) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    // Хвост строки занимает место, но не виден: без цвета и без тени, иначе тень проступит раньше букв.
    final hidden = style.copyWith(color: const Color(0x00000000), shadows: const []);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final n = _visible();
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: _chars.take(n).join(), style: style),
            TextSpan(text: _chars.skip(n).join(), style: hidden),
          ]),
          textAlign: widget.textAlign,
          semanticsLabel: widget.text,
        );
      },
    );
  }
}
