import '../../core/l10n.dart';

class Episode {
  Episode({required this.id, required this.title, required this.scenes, required this.characters, required this.finalTest, this.era});
  final String id;
  final L10n title;
  final String? era;
  final List<Scene> scenes;
  final Map<String, Character> characters;
  final FinalTestSpec finalTest;

  Scene sceneById(String id) => scenes.firstWhere((s) => s.id == id);
  int indexOf(String id) => scenes.indexWhere((s) => s.id == id);

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'],
        title: L10n.fromJson(j['title']),
        era: j['era'],
        scenes: [for (final s in j['scenes']) Scene.fromJson(s)],
        characters: {for (final e in (j['characters'] as Map).entries) e.key: Character.fromJson(e.value)},
        finalTest: FinalTestSpec(single: j['finalTest']['single'], context: j['finalTest']['context']),
      );
}

class Character {
  Character({required this.name, required this.fiction, this.avatar = false, this.defaultName});
  final L10n name;
  final bool fiction;
  /// Персонаж-аватар игрока: имя берётся из профиля, реплики показываются с фигурой.
  final bool avatar;
  final L10n? defaultName;
  factory Character.fromJson(Map<String, dynamic> j) => Character(
        name: L10n.fromJson(j['name']),
        fiction: j['fiction'] == true,
        avatar: j['avatar'] == true,
        defaultName: j['defaultName'] == null ? null : L10n.fromJson(j['defaultName']),
      );
}

class Scene {
  Scene({
    required this.id, required this.art, required this.covers, required this.beats, required this.quiz,
    this.title, this.layer, this.pan = 50, this.avatarRight = false,
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
      );
}

sealed class Beat {
  factory Beat.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'say' => Say(who: j['who'], text: L10n.fromJson(j['text']), emo: j['emo']),
        'choice' => Choice(prompt: L10n.fromJson(j['prompt']), options: [for (final o in j['options']) Option.fromJson(o)]),
        _ => throw FormatException('unknown beat type ${j['type']}'),
      };
}

class Say implements Beat {
  Say({required this.who, required this.text, this.emo});
  final String who;
  final L10n text;
  /// calm | joy | alarm | sorrow — состояние аватара в этой реплике; null = calm.
  final String? emo;
}

class Choice implements Beat {
  Choice({required this.prompt, required this.options});
  final L10n prompt;
  final List<Option> options;
}

class Option {
  Option({required this.id, required this.text, required this.set, required this.goto, this.art});
  final String id;
  final L10n text;
  final Map<String, int> set;
  final String goto;
  /// Свой кадр у опции — развилка показывается двумя картинками.
  final String? art;
  factory Option.fromJson(Map<String, dynamic> j) => Option(
        id: j['id'],
        text: L10n.fromJson(j['text']),
        set: {for (final e in (j['set'] as Map? ?? {}).entries) e.key as String: (e.value as num).toInt()},
        goto: j['goto'],
        art: j['art'],
      );
}

class FinalTestSpec {
  const FinalTestSpec({required this.single, required this.context});
  final int single;
  final int context;
}
