import 'package:flutter/material.dart';
import 'pages/history_page.dart';
import 'pages/indicators_page.dart';
import 'pages/intro_page.dart';
import 'pages/journal_page.dart';
import 'pages/signals_page.dart';
import 'services/deriv_feed.dart';
import 'services/journal_db.dart';
import 'services/sound_service.dart';
import 'theme.dart';
import 'widgets/pulsing_dot.dart';

enum AppView { signals, journal, history }

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool    _introDone  = false;
  bool    _restoring  = true;
  bool    _soundOn    = true;
  AppView _view       = AppView.signals;
  String  _activeAsset   = kAssets.first;
  String  _journalAsset  = kAssets.first;
  String  _tf            = '1m';
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() { super.initState(); _restore(); }

  Future<void> _restore() async {
    final s = await JournalDb.instance.loadState();
    if (!mounted) return;
    setState(() {
      if (s != null) {
        _activeAsset  = kAssets.contains(s['activeAsset'])
            ? s['activeAsset'] as String : kAssets.first;
        _journalAsset = kAssets.contains(s['journalAsset'])
            ? s['journalAsset'] as String : kAssets.first;
        _tf       = kGranularities.containsKey(s['timeframe'])
            ? s['timeframe'] as String : '1m';
        _soundOn  = (s['soundOn'] as int? ?? 1) == 1;
        _introDone = true;
      }
      _restoring = false;
    });
    SoundService.instance.setMuted(!_soundOn);
  }

  void _persist() => JournalDb.instance.saveState(
    view: _view.name, activeAsset: _activeAsset,
    journalAsset: _journalAsset, timeframe: _tf, soundOn: _soundOn,
  );

  void _toggleSound() {
    setState(() => _soundOn = !_soundOn);
    SoundService.instance.setMuted(!_soundOn);
    _persist();
  }

  void _setView(AppView v) {
    setState(() => _view = v);
    _persist();
    Navigator.of(context).maybePop();
  }

  void _openEngines(String asset) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IndicatorsPage(asset: asset, tf: _tf)));
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_introDone) {
      return IntroPage(onDone: () => setState(() => _introDone = true));
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawer: _buildDrawer(),
      body: SafeArea(child: Column(children: [
        _TopChrome(
          onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
          onWordmarkTap: () => _setView(AppView.signals),
        ),
        Expanded(
          child: IndexedStack(
            index: AppView.values.indexOf(_view),
            children: [
              SignalsPage(
                initialAsset: _activeAsset,
                initialTf: _tf,
                onAssetChanged: (a) { _activeAsset = a; _persist(); },
                onTfChanged: (tf) { setState(() => _tf = tf); _persist(); },
                onOpenEngines: _openEngines,
              ),
              JournalPage(initialAsset: _journalAsset, initialTf: _tf),
              HistoryPage(initialAsset: _activeAsset, initialTf: _tf),
            ],
          ),
        ),
      ])),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppColors.bg,
      child: SafeArea(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Text('NOCTIS', style: TextStyle(fontWeight: FontWeight.w900,
                fontSize: 20, letterSpacing: 6, color: AppColors.red)),
          ),
          const Divider(height: 1, color: AppColors.border),
          _NavTile(Icons.show_chart_rounded, 'Signals',
              _view == AppView.signals, () => _setView(AppView.signals)),
          _NavTile(Icons.insights_rounded, 'Indicator Engines', false, () {
            Navigator.of(context).maybePop();
            _openEngines(_activeAsset);
          }),
          _NavTile(Icons.calendar_month_rounded, 'Journal',
              _view == AppView.journal, () => _setView(AppView.journal)),
          _NavTile(Icons.history_rounded, 'History',
              _view == AppView.history, () => _setView(AppView.history)),
          const Divider(height: 1, color: AppColors.border),
          // ── Sound toggle — ONLY here, not in top bar ──
          ListTile(
            leading: Icon(
              _soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: _soundOn ? AppColors.red : AppColors.textDim, size: 20),
            title: Text(_soundOn ? 'Sound ON' : 'Sound OFF',
                style: TextStyle(
                    color: _soundOn ? AppColors.red : AppColors.textDim,
                    fontSize: 14)),
            onTap: _toggleSound,
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Center(child: Text('· iTRADE ·',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11,
                    letterSpacing: 2, color: AppColors.textMuted))),
          ),
        ],
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top chrome — NO sound icon (sound is drawer-only)
// ─────────────────────────────────────────────────────────────────────────────
class _TopChrome extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onWordmarkTap;
  const _TopChrome({required this.onMenuTap, required this.onWordmarkTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(children: [
        IconButton(icon: const Icon(Icons.menu_rounded, color: AppColors.text),
            onPressed: onMenuTap),
        GestureDetector(onTap: onWordmarkTap,
          child: const Text('NOCTIS', style: TextStyle(fontWeight: FontWeight.w900,
              fontSize: 16, letterSpacing: 5.6, color: AppColors.red))),
        const Spacer(),
        const PulsingDot(size: 10),
        const SizedBox(width: 12),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon; final String label;
  final bool selected; final VoidCallback onTap;
  const _NavTile(this.icon, this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? AppColors.red : AppColors.textDim, size: 20),
      title: Text(label, style: TextStyle(
          color: selected ? AppColors.red : AppColors.text,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 14)),
      selected: selected,
      selectedTileColor: AppColors.redFaint,
      onTap: onTap,
    );
  }
}
