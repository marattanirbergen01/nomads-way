import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../data/models/curriculum.dart';
import '../../widgets/avatar.dart';
import '../../widgets/common.dart';
import '../../widgets/ornament.dart';
import 'faq_screen.dart';
import 'settings_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key, required this.services});
  final Services services;
  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Services get _s => widget.services;
  List<Topic> _topics = const [];
  @override
  void initState() {
    super.initState();
    _s.changes.addListener(_r); _s.locale.addListener(_r);
    _s.content.curriculum().then((t) { if (mounted) setState(() => _topics = t); }).catchError((_) {});
  }
  @override
  void dispose() { _s.changes.removeListener(_r); _s.locale.removeListener(_r); super.dispose(); }
  void _r() { if (mounted) setState(() {}); }

  Future<void> _editName() async {
    final c = TextEditingController(text: _s.store.playerName);
    final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: C.card,
      title: Text(_s.s('avatar.name'), style: st(17, w: 600)),
      content: TextField(controller: c, autofocus: true, maxLength: 20, style: st(16), decoration: const InputDecoration(counterStyle: TextStyle(color: C.inkFaint))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_s.s('cancel'), style: st(14, color: C.inkSoft))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text('OK', style: st(14, w: 600, color: C.gold))),
      ],
    ));
    if (v != null) { await _s.store.setPlayerName(v); _s.touch(); }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s.s;
    final facts = _topics.where((t) => !t.isPeriod && !t.planned).expand((t) => t.factIds).toList();
    final ready = facts.isEmpty ? 0.0 : _s.readiness(facts);
    final awardsN = _s.store.awards().values.fold(0, (a, b) => a + b);
    final streak = _s.streakDays();
    final look = _s.store.look;
    final name = _s.store.playerName.isEmpty ? 'Айдар' : _s.store.playerName;

    return ListView(padding: EdgeInsets.zero, children: [
      Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.skyTop, C.skyMid, C.skyWarm], stops: [0, .62, 1])),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 6, 20, 20),
        child: Stack(children: [
          Positioned(right: -8, top: 0, child: IconButton(
            onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(services: _s))); _s.touch(); },
            icon: const Icon(Icons.settings_outlined, color: C.onSky, size: 23))),
          Column(children: [
            const SizedBox(height: 4),
            AvatarCircle(size: 96, look: look, services: _s),
            const SizedBox(height: 12),
            InkWell(onTap: _editName, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(name, style: st(24, w: 700, color: C.onSky)), const SizedBox(width: 8),
              const Icon(Icons.edit_outlined, size: 17, color: C.onSkySoft),
            ]))),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Stat('${(ready * 100).round()}%', s('readiness')), const SizedBox(width: 26),
              _Stat('$awardsN', s('award.c')), const SizedBox(width: 26),
              _Stat('$streak', s('streak')),
            ]),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 3; i++) Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: GestureDetector(
                onTap: () async { await _s.store.setLook(i); _s.touch(); },
                child: Opacity(opacity: look == i ? 1 : .5, child: AvatarCircle(size: 44, look: i, ring: look == i, services: _s)),
              )),
            ]),
          ]),
        ]),
      ),
      const HorizonLine(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), child: Column(children: [
        _Row(icon: Icons.credit_card_outlined, title: s('subscription'), sub: s('subscription.sub'), trailing: _SoonChip(s('soon'))),
        _Row(icon: Icons.help_outline_rounded, title: s('faq'), sub: s('faq.sub'), onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FaqScreen(services: _s)))),
        _Row(icon: Icons.description_outlined, title: s('sources.hist'), sub: s('sources.sub'), onTap: () => _sources(context)),
        _Row(icon: Icons.chat_bubble_outline_rounded, title: s('contact'), trailing: _SoonChip(s('soon'))),
        Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 0), child: Row(children: [
          for (final ic in [Icons.camera_alt_outlined, Icons.music_note_outlined, Icons.send_outlined, Icons.mail_outline_rounded])
            Padding(padding: const EdgeInsets.only(right: 10), child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: C.cardHigh)), child: Icon(ic, size: 19, color: C.inkFaint))),
        ])),
      ])),
    ]);
  }

  void _sources(BuildContext context) => showModalBottomSheet(
        context: context, backgroundColor: const Color(0xF21A140F),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 36), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_s.s('sources.hist'), style: st(17, w: 600)), const SizedBox(height: 12),
          Text(t(_s.l,
              kk: 'Деректер академиялық «Қазақстан тарихы» (5 томдық) және Мұхаммед Хайдар Дулатидің «Тарих-и Рашиди» еңбегіне сүйенеді. Әр сұрақтың дереккөзі талдауда көрсетіледі.\n\nТарихшы визасы әлі қойылмаған — серия сынақ режимінде.',
              ru: 'Факты опираются на академическую «Историю Казахстана» в пяти томах и «Тарих-и Рашиди» Мухаммада Хайдара Дулати. Источник каждого вопроса показан в разборе.\n\nВиза историка ещё не поставлена — серия в тестовом режиме.'),
              style: st(15, height: 1.5, color: const Color(0xFFE8D9BD))),
        ])),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.v, this.l);
  final String v, l;
  @override
  Widget build(BuildContext context) => Column(children: [Text(v, style: st(19, w: 700, color: C.onSky)), Text(l, style: st(11, color: C.onSkySoft))]);
}

class _SoonChip extends StatelessWidget {
  const _SoonChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(border: Border.all(color: C.gold), borderRadius: BorderRadius.circular(999)), child: Text(text, style: st(12, w: 600, color: C.gold)));
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.sub, this.trailing, this.onTap});
  final IconData icon; final String title; final String? sub; final Widget? trailing; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))),
        child: Row(children: [
          Icon(icon, size: 22, color: C.gold), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: st(15)), if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: st(12.5, color: C.inkSoft))]])),
          trailing ?? (onTap != null ? const Chevron() : const SizedBox.shrink()),
        ]),
      ));
}
