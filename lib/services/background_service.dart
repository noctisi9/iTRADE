import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundServiceManager v2
//
// All operations wrapped in try-catch — NEVER crashes the main app even if
// the background service fails (e.g. when battery optimization is disabled
// on Samsung/Xiaomi which can trigger a force-stop during init).
//
// The service's only job is to keep the process alive while the phone is
// locked so DerivFeed WebSocket stays connected. If it fails, the app
// continues normally — the feed just disconnects when the screen locks.
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundServiceManager {
  BackgroundServiceManager._();
  static final BackgroundServiceManager instance = BackgroundServiceManager._();

  bool _initialized = false;
  bool _available   = true; // set false if bg service is unavailable on device

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final service = FlutterBackgroundService();
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          notificationChannelId: 'itrade_live',
          initialNotificationTitle: 'iTRADE — Live',
          initialNotificationContent: 'Signals active in background',
          foregroundServiceNotificationId: 9001,
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
        ),
      );
    } catch (_) {
      // Background service unavailable on this device — continue silently
      _available = false;
    }
  }

  Future<void> start() async {
    if (!_available) return;
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) {
        await service.startService();
      }
    } catch (_) {
      _available = false;
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke('stop');
      }
    } catch (_) {}
  }

  Future<bool> isRunning() async {
    if (!_available) return false;
    try {
      return await FlutterBackgroundService().isRunning();
    } catch (_) {
      return false;
    }
  }

  bool get isAvailable => _available;

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    try {
      if (service is AndroidServiceInstance) {
        service.on('stop').listen((_) => service.stopSelf());
        await service.setAsForegroundService();
      }
    } catch (_) {
      // If anything fails in the background isolate, stop gracefully
      service.stopSelf();
    }
  }
}
