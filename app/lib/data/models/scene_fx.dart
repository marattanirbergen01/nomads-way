// Живой кадр сцены: движение камеры и слои частиц. Источник — `content/fx/<season>.yaml`,
// в episode.json приходит уже проверенным компилятором (docs/CONTENT_FORMAT.md, «content/fx»).

enum CameraMove { still, breathe, push, pull, pan }

class CameraSpec {
  const CameraSpec({this.move = CameraMove.breathe, this.from, this.to, this.zoom, this.seconds, this.panY = 50});

  final CameraMove move;
  /// Горизонталь в единицах `pan` (0..100); null — `pan` сцены.
  final double? from, to;
  /// Наибольшее приближение; null — по умолчанию для движения.
  final double? zoom;
  /// Один проход туда; обратно — столько же.
  final double? seconds;
  /// Вертикаль кадра: 0 — верх, 100 — низ.
  final double panY;

  /// Без записи в content/fx сцена «дышит».
  static const breathe = CameraSpec();

  factory CameraSpec.fromJson(Map<String, dynamic> j) => CameraSpec(
        move: CameraMove.values.asNameMap()[j['move']] ?? CameraMove.breathe,
        from: (j['from'] as num?)?.toDouble(),
        to: (j['to'] as num?)?.toDouble(),
        zoom: (j['zoom'] as num?)?.toDouble(),
        seconds: (j['dur'] as num?)?.toDouble(),
        panY: (j['panY'] as num?)?.toDouble() ?? 50,
      );

  /// Наибольшее приближение за проход — под него декодируется кадр, чтобы не мылился.
  double get maxZoom => switch (move) {
        CameraMove.still => 1,
        CameraMove.breathe => zoom ?? 1.06,
        CameraMove.push || CameraMove.pull => zoom ?? 1.15,
        CameraMove.pan => zoom ?? 1.12,
      };
}

enum FxType { dust, sand, fog, snow, embers, firelight }

class FxLayer {
  const FxLayer(this.type, {this.x = .5, this.y = .5, this.radius, this.density = 1, this.wind = 1});

  final FxType type;
  /// Точка огня в долях картинки (0..1).
  final double x, y;
  /// Радиус отсвета в долях ширины картинки.
  final double? radius;
  final double density;
  /// Ветер: 1 — вправо, -1 — влево.
  final double wind;

  /// Огонь привязан к месту на картинке и едет вместе с камерой; погода висит над кадром.
  bool get anchored => type == FxType.embers || type == FxType.firelight;

  /// null — тип, которого клиент не знает (контент новее приложения): слой пропускается.
  static FxLayer? fromJson(Map<String, dynamic> j) {
    final t = FxType.values.asNameMap()[j['type']];
    if (t == null) return null;
    return FxLayer(
      t,
      x: (j['x'] as num?)?.toDouble() ?? .5,
      y: (j['y'] as num?)?.toDouble() ?? .5,
      radius: (j['r'] as num?)?.toDouble(),
      density: (j['density'] as num?)?.toDouble() ?? 1,
      wind: (j['wind'] as num?)?.toDouble() ?? 1,
    );
  }
}
