import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_shell.dart';
import 'services/background_service.dart';
import 'services/deriv_feed.dart';
import 'services/journal_db.dart';
import 'services/sound_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted state
  final state   = await JournalDb.instance.loadState();
  final soundOn = (state?['soundOn'] as int? ?? 1) == 1;

  // Init audio
  await SoundService.instance.init(soundOn: soundOn);

  // Register background service config
  // Wrapped in try-catch — if battery optimization disables the service,
  // the app continues normally without it rather than crashing
  try {
    await BackgroundServiceManager.instance.initialize();
    final bgOn = (state?['bgServiceOn'] as int? ?? 0) == 1;
    if (bgOn) {
      await BackgroundServiceManager.instance.start().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // Service didn't start in time (common when battery opt is forced)
          // Silently continue — app works without background service
        },
      );
    }
  } catch (_) {
    // Background service unavailable (battery optimization forced stop,
    // or device restriction) — app continues in foreground-only mode
  }

  // Pre-warm ALL assets from SQLite BEFORE showing any UI.
  // This is what eliminates the "Gathering candles..." delay.
  // loadCandles() reads from SQLite — no network call, completes in <100ms
  // per asset on any modern device.
  // unawaited intentionally — we don't block the UI for WebSocket connects,
  // but SQLite warm-up is synchronous within preWarmAll before live subs.
  DerivFeed.instance.preWarmAll(kAssets);

  runApp(const NoctisApp());
}

class NoctisApp extends StatelessWidget {
  const NoctisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOCTIS iTRADE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.red,
          primary: AppColors.red,
          surface: AppColors.bg,
        ),
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const AppShell(),
    );
  }
}
