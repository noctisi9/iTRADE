# NOCTIS · iTRADE (Flutter / Android)

Flutter rebuild of the NOCTIS iTRADE web app — live signals, AO/AC/CUSUM/Kaplan-Meier
indicator engines, and a trade journal for Deriv synthetic indices (BOOM1000, CRASH1000,
VIX75, VIX75 1s).

## Project structure
```
lib/
  models/        Candle
  services/       Deriv WebSocket feed, indicator math, SQLite journal, CSV export, sounds
  widgets/        Chart, histograms, gauges (Welford/CUSUM/Kaplan-Meier), engine cards
  pages/          Intro, Signals, Indicators, Journal, History
  app_shell.dart  Drawer navigation + view switching
  main.dart       Entry point
assets/
  intro/          Onboarding background images
  sounds/         Countdown + signal beep tones
```

The `android/` folder is **not committed** — CI generates it fresh on every build via
`flutter create --platforms=android .`, so it always matches whatever Flutter SDK version
the workflow installs. This avoids hand-maintained Gradle files going stale.

## Run locally
Requires the [Flutter SDK](https://flutter.dev) installed and a connected device/emulator.
```
flutter create --platforms=android .   # only needed once, to generate android/
flutter pub get
flutter run
```

## Build the APK without installing Flutter
Push to `main` (or run the workflow manually from the Actions tab). GitHub Actions will:
1. Install the Flutter SDK
2. Generate the Android platform folder
3. Build a release APK
4. Upload it as a downloadable build artifact (Actions tab → latest run → Artifacts)

To get a permanent download link instead, push a tag like `v1.0.0` — the workflow will
attach the APK directly to a GitHub Release.

## Notes
- Live market data comes from Deriv's public WebSocket API (`wss://ws.derivws.com`), no
  API key required for candle/tick history.
- Journal entries are stored locally on-device via SQLite (`sqflite`) — nothing is synced
  to a server.
- Android only for now (iOS was not in scope for this build).
