import 'package:flutter/material.dart';
import '../../core/services.dart';
import '../../core/theme.dart';
import '../../widgets/ornament.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key, required this.services});
  final Services services;

  static const _kk = [
    ('Қолданба мұғалімді алмастыра ма?', 'Жоқ. Бұл — оқулықпен және мұғаліммен қатар жүретін жаттықтырушы. Оқиға арқылы датаны, жерді, есімді есте сақтауға көмектеседі; емтиханға дайындықтың толық курсы емес.'),
    ('Деректер қайдан алынған?', 'Академиялық «Қазақстан тарихы» (5 томдық) және Мұхаммед Хайдар Дулатидің «Тарих-и Рашиди» еңбегінен. Әр сұрақтың дереккөзі талдауда көрсетіледі. Тарихшы визасы — қойылған соң серия «сынақ» белгісінен шығады.'),
    ('«Дайындық» пайызы қалай есептеледі?', 'Әр дерек бойынша соңғы үш жауап алынады, жаңасы ауырлау саналады. Жауап берілмеген дерек 0% деп есептеледі — сан әрқашан шынайы.'),
    ('Қате байқасам не істеймін?', 'Талдау экранында дереккөз көрсетілген. Қатені хабарлау түймесі жақында қосылады; әзірге профильдегі «Бізбен байланыс» арқылы.'),
    ('Айдар шын адам ма?', 'Жоқ. Кейіпкер — ойдан шығарылған табунщы, оның өмірі тарихи оқиғаларға жанама байланысты. Керей, Жәнібек, Әбілқайыр, Есен-Бұға — шын тарихи тұлғалар, олардың сөздері дереккөзге сүйенеді.'),
  ];
  static const _ru = [
    ('Заменяет ли приложение учителя?', 'Нет. Это тренажёр рядом с учебником и учителем. Он помогает запомнить дату, место и имя через историю, но не является полным курсом подготовки.'),
    ('Откуда факты?', 'Из академической «Истории Казахстана» в пяти томах и «Тарих-и Рашиди» Мухаммада Хайдара Дулати. Источник каждого вопроса показан в разборе. После визы историка серия выйдет из тестового режима.'),
    ('Как считается процент готовности?', 'По последним трём ответам на каждый факт, свежие весят больше. Факт без ответов считается за 0% — число всегда честное.'),
    ('Что делать, если нашёл ошибку?', 'В разборе указан источник. Кнопка «сообщить об ошибке» появится скоро; пока — через «Связаться с нами» в профиле.'),
    ('Айдар — реальный человек?', 'Нет. Персонаж вымышлен — табунщик, чья жизнь косвенно связана с историческими событиями. Керей, Жанибек, Абулхайр, Есен-Буга — реальные лица, их слова опираются на источники.'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = services.s; final items = services.l == 'kk' ? _kk : _ru;
    return Scaffold(body: ListView(padding: EdgeInsets.zero, children: [
      Container(
        height: 132 + MediaQuery.of(context).padding.top,
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFC3D2DD), Color(0xFFE2DCCB)])),
        child: Stack(children: [
          Positioned(left: 4, top: MediaQuery.of(context).padding.top, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, color: C.onSky))),
          Positioned(left: 20, right: 20, bottom: 16, child: Text(s('faq'), style: st(24, w: 700, color: C.onSky))),
        ]),
      ),
      const HorizonLine(),
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 30), child: Column(children: [
        for (final (q, a) in items) Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 4), iconColor: C.gold, collapsedIconColor: C.inkFaint,
          title: Text(q, style: st(15, w: 600)),
          children: [Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 14), child: Text(a, style: st(14.5, color: const Color(0xFFE8D9BD), height: 1.5)))],
        )),
      ])),
    ]));
  }
}
