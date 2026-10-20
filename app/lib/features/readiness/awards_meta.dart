import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../engine/awards.dart';

class AwardMeta {
  const AwardMeta({required this.kk, required this.ru, required this.descKk, required this.descRu, required this.icon, required this.video});
  final String kk, ru, descKk, descRu;
  final IconData icon;
  /// Ролик раскрытия: assets/awards/<video>.mp4.
  final String video;
  String name(String l) => l == 'kk' ? kk : ru;
  String desc(String l) => l == 'kk' ? descKk : descRu;
}

const awardMeta = <Award, AwardMeta>{
  Award.mergen: AwardMeta(kk: 'Мерген', ru: 'Мерген', descKk: 'Тестте 20 сұрақтың 20-ына дұрыс жауап бердің.',
      descRu: 'Ответил верно на 20 вопросов из 20 в тесте.', icon: Icons.gps_fixed_rounded, video: 'mergen'),
  Award.koshBastagan: AwardMeta(kk: 'Көш бастаған', ru: 'Көш бастаған', descKk: 'Алғашқы серияны аяғына дейін өттің.',
      descRu: 'Прошёл первую серию до конца.', icon: Icons.home_outlined, video: 'kosh-bastagan'),
  Award.shezhireshi: AwardMeta(kk: 'Шежіреші', ru: 'Шежіреші', descKk: 'Керей мен Жәнібек туралы барлық сұраққа дұрыс жауап бердің.',
      descRu: 'Верно ответил на все вопросы о Керее и Жанибеке.', icon: Icons.menu_book_outlined, video: 'shezhireshi'),
  Award.streak7: AwardMeta(kk: '7 күн қатар', ru: '7 дней подряд', descKk: 'Апта бойы күн сайын оқыдың.',
      descRu: 'Занимался каждый день целую неделю.', icon: Icons.wb_sunny_outlined, video: '7-kun-qatar'),
};

/// Медальон награды: кольцо, тонкое внутреннее кольцо, знак.
class Medal extends StatelessWidget {
  const Medal({super.key, required this.award, this.size = 56, this.locked = false});
  final Award award; final double size; final bool locked;
  @override
  Widget build(BuildContext context) {
    final ring = locked ? const Color(0xFF6B5A48) : C.gold;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2F241B), border: Border.all(color: ring, width: size > 100 ? 2 : 1.6)),
      child: Container(
        margin: EdgeInsets.all(size * .08),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring.withValues(alpha: .55), width: .8)),
        child: Icon(awardMeta[award]!.icon, size: size * .42, color: locked ? const Color(0xFF6B5A48) : C.goldBright),
      ),
    );
  }
}
