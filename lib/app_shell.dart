import 'package:flutter/material.dart';
import 'pages/history_page.dart';
import 'pages/indicators_page.dart';
import 'pages/intro_page.dart';
import 'pages/journal_page.dart';
import 'pages/signals_page.dart';
import 'services/journal_db.dart';
import 'theme.dart';
import 'widgets/pulsing_dot.dart';

enum AppView { signals, journal, history }

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _introDone = false;
  bool _restoring = true;
  AppView _view = AppView.signals;
  String _activeAsset = kAssets.first;
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
        _activeAsset = kAssets.contains(s['activeAsset']) ? s['activeAsset']! : kAssets.first;
        _journalAsset = kAssets.contains(s['journalAsset']) ? s['journalAsset']! : kAssets.first;
        _introDone = true; // returning user, skip intro
      }
      _restoring = false;
    });
  }

  void _persist() {
    JournalDb.instance.saveState(
      view: _view.name,
      activeAsset: _activeAsset,
      journalAsset: _journalAsset,
    );
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                  onTap: () => _setView(AppView.signals)),
              _NavTile(
                  icon: Icons.insights_rounded,
                  label: 'Indicator Engines',
                  selected: false,
                  onTap: () {
                    Navigator.of(context).maybePop();
                    _openEngines(_activeAsset);
                  }),
              _NavTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Journal',
                  selected: _view == AppView.journal,
                  onTap: () => _setView(AppView.journal)),
              _NavTile(
                  icon: Icons.history_rounded,
                  label: 'History',
                  selected: _view == AppView.history,
                  onTap: () => _setView(AppView.history)),
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

class _TopChrome extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onWordmarkTap;
  const _TopChrome({required this.onMenuTap, required this.onWordmarkTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
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
                letterSpacing: 5.6, // ~0.35em at this size
                color: AppColors.red,
              ),
            ),
          ),
          const Spacer(),
          const PulsingDot(size: 10),
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
  const _NavTile({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: selected ? AppColors.red : AppColors.textDim, size: 20),
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
