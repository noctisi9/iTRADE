@'
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
'@ | Set-Content -Path "lib\services\sound_service.dart" -Encoding utf8

@'
name: itrade_flutter
description: "NOCTIS iTRADE - live trading signals for Deriv synthetic indices."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  web_socket_channel: ^2.4.0
  sqflite: ^2.3.0
  path: ^1.9.0
  path_provider: ^2.1.1
  audioplayers: ^5.2.1
  share_plus: ^7.2.1
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - assets/intro/
    - assets/sounds/
'@ | Set-Content -Path "pubspec.yaml" -Encoding utf8

@'
name: Build Android APK

on:
  push:
    branches: [main]
    tags: ['v*']
  workflow_dispatch: {}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Scaffold Android platform files
        run: flutter create --platforms=android --org com.noctis.itrade .

      - name: Remove default test stub (references a class that doesn't exist in this project)
        run: rm -rf test

      - name: Show generated manifest (debug aid)
        run: cat android/app/src/main/AndroidManifest.xml

      - name: Add INTERNET permission (required for the live Deriv feed)
        run: |
          python3 - <<'PY'
          import re
          path = "android/app/src/main/AndroidManifest.xml"
          with open(path) as f:
              content = f.read()
          if "android.permission.INTERNET" not in content:
              content = re.sub(
                  r"(<manifest[^>]*>)",
                  r'\1\n    <uses-permission android:name="android.permission.INTERNET" />',
                  content,
                  count=1,
              )
          with open(path, "w") as f:
              f.write(content)
          assert "android.permission.INTERNET" in content, "Failed to inject INTERNET permission"
          print("Manifest OK:")
          print(content)
          PY

      - name: Set app label
        run: |
          python3 - <<'PY'
          import re
          path = "android/app/src/main/AndroidManifest.xml"
          with open(path) as f:
              content = f.read()
          content = re.sub(r'android:label="[^"]*"', 'android:label="NOCTIS iTRADE"', content, count=1)
          with open(path, "w") as f:
              f.write(content)
          PY

      - name: Bump compileSdk/targetSdk globally (defensive, helps most plugins)
        run: |
          echo "flutter.compileSdkVersion=36" >> android/local.properties
          echo "flutter.targetSdkVersion=36" >> android/local.properties

      - name: Install dependencies
        run: flutter pub get

      - name: Patch audioplayers_android's own compileSdk (the actual file that was failing)
        run: |
          python3 - <<'PY'
          import glob, os

          home = os.path.expanduser("~")
          patterns = [
              f"{home}/.pub-cache/hosted/pub.dev/audioplayers_android-*/android/build.gradle",
              f"{home}/.pub-cache/hosted/pub.dev/audioplayers_android-*/android/build.gradle.kts",
          ]
          candidates = []
          for p in patterns:
              candidates.extend(glob.glob(p))

          print("Found candidate files:", candidates)
          if not candidates:
              print("WARNING: no audioplayers_android Gradle file found — pub cache layout may differ.")

          for path in candidates:
              with open(path) as f:
                  original = f.read()
              content = original
              replacements = [
                  ("compileSdkVersion safeExtGet('compileSdkVersion', 33)", "compileSdkVersion 36"),
                  ('compileSdkVersion safeExtGet("compileSdkVersion", 33)', "compileSdkVersion 36"),
                  ("compileSdk = flutter.compileSdkVersion", "compileSdk = 36"),
                  ("compileSdkVersion flutter.compileSdkVersion", "compileSdkVersion 36"),
                  ("compileSdkVersion 33", "compileSdkVersion 36"),
                  ("compileSdk 33", "compileSdk 36"),
              ]
              for old, new in replacements:
                  content = content.replace(old, new)

              print(f"\n--- {path} (changed: {content != original}) ---")
              print(content)

              if content != original:
                  with open(path, "w") as f:
                      f.write(content)
          PY

      - name: Flutter doctor
        run: flutter doctor -v

      - name: Analyze (surfaces Dart errors clearly before the slow build step)
        run: flutter analyze --no-fatal-infos --no-fatal-warnings

      - name: Build release APK
        run: flutter build apk --release

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: noctis-itrade-apk
          path: build/app/outputs/flutter-apk/app-release.apk

      - name: Attach APK to GitHub Release
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@v2
        with:
          files: build/app/outputs/flutter-apk/app-release.apk
'@ | Set-Content -Path ".github\workflows\build-apk.yml" -Encoding utf8

Write-Host "--- Verifying ---"
Select-String -Path "pubspec.yaml" -Pattern "audioplayers"
Select-String -Path ".github\workflows\build-apk.yml" -Pattern "Patch audioplayers_android"
