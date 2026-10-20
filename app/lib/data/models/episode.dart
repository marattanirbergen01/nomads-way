import '../../core/l10n.dart';

class Episode {
  Episode({required this.id, required this.title, required this.scenes, required this.characters, required this.finalTest, this.era, this.mediaExt = const {}, this.motion = const {}});
  final String id;
  final L10n title;
  final String? era;
  /// Расширения медиа, отличные от jpg: карта — png.
  final Map<String, String> mediaExt;
  /// Анимированные кадры (карты): кадр → {язык: файл постера}. Ролик — `<art>_<lang>.mp4`,
  /// постер — его последний кадр (jpg или png).
  final Map<String, Map<String, String>> motion;
  /// Язык ролика для игрока: его язык, иначе kk, иначе любой. null — у кадра нет ролика.
  String? motionLang(String art, String locale) {
    final langs = motion[art];
    if (langs == null || langs.isEmpty) return null;
    return langs.containsKey(locale) ? locale : (langs.containsKey('kk') ? 'kk' : langs.keys.first);
  }
  String motionPoster(String art, String lang) => motion[art]![lang]!;
  final List<Scene> scenes;
  final Map<String, Character> characters;
  final FinalTestSpec finalTest;

  Scene sceneById(String id) => scenes.firstWhere((s) => s.id == id);
  int indexOf(String id) => scenes.indexWhere((s) => s.id == id);

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'],
        title: L10n.fromJson(j['title']),
        era: j['era'],
        mediaExt: {for (final e in ((j['mediaExt'] as Map?) ?? {}).entries) e.key as String: e.value as String},
        motion: {
          for (final e in ((j['motion'] as Map?) ?? {}).entries)
            e.key as String: (e.value as Map).map((k, v) => MapEntry(k as String, v as String)),
        },
        scenes: [for (final s in j['scenes']) Scene.fromJson(s)],
        characters: {for (final e in (j['characters'] as Map).entries) e.key: Character.fromJson(e.value)},
        finalTest: FinalTestSpec(single: j['finalTest']['single'], context: j['finalTest']['context']),
      );
}

class Character {
  Character({required this.name, required this.fiction, this.avatar = false, this.defaultName, this.portrait});
  final L10n name;
  final bool fiction;
  /// Персонаж-аватар игрока: имя берётся из профиля, реплики показываются с фигурой.
  final bool avatar;
  final L10n? defaultName;
  /// Портрет из общего пакета (characters/`<id>`.jpg); null — кружка нет.
  final String? portrait;
  factory Character.fromJson(Map<String, dynamic> j) => Character(
        name: L10n.fromJson(j['name']),
        fiction: j['fiction'] == true,
        avatar: j['avatar'] == true,
        defaultName: j['defaultName'] == null ? null : L10n.fromJson(j['defaultName']),
        portrait: j['portrait'],
      );
}

class Scene {
  Scene({
    required this.id, required this.art, required this.covers, required this.beats, required this.quiz,
    this.title, this.layer, this.pan = 50, this.avatarRight = false, this.artWhen = const [],
  });
  final String id;
  final String art;
  final List<String> covers;
  final List<Beat> beats;
  final List<String> quiz;
  final L10n? title;
  final String? layer;          // history | personal | null
  final int pan;                // 0..100 — горизонтальное панорамирование кадра
  final bool avatarRight;
  /// Кадр по условию на переменные сюжета: первое совпавшее правило; иначе [art].
  final List<ArtRule> artWhen;

  /// Какой кадр показать при текущих переменных — так вечерняя сцена помнит, где поставили юрту.
  String artFor(Map<String, int> vars) {
    for (final r in artWhen) {
      if (r.matches(vars)) return r.art;
    }
    return art;
  }

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'],
        art: j['art'],
        covers: (j['covers'] as List).cast<String>(),
        beats: [for (final b in j['beats']) Beat.fromJson(b)],
        quiz: (j['quiz'] as List).cast<String>(),
        title: j['title'] == null ? null : L10n.fromJson(j['title']),
        layer: j['layer'],
        pan: (j['pan'] as num?)?.toInt() ?? 50,
        avatarRight: j['avatarSide'] == 'right',
        artWhen: [for (final r in (j['artWhen'] as List? ?? [])) ArtRule.fromJson(r)],
      );
}

class ArtRule {
  const ArtRule({required this.conds, required this.art});
  final List<Cond> conds;
  final String art;
  bool matches(Map<String, int> vars) => conds.every((c) => c.test(vars[c.name] ?? 0));
  factory ArtRule.fromJson(Map<String, dynamic> j) => ArtRule(
        conds: [for (final c in (j['if'] as List? ?? [])) Cond(c['var'], c['op'], (c['value'] as num).toInt())],
        art: j['art'],
      );
}

/// Одно сравнение переменной сюжета с числом. Отсутствующая переменная равна 0.
class Cond {
  const Cond(this.name, this.op, this.value);
  final String name; final String op; final int value;
  bool test(int v) => switch (op) {
        '==' => v == value, '!=' => v != value, '<' => v < value,
        '<=' => v <= value, '>' => v > value, '>=' => v >= value, _ => false,
      };
}

sealed class Beat {
  factory Beat.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'say' => Say(
            who: j['who'], text: L10n.fromJson(j['text']), emo: j['emo'],
            when: [for (final c in (j['when'] as List? ?? [])) Cond(c['var'], c['op'], (c['value'] as num).toInt())],
          ),
        'choice' => Choice(prompt: L10n.fromJson(j['prompt']), options: [for (final o in j['options']) Option.fromJson(o)]),
        _ => throw FormatException('unknown beat type ${j['type']}'),
      };
}

class Say implements Beat {
  Say({required this.who, required this.text, this.emo, this.when = const []});
  final String who;
  final L10n text;
  /// calm | joy | alarm | sorrow — состояние аватара в этой реплике; null = calm.
  final String? emo;
  /// Условие показа на переменные сюжета; пустое — реплика звучит всегда.
  final List<Cond> when;
  bool visible(Map<String, int> vars) => when.every((c) => c.test(vars[c.name] ?? 0));
}

class Choice implements Beat {
  Choice({required this.prompt, required this.options});
  final L10n prompt;
  final List<Option> options;
}

class Option {
  Option({required this.id, required this.text, required this.set, required this.goto, this.art, this.reply, this.replyEmo});
  final String id;
  final L10n text;
  final Map<String, int> set;
  final String goto;
  /// Свой кадр у опции — развилка показывается двумя картинками.
  final String? art;
  /// Что произошло после выбора — текст экрана «выбор сделан».
  final L10n? reply;
  /// Состояние аватара на экране «выбор сделан».
  final String? replyEmo;
  factory Option.fromJson(Map<String, dynamic> j) => Option(
        id: j['id'],
        text: L10n.fromJson(j['text']),
        set: {for (final e in (j['set'] as Map? ?? {}).entries) e.key as String: (e.value as num).toInt()},
        goto: j['goto'],
        art: j['art'],
        reply: j['reply'] == null ? null : L10n.fromJson(j['reply']),
        replyEmo: j['replyEmo'],
      );
}

class FinalTestSpec {
  const FinalTestSpec({required this.single, required this.context});
  final int single;
  final int context;
}
