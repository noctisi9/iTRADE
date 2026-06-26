import 'package:flutter/material.dart';
import 'pages/history_page.dart';
import 'pages/indicators_page.dart';
import 'pages/intro_page.dart';
import 'pages/journal_page.dart';
import 'pages/signals_page.dart';
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
  bool _introDone  = false;
  bool _restoring  = true;
  bool _soundOn    = true;
  AppView _view    = AppView.signals;
  String _activeAsset  = kAssets.first;
  String _journalAsset = kAssets.first;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final s = await JournalDb.instance.loadState();
    if (!mounted) return;
    setState(() {
      if (s != null) {
        _activeAsset  = kAssets.contains(s['activeAsset'])  ? s['activeAsset'] as String : kAssets.first;
        _journalAsset = kAssets.contains(s['journalAsset']) ? s['journalAsset'] as String : kAssets.first;
        _soundOn      = (s['soundOn'] as int? ?? 1) == 1;
        _introDone    = true;
      }
      _restoring = false;
    });
    // Apply persisted sound preference
    SoundService.instance.setMuted(!_soundOn);
  }

  void _persist() {
    JournalDb.instance.saveState(
      view: _view.name,
      activeAsset: _activeAsset,
      journalAsset: _journalAsset,
      soundOn: _soundOn,
    );
  }

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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IndicatorsPage(asset: asset)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (!_introDone) {
      return IntroPage(onDone: () => setState(() => _introDone = true));
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawer: Drawer(
        backgroundColor: AppColors.bg,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  'NOCTIS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 6,
                    color: AppColors.red,
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _NavTile(
                icon: Icons.show_chart_rounded,
                label: 'Signals',
                selected: _view == AppView.signals,
                onTap: () => _setView(AppView.signals),
              ),
              _NavTile(
                icon: Icons.insights_rounded,
                label: 'Indicator Engines',
                selected: false,
                onTap: () {
                  Navigator.of(context).maybePop();
                  _openEngines(_activeAsset);
                },
              ),
              _NavTile(
                icon: Icons.calendar_month_rounded,
                label: 'Journal',
                selected: _view == AppView.journal,
                onTap: () => _setView(AppView.journal),
              ),
              _NavTile(
                icon: Icons.history_rounded,
                label: 'History',
                selected: _view == AppView.history,
                onTap: () => _setView(AppView.history),
              ),
              const Divider(height: 1, color: AppColors.border),
              // Sound toggle in drawer
              ListTile(
                leading: Icon(
                  _soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: _soundOn ? AppColors.red : AppColors.textDim,
                  size: 20,
                ),
                title: Text(
                  _soundOn ? 'Sound ON' : 'Sound OFF',
                  style: TextStyle(
                    color: _soundOn ? AppColors.red : AppColors.textDim,
                    fontSize: 14,
                  ),
                ),
                onTap: _toggleSound,
              ),
              const Spacer(),
              const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(
                  child: Text(
                    '· iTRADE ·',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 2,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TopChrome(
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onWordmarkTap: () => _setView(AppView.signals),
              soundOn: _soundOn,
              onSoundToggle: _toggleSound,
            ),
            Expanded(
              child: IndexedStack(
                index: AppView.values.indexOf(_view),
                children: [
                  SignalsPage(
                    initialAsset: _activeAsset,
                    onAssetChanged: (a) {
                      _activeAsset = a;
                      _persist();
                    },
                    onOpenEngines: _openEngines,
                  ),
                  JournalPage(initialAsset: _journalAsset),
                  HistoryPage(initialAsset: _activeAsset),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top chrome — now has a sound toggle icon on the right
// ─────────────────────────────────────────────────────────────────────────────
class _TopChrome extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onWordmarkTap;
  final bool soundOn;
  final VoidCallback onSoundToggle;

  const _TopChrome({
    required this.onMenuTap,
    required this.onWordmarkTap,
    required this.soundOn,
    required this.onSoundToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.text),
            onPressed: onMenuTap,
          ),
          GestureDetector(
            onTap: onWordmarkTap,
            child: const Text(
              'NOCTIS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 5.6,
                color: AppColors.red,
              ),
            ),
          ),
          const Spacer(),
          // Sound toggle — prominent in nav bar
          GestureDetector(
            onTap: onSoundToggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: soundOn ? AppColors.redFaint : AppColors.cardAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                soundOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: soundOn ? AppColors.red : AppColors.textMuted,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const PulsingDot(size: 10),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavTile(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          Icon(icon, color: selected ? AppColors.red : AppColors.textDim, size: 20),
      title: Text(label,
          style: TextStyle(
              color: selected ? AppColors.red : AppColors.text,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14)),
      selected: selected,
      selectedTileColor: AppColors.redFaint,
      onTap: onTap,
    );
  }
}
