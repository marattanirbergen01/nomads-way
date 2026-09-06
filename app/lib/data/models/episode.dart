import '../../core/l10n.dart';

class Episode {
  Episode({required this.id, required this.title, required this.scenes, required this.characters, required this.finalTest});
  final String id;
  final L10n title;
  final List<Scene> scenes;
  final Map<String, Character> characters;
  final FinalTestSpec finalTest;

  Scene sceneById(String id) => scenes.firstWhere((s) => s.id == id);
  int indexOf(String id) => scenes.indexWhere((s) => s.id == id);

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'],
        title: L10n.fromJson(j['title']),
        scenes: [for (final s in j['scenes']) Scene.fromJson(s)],
        characters: {for (final e in (j['characters'] as Map).entries) e.key: Character.fromJson(e.value)},
        finalTest: FinalTestSpec(single: j['finalTest']['single'], context: j['finalTest']['context']),
      );
}

class Character {
  Character({required this.name, required this.fiction});
  final L10n name;
  final bool fiction;
  factory Character.fromJson(Map<String, dynamic> j) => Character(name: L10n.fromJson(j['name']), fiction: j['fiction'] == true);
}

class Scene {
  Scene({required this.id, required this.art, required this.covers, required this.beats, required this.quiz});
  final String id;
  final String art;
  final List<String> covers;
  final List<Beat> beats;
  final List<String> quiz;

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
        id: j['id'],
        art: j['art'],
        covers: (j['covers'] as List).cast<String>(),
        beats: [for (final b in j['beats']) Beat.fromJson(b)],
        quiz: (j['quiz'] as List).cast<String>(),
      );
}

sealed class Beat {
  factory Beat.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'say' => Say(who: j['who'], text: L10n.fromJson(j['text'])),
        'choice' => Choice(prompt: L10n.fromJson(j['prompt']), options: [for (final o in j['options']) Option.fromJson(o)]),
        _ => throw FormatException('unknown beat type ${j['type']}'),
      };
}

class Say implements Beat {
  Say({required this.who, required this.text});
  final String who;
  final L10n text;
}

class Choice implements Beat {
  Choice({required this.prompt, required this.options});
  final L10n prompt;
  final List<Option> options;
}

class Option {
  Option({required this.id, required this.text, required this.set, required this.goto});
  final String id;
  final L10n text;
  final Map<String, int> set;
  final String goto;
  factory Option.fromJson(Map<String, dynamic> j) => Option(
        id: j['id'],
        text: L10n.fromJson(j['text']),
        set: {for (final e in (j['set'] as Map? ?? {}).entries) e.key as String: (e.value as num).toInt()},
        goto: j['goto'],
      );
}

class FinalTestSpec {
  const FinalTestSpec({required this.single, required this.context});
  final int single;
  final int context;
}
