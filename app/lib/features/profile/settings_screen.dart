import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/ornament.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});
  final Services services;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Services get _s => widget.services;

  Future<void> _edit(String title, String current, Future<void> Function(String) save, {TextInputType? type}) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: C.card, title: Text(title, style: st(17, w: 600)),
      content: TextField(controller: c, autofocus: true, keyboardType: type, style: st(16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_s.s('cancel'), style: st(14, color: C.inkSoft))),
        TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text('OK', style: st(14, w: 600, color: C.gold))),
      ]));
    if (v != null) { await save(v); setState(() {}); _s.touch(); }
  }

  Widget _field(String label, String value, VoidCallback onTap) => InkWell(onTap: onTap, child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))),
        child: Row(children: [
          SizedBox(width: 112, child: Text(label, style: st(14, color: C.inkSoft))),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: st(15))),
          const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF6B5A48)),
        ])));

  Widget _section(String title) => Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text(title, style: st(11.5, w: 600, color: C.inkFaint, spacing: 1.1)));

  @override
  Widget build(BuildContext context) {
    final s = _s.s; final st_ = _s.store;
    final mb = (st_.cacheBytes() / 1024 / 1024);
    return Scaffold(body: ListView(padding: EdgeInsets.zero, children: [
      Container(
        height: 132 + MediaQuery.of(context).padding.top,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFC3D2DD), Color(0xFFE2DCCB)])),
        child: Stack(children: [
          Positioned(left: 4, top: MediaQuery.of(context).padding.top, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: C.onSky))),
          Positioned(left: 20, bottom: 16, child: Text(s('settings'), style: st(24, w: 700, color: C.onSky))),
        ]),
      ),
      const HorizonLine(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 30), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section(s('personal')),
        _field(s('name'), st_.realName, () => _edit(s('name'), st_.realName, st_.setRealName)),
        _field(s('surname'), st_.surname, () => _edit(s('surname'), st_.surname, st_.setSurname)),
        _field(s('grade'), st_.grade, () => _edit(s('grade'), st_.grade, st_.setGrade, type: TextInputType.number)),
        _field(s('email'), st_.email, () => _edit(s('email'), st_.email, st_.setEmail, type: TextInputType.emailAddress)),
        Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))), child: Row(children: [
          SizedBox(width: 112, child: Text(s('password'), style: st(14, color: C.inkSoft))),
          Expanded(child: Text('••••••••', style: st(15, spacing: 3))),
          Text(s('soon'), style: st(13, w: 600, color: C.gold)),
        ])),
        const SizedBox(height: 22),
        _section(s('app.sec')),
        Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))), child: Row(children: [
          Expanded(child: Text(s('lang'), style: st(15))),
          _Seg(value: _s.l, onChanged: (v) { _s.locale.set(v); setState(() {}); }),
        ])),
        Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))), child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s('notifications'), style: st(15)), Text(s('notif.sub'), style: st(12.5, color: C.inkSoft))])),
          Switch(value: st_.notifications, activeThumbColor: C.ground, activeTrackColor: C.gold, onChanged: (v) async { await st_.setNotifications(v); setState(() {}); }),
        ])),
        Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))), child: Row(children: [
          Expanded(child: Text(s('downloads'), style: st(15))), Text('${mb.toStringAsFixed(mb < 1 ? 2 : 0)} МБ', style: st(13, color: C.inkSoft)),
        ])),
        Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))), child: Row(children: [
          Expanded(child: Text(s('about'), style: st(15))), Text('0.1.0', style: st(13, color: C.inkSoft)),
        ])),
        Container(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.lineSoft))), child: Row(children: [
          Expanded(child: Text(s('cdn'), style: st(15))),
          TextButton(onPressed: _cdn, child: Text(_s.content.baseUrl.replaceFirst(RegExp(r'^https?://'), ''), style: st(12, color: C.gold), overflow: TextOverflow.ellipsis)),
        ])),
        const SizedBox(height: 14),
        InkWell(onTap: null, child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), child: Row(children: [Expanded(child: Text(s('logout'), style: st(15, color: C.ember.withValues(alpha: .5)))), Text(s('soon'), style: st(12, color: C.inkFaint))]))),
        InkWell(onTap: _wipe, child: Padding(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4), child: Text(s('wipe'), style: st(15, color: C.ember)))),
      ])),
    ]));
  }

  Future<void> _cdn() async {
    await _edit(_s.s('cdn'), _s.content.baseUrl, (v) async { if (v.trim().isNotEmpty) _s.content.baseUrl = v.trim(); }, type: TextInputType.url);
  }

  Future<void> _wipe() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: C.card, content: Text(_s.s('wipe.q'), style: st(15)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_s.s('cancel'), style: st(14, color: C.inkSoft))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_s.s('wipe'), style: st(14, w: 600, color: C.ember))),
      ]));
    if (ok == true) {
      final locale = _s.l;
      await _s.store.wipe();
      await _s.store.setLocale(locale);
      _s.touch(); setState(() {});
    }
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.value, required this.onChanged});
  final String value; final void Function(String) onChanged;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(border: Border.all(color: C.cardHigh), borderRadius: BorderRadius.circular(999)),
        clipBehavior: Clip.antiAlias,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final v in const ['kk', 'ru']) GestureDetector(onTap: () => onChanged(v), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), color: value == v ? C.gold : Colors.transparent,
            child: Text(v == 'kk' ? 'ҚАЗ' : 'РУС', style: st(12, w: 600, color: value == v ? C.ground : C.inkSoft)))),
        ]),
      );
}
