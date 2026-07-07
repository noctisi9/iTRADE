import 'package:flutter_background_service/flutter_background_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundServiceManager
//
// Wraps flutter_background_service to run a persistent Android foreground
// service with a visible notification ("iTRADE — Live"), the same pattern
// MetaTrader and other trading apps use to survive the phone being locked
// or the app being backgrounded.
//
// Important scope note: this keeps the OS from killing the app process, so
// the existing DerivFeed WebSocket connections (running in the main
// isolate) keep receiving data while the phone is locked. It does NOT
// duplicate the trading logic into a separate isolate — that would mean
// re-implementing DerivFeed/GardenState/JournalDb access across an isolate
// boundary, which is a much larger refactor. For a single-device personal
// trading tool, the foreground-service-keeps-process-alive approach is the
// standard, well-supported pattern and is what's implemented here.
//
// Known device-level limitation (not fixable in code): some manufacturer
// Android skins (Samsung One UI, Xiaomi MIUI, Huawei EMUI) aggressively
// kill background processes regardless of foreground service status unless
// the user manually exempts the app in battery settings. There is no way
// to bypass this from the app itself — the user has to grant that exemption
// on their device.
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundServiceManager {
  BackgroundServiceManager._();
  static final BackgroundServiceManager instance = BackgroundServiceManager._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'itrade_live',
        initialNotificationTitle: 'iTRADE — Live',
        initialNotificationContent: 'Keeping your live feed connected in the background',
        foregroundServiceNotificationId: 9001,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
      ),
    );
  }

  Future<void> start() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  Future<void> stop() async {
    final service = FlutterBackgroundService();
    if (await service.isRunning()) {
      service.invoke('stop');
    }
  }

  Future<bool> isRunning() => FlutterBackgroundService().isRunning();

  @pragma('vm:entry-point')
  static void _onStart(ServiceInstance service) async {
    if (service is AndroidServiceInstance) {
      service.on('stop').listen((event) {
        service.stopSelf();
      });
      // Keep the foreground notification alive. The actual live data
      // connections run in the main app isolate (DerivFeed) — this
      // service's only job is to hold a foreground presence so Android
      // doesn't kill the whole process while the phone is locked.
      service.setAsForegroundService();
    }
  }
}
