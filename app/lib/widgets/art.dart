import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Единственная точка показа иллюстраций.
///
/// Кадры распаковываются в память как несжатый битмап: 1600×1600 это 9 МБ,
/// а обложка 1024×1024 ради миниатюры 72 px — 4 МБ. Поэтому декодируем
/// строго под размер на экране через cacheWidth и держим кэш в узде (см. main.dart).
class Art extends StatelessWidget {
  const Art({
    super.key, this.url, this.file, this.fit = BoxFit.cover, this.pan, this.alignment,
    this.width, this.height, this.fallback, this.logicalWidth,
  });

  /// Сеть — пока серия не скачана, и всегда в браузере.
  final String? url;
  /// Файл из скачанного бандла.
  final File? file;
  final BoxFit fit;
  /// 0..100 — какую часть кадра показывать по горизонтали. null = центр.
  final int? pan;
  /// Явное выравнивание; перекрывает pan.
  final Alignment? alignment;
  final double? width, height;
  final Widget? fallback;
  /// Ширина места на экране в логических пикселях; по умолчанию — вся ширина.
  final double? logicalWidth;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screen = MediaQuery.sizeOf(context).width;
    // width может быть double.infinity у полноэкранного кадра — тогда берём ширину экрана.
    final candidate = [logicalWidth, width].firstWhere((v) => v != null && v.isFinite && v > 0, orElse: () => null);
    final lw = candidate ?? (screen.isFinite && screen > 0 ? screen : 400.0);
    final cacheWidth = (lw * dpr).round().clamp(64, 1440);
    final align = alignment ?? (pan == null ? Alignment.center : Alignment((pan! / 50) - 1, 0));
    final fb = fallback ?? Container(color: C.cardHigh, width: width, height: height);

    if (file != null) {
      return Image.file(
        file!, fit: fit, alignment: align, width: width, height: height,
        cacheWidth: cacheWidth, gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fb,
      );
    }
    return Image.network(
      url!, fit: fit, alignment: align, width: width, height: height,
      cacheWidth: cacheWidth, gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fb,
      loadingBuilder: (_, child, p) => p == null ? child : fb,
    );
  }

  /// Провайдер того же кадра — для предзагрузки и выгрузки из кэша.
  static ImageProvider provider({String? url, File? file, required double logicalWidth, required double dpr}) {
    final w = (logicalWidth * dpr).round().clamp(64, 1440);
    final base = file != null ? FileImage(file) : NetworkImage(url!) as ImageProvider;
    return ResizeImage(base, width: w, allowUpscaling: false);
  }
}

/// Настройка кэша картинок под наш сценарий: одна сцена на экране плюс соседняя.
void tuneImageCache() {
  final c = PaintingBinding.instance.imageCache;
  c.maximumSizeBytes = 40 << 20;   // 40 МБ вместо стандартных 100
  c.maximumSize = kIsWeb ? 40 : 24;
}
