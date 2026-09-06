import 'package:flutter/material.dart';
import '../../core/locale_controller.dart';
import '../../data/remote/bundle_loader.dart';
import '../episode/episode_screen.dart';

/// Временный вход: адрес CDN + запуск серии. Позже — карта сезона.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.locale});
  final LocaleController locale;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _url = TextEditingController(text: 'http://localhost:8787');
  final _ep = TextEditingController(text: 's1e01');
  String? _error;
  bool _busy = false;

  Future<void> _start() async {
    setState(() { _busy = true; _error = null; });
    try {
      final (ep, qs) = await BundleLoader(baseUrl: _url.text.trim()).load(_ep.text.trim());
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EpisodeScreen(episode: ep, questions: qs, locale: widget.locale),
      ));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.locale.code;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nomad's Way"),
        actions: [_LangToggle(locale: widget.locale)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l == 'kk' ? 'Серияны жүктеу' : 'Загрузить серию', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextField(controller: _url, decoration: const InputDecoration(labelText: 'CDN', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _ep, decoration: InputDecoration(labelText: l == 'kk' ? 'Серия' : 'Серия', border: const OutlineInputBorder())),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _start,
                  child: Text(_busy ? '…' : (l == 'kk' ? 'Бастау' : 'Начать')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                  Text(l == 'kk' ? 'tools/serve.py іске қосылғанын тексеріңіз.' : 'Проверьте, что запущен tools/serve.py.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.locale});
  final LocaleController locale;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'kk', label: Text('ҚАЗ')), ButtonSegment(value: 'ru', label: Text('РУС'))],
          selected: {locale.code},
          onSelectionChanged: (s) => locale.set(s.first),
        ),
      );
}
