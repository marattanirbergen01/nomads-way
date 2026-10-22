import 'package:video_player/video_player.dart';

/// Короткие звуки интерфейса (ассеты wav). Играет и забывает; ошибки — тишина (браузер без жеста, нет звука).
class Sfx {
  Sfx(this.enabled);
  /// Настройка «Дыбыс».
  final bool enabled;

  Future<void> play(String asset, {double volume = .8}) async {
    if (!enabled) return;
    final v = VideoPlayerController.asset(asset, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await v.initialize();
      await v.setVolume(volume);
      await v.play();
      await Future<void>.delayed(v.value.duration + const Duration(milliseconds: 200));
    } catch (_) {
      // тихо
    } finally {
      await v.dispose();
    }
  }

  /// Звук мини-игры: `assets/games/game_<name>.wav`
  Future<void> game(String name) => play('assets/games/game_$name.wav');
}
