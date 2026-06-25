import 'package:audioplayers/audioplayers.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _tickPlayer = AudioPlayer();
  final AudioPlayer _signalPlayerA = AudioPlayer();
  final AudioPlayer _signalPlayerB = AudioPlayer();
  bool muted = false;

  Future<void> _play(AudioPlayer player, String asset) async {
    if (muted) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio is best-effort; never let a playback failure crash the UI.
    }
  }

  /// Call once per second while a countdown is active (secondsLeft 1..10).
  void countdownTick(int secondsLeft) {
    if (secondsLeft == 1) {
      _play(_tickPlayer, 'sounds/beep_1400.wav');
    } else {
      _play(_tickPlayer, 'sounds/beep_900.wav');
    }
  }

  /// Two-tone alert played when a new signal appears.
  void signalAlert() {
    _play(_signalPlayerA, 'sounds/beep_1320.wav');
    Future.delayed(const Duration(milliseconds: 180), () {
      _play(_signalPlayerB, 'sounds/beep_1760.wav');
    });
  }

  void dispose() {
    _tickPlayer.dispose();
    _signalPlayerA.dispose();
    _signalPlayerB.dispose();
  }
}
