import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SoundService v2
// · muted flag persisted across sessions (caller sets from DB at startup)
// · signalAlert() also fires a push notification so the user is alerted
//   even when the app is backgrounded
// · AudioPlayer instances are long-lived — avoids re-init latency and
//   keeps audio context alive when app is in background
// ─────────────────────────────────────────────────────────────────────────────

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _tickPlayer   = AudioPlayer();
  final AudioPlayer _signalPlayerA = AudioPlayer();
  final AudioPlayer _signalPlayerB = AudioPlayer();

  bool _muted = false;
  bool get muted => _muted;

  final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();
  bool _notifReady = false;

  // ── Init (call once from main.dart after WidgetsFlutterBinding) ──────────
  Future<void> init({bool soundOn = true}) async {
    _muted = !soundOn;

    // Keep audio players alive for background use
    await _tickPlayer.setReleaseMode(ReleaseMode.stop);
    await _signalPlayerA.setReleaseMode(ReleaseMode.stop);
    await _signalPlayerB.setReleaseMode(ReleaseMode.stop);

    // Init local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    final ok = await _notif.initialize(initSettings);
    _notifReady = ok ?? false;

    // Request permission (Android 13+)
    await _notif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  void setMuted(bool value) => _muted = value;

  // ── Internal play helper ──────────────────────────────────────────────────
  Future<void> _play(AudioPlayer player, String asset) async {
    if (_muted) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (_) {
      // Audio is best-effort
    }
  }

  // ── Countdown tick (called every second when ≤ 10s left) ─────────────────
  void countdownTick(int secondsLeft) {
    if (secondsLeft == 1) {
      _play(_tickPlayer, 'sounds/beep_1400.wav');
    } else {
      _play(_tickPlayer, 'sounds/beep_900.wav');
    }
  }

  // ── Signal alert: two-tone beep + push notification ─────────────────────
  void signalAlert({required String asset, required String direction}) {
    _play(_signalPlayerA, 'sounds/beep_1320.wav');
    Future.delayed(const Duration(milliseconds: 180), () {
      _play(_signalPlayerB, 'sounds/beep_1760.wav');
    });
    _pushNotification(asset: asset, direction: direction);
  }

  // ── Invalidation alert: signal fired then reversed before you closed it ──
  // Fires when indicators flip back to WAIT while a signal was still armed —
  // a warning that the setup no longer holds, distinct from the entry alert.
  void invalidationAlert({required String asset, required String wasDirection}) {
    _play(_tickPlayer, 'sounds/beep_900.wav');
    _pushInvalidationNotification(asset: asset, wasDirection: wasDirection);
  }

  Future<void> _pushInvalidationNotification({
    required String asset,
    required String wasDirection,
  }) async {
    if (!_notifReady) return;
    const androidDetails = AndroidNotificationDetails(
      'itrade_invalidations',
      'iTRADE Signal Invalidations',
      channelDescription: 'Alerts when an armed iTRADE signal reverses',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);
    await _notif.show(
      (asset.hashCode ^ 0x5A5A5A) & 0x7FFFFFFF,
      '⚠️ $asset — SIGNAL INVALIDATED',
      'The $wasDirection setup reversed before close. NOCTIS iTRADE',
      details,
    );
  }

  // ── Push notification ────────────────────────────────────────────────────
  Future<void> _pushNotification({
    required String asset,
    required String direction,
  }) async {
    if (!_notifReady) return;
    const androidDetails = AndroidNotificationDetails(
      'itrade_signals',
      'iTRADE Signals',
      channelDescription: 'NOCTIS iTRADE live trading signals',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false, // we handle sound ourselves
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);
    final emoji = direction == 'BUY' ? '📈' : '📉';
    await _notif.show(
      asset.hashCode & 0x7FFFFFFF,
      '$emoji $asset — $direction SIGNAL',
      'NOCTIS iTRADE · Tap to open the app',
      details,
    );
  }

  void dispose() {
    _tickPlayer.dispose();
    _signalPlayerA.dispose();
    _signalPlayerB.dispose();
  }
}
