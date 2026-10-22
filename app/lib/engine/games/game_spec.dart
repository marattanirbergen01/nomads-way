import 'dart:math' as math;
import '../../core/l10n.dart';
import '../../data/models/episode.dart' show ChoiceToast;

/// Мини-игра внутри сцены (экспериментально, ветка experiment/minigames).
///
/// Описание приходит из `content/games/<season>.yaml` через компилятор. Игра идёт после реплик сцены,
/// до её вопросов. Исход — win / partial / lose — ставит переменные сюжета (как set варианта выбора)
/// и даёт реплику аватара. Проигрыш сюжет не блокирует, любую игру можно пропустить (= partial).
enum GameOutcome { win, partial, lose }

class OutcomeSpec {
  const OutcomeSpec({this.set = const {}, this.reply, this.toasts = const []});
  final Map<String, int> set;
  final L10n? reply;
  final List<ChoiceToast> toasts;
  factory OutcomeSpec.fromJson(Map<String, dynamic>? j) => OutcomeSpec(
        toasts: [for (final t in (j?['toasts'] as List? ?? const [])) ChoiceToast.fromJson((t as Map).cast<String, dynamic>())],
        set: {for (final e in ((j?['set'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toInt()},
        reply: j?['reply'] == null ? null : L10n.fromJson((j!['reply'] as Map).cast<String, dynamic>()),
      );
}

sealed class GameSpec {
  GameSpec({required this.id, required this.title, required this.prompt, required this.outcomes, this.art, this.when = const []});
  final String id;
  final L10n title;
  final L10n prompt;
  final Map<GameOutcome, OutcomeSpec> outcomes;
  /// Фон игры (кадр сцены или своя картинка); null — кадр сцены.
  final String? art;
  /// Условие запуска, как у реплик: [{var, op, value}] — например, только если игрок выбрал лучника.
  final List<Map<String, Object>> when;

  OutcomeSpec outcome(GameOutcome o) => outcomes[o] ?? const OutcomeSpec();

  bool visible(Map<String, int> vars) => when.every((c) {
        final v = vars[c['var']] ?? 0, x = c['value'] as int;
        return switch (c['op']) { '>=' => v >= x, '>' => v > x, '<=' => v <= x, '<' => v < x, '==' => v == x, '!=' => v != x, _ => true };
      });

  static GameSpec fromJson(Map<String, dynamic> j) {
    final base = (
      id: j['id'] as String,
      title: L10n.fromJson((j['title'] as Map).cast<String, dynamic>()),
      prompt: L10n.fromJson((j['prompt'] as Map).cast<String, dynamic>()),
      outcomes: {
        for (final o in GameOutcome.values)
          if (j['outcomes']?[o.name] != null) o: OutcomeSpec.fromJson((j['outcomes'][o.name] as Map).cast<String, dynamic>()),
      },
      art: j['art'] as String?,
      when: [for (final c in (j['when'] as List? ?? const [])) (c as Map).cast<String, Object>()],
    );
    return switch (j['kind']) {
      'route' => RouteSpec._(base, j),
      'trade' => TradeSpec._(base, j),
      'tactics' => TacticsSpec._(base, j),
      'volley' => VolleySpec._(base, j),
      _ => throw FormatException('неизвестная игра ${j['kind']}'),
    };
  }
}

typedef _Base = ({String id, L10n title, L10n prompt, Map<GameOutcome, OutcomeSpec> outcomes, String? art, List<Map<String, Object>> when});
L10n _l(Object? m) => L10n.fromJson(((m as Map?) ?? const {}).cast<String, dynamic>());
double _d(Object? v) => (v as num).toDouble();

// ---------------------------------------------------------------- путь кочевья
class RouteNode {
  const RouteNode({required this.id, required this.x, required this.y, required this.label, this.kind = 'camp'});
  final String id; final double x, y; final L10n label;
  /// camp — стоянка, river — брод, hill — перевал, enemy — набег (пройти через него — поражение).
  final String kind;
}

class RouteSpec extends GameSpec {
  RouteSpec._(_Base b, Map<String, dynamic> j)
      : nodes = [for (final n in j['nodes'] as List) RouteNode(id: n['id'], x: _d(n['x']), y: _d(n['y']), label: _l(n['label']), kind: n['kind'] ?? 'camp')],
        edges = [for (final e in j['edges'] as List) (a: e[0] as String, b: e[1] as String, days: (e[2] as num).toInt())],
        start = j['start'], goal = j['goal'], daysLimit = (j['days_limit'] as num).toInt(),
        super(id: b.id, title: b.title, prompt: b.prompt, outcomes: b.outcomes, art: b.art, when: b.when);
  final List<RouteNode> nodes;
  final List<({String a, String b, int days})> edges;
  final String start, goal;
  final int daysLimit;

  RouteNode node(String id) => nodes.firstWhere((n) => n.id == id);
  int? days(String a, String b) => edges.where((e) => (e.a == a && e.b == b) || (e.a == b && e.b == a)).firstOrNull?.days;
}

/// Ход игрока по маршруту: из текущей точки — только в соседнюю, можно отменить последний шаг.
class RouteGame {
  RouteGame(this.spec) : path = [spec.start];
  final RouteSpec spec;
  final List<String> path;
  String get at => path.last;
  bool get finished => at == spec.goal;
  int get daysUsed => [for (var i = 1; i < path.length; i++) spec.days(path[i - 1], path[i])!].fold(0, (a, b) => a + b);
  bool canGo(String id) => !finished && !path.contains(id) && spec.days(at, id) != null;
  bool go(String id) { if (!canGo(id)) return false; path.add(id); return true; }
  void undo() { if (path.length > 1) path.removeLast(); }
  bool get raided => path.any((id) => spec.node(id).kind == 'enemy');
  GameOutcome get outcome => raided ? GameOutcome.lose : (daysUsed <= spec.daysLimit ? GameOutcome.win : GameOutcome.partial);
}

// ---------------------------------------------------------------- базар
class TradeGood {
  const TradeGood({required this.id, required this.label, required this.price, this.icon});
  final String id; final L10n label; final int price; final String? icon;
}

class TradeSpec extends GameSpec {
  TradeSpec._(_Base b, Map<String, dynamic> j)
      : budget = (j['budget'] as num).toInt(), currency = _l(j['currency']),
        goods = [for (final g in j['goods'] as List) TradeGood(id: g['id'], label: _l(g['label']), price: (g['price'] as num).toInt(), icon: g['icon'])],
        needs = {for (final e in (j['needs'] as Map).entries) e.key as String: (e.value as num).toInt()},
        super(id: b.id, title: b.title, prompt: b.prompt, outcomes: b.outcomes, art: b.art, when: b.when);
  final int budget;
  final L10n currency;
  final List<TradeGood> goods;
  /// Что нужно аулу к зиме: товар → сколько.
  final Map<String, int> needs;
}

class TradeGame {
  TradeGame(this.spec);
  final TradeSpec spec;
  final cart = <String, int>{};
  int get spent => spec.goods.fold(0, (s, g) => s + g.price * (cart[g.id] ?? 0));
  int get left => spec.budget - spent;
  bool canAdd(String id) => spec.goods.firstWhere((g) => g.id == id).price <= left;
  void add(String id) { if (canAdd(id)) cart[id] = (cart[id] ?? 0) + 1; }
  void remove(String id) { final n = cart[id] ?? 0; if (n > 0) cart[id] = n - 1; }
  /// Сколько нужд закрыто полностью.
  int get met => spec.needs.entries.where((e) => (cart[e.key] ?? 0) >= e.value).length;
  GameOutcome get outcome => met == spec.needs.length ? GameOutcome.win : (met * 2 >= spec.needs.length ? GameOutcome.partial : GameOutcome.lose);
}

// ---------------------------------------------------------------- тактика
class TacticsMove {
  const TacticsMove({required this.id, required this.label, required this.outcome, this.arrows = const []});
  final String id; final L10n label; final GameOutcome outcome;
  /// Стрелки манёвра на карте: [[x1,y1,x2,y2], ...] в долях кадра; рисуются кодом.
  final List<List<double>> arrows;
}

class TacticsSpec extends GameSpec {
  TacticsSpec._(_Base b, Map<String, dynamic> j)
      : units = [for (final u in j['units'] as List) (label: _l(u['label']), x: _d(u['x']), y: _d(u['y']), enemy: u['enemy'] == true)],
        moves = [
          for (final m in j['moves'] as List)
            TacticsMove(id: m['id'], label: _l(m['label']), outcome: GameOutcome.values.byName(m['outcome']),
                arrows: [for (final a in (m['arrows'] as List? ?? const [])) [for (final v in a as List) _d(v)]]),
        ],
        super(id: b.id, title: b.title, prompt: b.prompt, outcomes: b.outcomes, art: b.art, when: b.when);
  final List<({L10n label, double x, double y, bool enemy})> units;
  final List<TacticsMove> moves;
}

// ---------------------------------------------------------------- залп
class VolleySpec extends GameSpec {
  VolleySpec._(_Base b, Map<String, dynamic> j)
      : rounds = (j['rounds'] as num?)?.toInt() ?? 3, need = (j['need'] as num?)?.toInt() ?? 2,
        periodMs = (j['period_ms'] as num?)?.toInt() ?? 1600,
        window = (_d((j['window'] as List)[0]), _d((j['window'] as List)[1])),
        super(id: b.id, title: b.title, prompt: b.prompt, outcomes: b.outcomes, art: b.art, when: b.when);
  final int rounds, need, periodMs;
  /// Окно «вовремя» на шкале напряжения 0..1.
  final (double, double) window;
}

/// Шкала напряжения ходит 0→1→0 с периодом periodMs; выстрел в окне — попадание.
class VolleyGame {
  VolleyGame(this.spec);
  final VolleySpec spec;
  final shots = <bool>[];
  bool get finished => shots.length >= spec.rounds;
  int get hits => shots.where((x) => x).length;
  double meter(int ms) {
    final p = (ms % spec.periodMs) / spec.periodMs;
    return 0.5 - 0.5 * math.cos(2 * math.pi * p);
  }
  bool shoot(int ms) {
    if (finished) return false;
    final m = meter(ms);
    final hit = m >= spec.window.$1 && m <= spec.window.$2;
    shots.add(hit);
    return hit;
  }
  GameOutcome get outcome => hits >= spec.need ? GameOutcome.win : (hits > 0 ? GameOutcome.partial : GameOutcome.lose);
}
