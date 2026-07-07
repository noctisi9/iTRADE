import 'package:flutter/material.dart';
import 'app_shell.dart';
import 'services/background_service.dart';
import 'services/journal_db.dart';
import 'services/sound_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted sound preference before starting audio engine
  final state  = await JournalDb.instance.loadState();
  final soundOn = (state?['soundOn'] as int? ?? 1) == 1;
  await SoundService.instance.init(soundOn: soundOn);

  // Register the background service config. This does NOT start it —
  // starting/stopping is controlled by the drawer toggle, persisted per user.
  await BackgroundServiceManager.instance.initialize();
  final bgOn = (state?['bgServiceOn'] as int? ?? 0) == 1;
  if (bgOn) await BackgroundServiceManager.instance.start();

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
