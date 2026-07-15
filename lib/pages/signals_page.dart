import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
import '../services/garden_calc.dart';
import '../services/indicators.dart';
import '../services/journal_db.dart';
import '../services/sound_service.dart';
import '../theme.dart';
import '../widgets/candle_chart.dart';
import '../widgets/pulsing_dot.dart';

enum SignalDirection { none, buy, sell }

class SignalsPage extends StatefulWidget {
  final String initialAsset;
  final String initialTf;
  final ValueChanged<String> onAssetChanged;
  final ValueChanged<String> onTfChanged;
  final void Function(String asset) onOpenEngines;

  const SignalsPage({
    super.key,
    required this.initialAsset,
    required this.initialTf,
    required this.onAssetChanged,
    required this.onTfChanged,
    required this.onOpenEngines,
  });

  @override
  State<SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<SignalsPage> {
  late final PageController _pageCtrl;
  late int    _page;
  late String _tf;

  @override
  void initState() {
    super.initState();
    _page   = kAssets.indexOf(widget.initialAsset).clamp(0, kAssets.length - 1);
    _tf     = widget.initialTf;
    _pageCtrl = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Column(
      children: [
        // ── Timeframe selector — portrait only. In landscape all 3
        // timeframes are shown at once, so there's nothing to pick. ──
        if (!isLandscape) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: kGranularities.keys.map((tf) {
                final active = tf == _tf;
                return GestureDetector(
                  onTap: () {
                    setState(() => _tf = tf);
                    widget.onTfChanged(tf);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? AppColors.red : AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: active ? AppColors.red : AppColors.border),
                    ),
                    child: Text(tf,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.4,
                          color: active ? Colors.white : AppColors.textDim,
                        )),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
        ],

        // ── Asset page view ──
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageCtrl,
                scrollDirection: Axis.vertical,
                itemCount: kAssets.length,
                onPageChanged: (i) {
                  setState(() => _page = i);
                  widget.onAssetChanged(kAssets[i]);
                },
                itemBuilder: (_, i) => isLandscape
                    ? _LandscapeTriView(
                        key: ValueKey('${kAssets[i]}_landscape'),
                        asset: kAssets[i],
                        onOpenEngines: widget.onOpenEngines,
                      )
                    : _AssetView(
                        key: ValueKey('${kAssets[i]}_$_tf'),
                        asset: kAssets[i],
                        tf: _tf,
                        onOpenEngines: widget.onOpenEngines,
                      ),
              ),
              Positioned(
                left: 0, right: 0, bottom: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(kAssets.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.red
                            : AppColors.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Landscape view — same asset, all 3 timeframes side by side instead of
// picking one from the top selector. Each column is the exact same
// _AssetView used in portrait (same chart, same signal pill, same
// everything) — just three of them at once, one per timeframe.
// ─────────────────────────────────────────────────────────────────────────────
class _LandscapeTriView extends StatelessWidget {
  final String asset;
  final void Function(String) onOpenEngines;

  const _LandscapeTriView({
    super.key,
    required this.asset,
    required this.onOpenEngines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: kGranularities.keys.map((tf) {
        return Expanded(
          child: _AssetView(
            key: ValueKey('${asset}_${tf}_landscape'),
            asset: asset,
            tf: tf,
            onOpenEngines: onOpenEngines,
            tfBadge: tf,
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-asset view — one instance per asset×timeframe combo
// ─────────────────────────────────────────────────────────────────────────────
class _AssetView extends StatefulWidget {
  final String asset;
  final String tf;
  final void Function(String) onOpenEngines;
  final String? tfBadge; // shown only in landscape's 3-column view

  const _AssetView({
    super.key,
    required this.asset,
    required this.tf,
    required this.onOpenEngines,
    this.tfBadge,
  });

  @override
  State<_AssetView> createState() => _AssetViewState();
}

class _AssetViewState extends State<_AssetView> {
  final GardenState _gardenState = GardenState();

  StreamSubscription<List<Candle>>? _sub;
  List<Candle> _candles = [];
  GardenResult? _garden;
  Timer? _ticker;
  Timer? _copiedTimer;
  int _secondsToClose = 60;
  bool _justCopied = false;

  // Signal session tracking
  String  _activeSignal    = 'WAIT';
  double  _sessionEntry    = 0;
  int     _sessionOpenEpoch = 0;
  int     _sessionCandles  = 0;
  int     _sessionPeakScore = 0;
  int?    _lastLoggedEpoch;

  @override
  void initState() {
    super.initState();
    final symbol = assetSymbol[widget.asset]!;

    // Gap-fill: log missed candles
    DerivFeed.instance.onGapFilled = (key, gap) {
      if (key == feedKey(symbol, widget.tf)) _journalBatch(gap);
    };

    _candles = DerivFeed.instance.current(symbol, widget.tf);
    _garden  = _gardenState.compute(_candles, widget.asset);

    _sub = DerivFeed.instance.stream(symbol, widget.tf).listen(_onCandles);
    _ticker = Timer.periodic(
        const Duration(seconds: 1), (_) => _tickCountdown());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  // ── Countdown ──────────────────────────────────────────────────────────────
  void _tickCountdown() {
    final now  = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final gran = kGranularities[widget.tf]!;
    final left = gran - (now % gran);
    if (mounted) setState(() => _secondsToClose = left);
    if (left <= 10) SoundService.instance.countdownTick(left);
  }

  // ── Candle update ──────────────────────────────────────────────────────────
  void _onCandles(List<Candle> candles) {
    if (!mounted) return;
    _candles = candles;
    final g = _gardenState.compute(candles, widget.asset);

    // Signal session management
    if (g != null) {
      final newSig = g.signal;
      if (newSig != 'WAIT' && _activeSignal == 'WAIT') {
        // Session opened
        _activeSignal     = newSig;
        _sessionEntry     = candles.isNotEmpty ? candles.last.c : 0;
        _sessionOpenEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
        _sessionCandles   = 0;
        _sessionPeakScore = g.score;
        SoundService.instance.signalAlert(
            asset: widget.asset, direction: newSig);
      } else if (newSig == 'WAIT' && _activeSignal != 'WAIT') {
        // Session closed — indicators reversed before a manual close.
        // This is exactly the "signal invalidated" case: alert the user.
        SoundService.instance.invalidationAlert(
            asset: widget.asset, wasDirection: _activeSignal);
        _closeSession(candles);
        _activeSignal = 'WAIT';
      } else if (newSig != 'WAIT') {
        // Session ongoing
        _sessionPeakScore = g.score > _sessionPeakScore ? g.score : _sessionPeakScore;
        _sessionCandles++;
      }
    }

    setState(() => _garden = g);
    _maybeLog(candles, g);
  }

  // ── Log closed candle ──────────────────────────────────────────────────────
  void _maybeLog(List<Candle> candles, GardenResult? g) {
    if (candles.length < 2) return;
    final closed = candles[candles.length - 2];
    if (_lastLoggedEpoch == closed.epoch) return;
    _lastLoggedEpoch = closed.epoch;
    _logOne(closed, g);
  }

  void _logOne(Candle c, GardenResult? g) async {
    final num = await JournalDb.instance.nextCandleNum(widget.asset, widget.tf);
    JournalDb.instance.logCandle(JournalEntry(
      asset: widget.asset,
      timeframe: widget.tf,
      epoch: c.epoch,
      candleNum: num,
      open: c.o, high: c.h, low: c.l, close: c.c,
      movement: c.c - c.o,
      spike: c.spike,
      ao:        g?.ao ?? 0,
      ac:        g?.ac ?? 0,
      stochK:    g?.stochK ?? 50,
      stochLabel: g?.stochLabel ?? 'NEUTRAL',
      riskPct:   g?.score ?? 0,
      signal:    g?.signal ?? 'WAIT',
      candlesSinceSpike: g?.candlesSinceSpike ?? 0,
    ));
  }

  // ── Batch log gap-fill candles ─────────────────────────────────────────────
  void _journalBatch(List<Candle> gap) {
    final all = List<Candle>.from(_candles);
    for (final c in gap) {
      final idx = all.indexWhere((x) => x.epoch == c.epoch);
      if (idx < 1) continue;
      final slice = all.sublist(0, idx);
      final g = _gardenState.compute(slice, widget.asset);
      _logOne(c, g);
    }
  }

  // ── Close signal session ───────────────────────────────────────────────────
  void _closeSession(List<Candle> candles) {
    if (_activeSignal == 'WAIT' || _sessionOpenEpoch == 0) return;
    final exitPrice = candles.isNotEmpty ? candles.last.c : _sessionEntry;
    final closeEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    JournalDb.instance.logSession(SignalSession(
      asset: widget.asset,
      timeframe: widget.tf,
      signal: _activeSignal,
      openEpoch: _sessionOpenEpoch,
      closeEpoch: closeEpoch,
      entryPrice: _sessionEntry,
      exitPrice: exitPrice,
      candlesHeld: _sessionCandles,
      pointMove: (exitPrice - _sessionEntry).abs(),
      peakScore: _sessionPeakScore,
    ));
  }

  // ── Summary line ───────────────────────────────────────────────────────────
  String _summaryLine() {
    final g = _garden;
    if (g == null) return 'Gathering data…  ${_secondsToClose}s';
    return '${buildSummaryLine(g, widget.asset)}  · ${_secondsToClose}s';
  }

  // ── Signal copy text — NOX❄ format ────────────────────────────────────────
  String _signalText() {
    final g     = _garden;
    final score = g?.score ?? 0;
    final sig   = g?.signal ?? 'WAIT';
    final emoji = widget.asset.startsWith('BOOM') ? '💥' : '📊';

    if (sig == 'WAIT') {
      return '*_${widget.asset} $emoji | NO SIGNAL |_*\n*NOX❄*';
    }
    return '*_📊 ${widget.asset} $sig: NOW_*\n'
        '*_📈 Targets:_*\n'
        '    🎯TP¹: 5 Candles\n'
        '*_❌ Stop Loss: NONE_*\n'
        '*_🔘 MANAGE YOUR OWN RISK_*\n'
        '*_⚡ Risk Score: $score%_*\n'
        ' *TRADE COMPLETE 👍_*❤️\n'
        '*NOX❄*';
  }

  void _copySignal() {
    Clipboard.setData(ClipboardData(text: _signalText()));
    _copiedTimer?.cancel();
    setState(() => _justCopied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  Color _riskColor(int pct) {
    if (pct < 33) return const Color(0xFF27AE60);
    if (pct < 66) return const Color(0xFFE67E22);
    return AppColors.red;
  }

  @override
  Widget build(BuildContext context) {
    final live   = _candles.isNotEmpty ? _candles.last.c : null;
    final urgent = _secondsToClose <= 10;
    final g      = _garden;
    final armed  = g?.armed ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Asset header ──
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(widget.asset,
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.6, color: AppColors.text)),
                if (widget.tfBadge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.redFaint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(widget.tfBadge!,
                        style: const TextStyle(fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1, color: AppColors.red)),
                  ),
                ],
              ]),
              Row(children: [
                Text(live != null ? live.toStringAsFixed(3) : '—',
                    style: const TextStyle(
                        fontSize: 10, fontFamily: 'monospace',
                        color: AppColors.textDim)),
                const SizedBox(width: 6),
                const PulsingDot(size: 7),
                const SizedBox(width: 6),
                Text('${_secondsToClose}s',
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: urgent ? AppColors.red : AppColors.textDim)),
              ]),
            ],
          ),
          const SizedBox(height: 8),

          // ── Chart ──
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.card,
                    border: Border.all(color: AppColors.border)),
                child: Stack(children: [
                  _candles.isEmpty
                      ? const Center(child: Text('Connecting…',
                          style: TextStyle(color: AppColors.textMuted)))
                      : CandleChart(candles: _candles),
                  // Engines button
                  Positioned(right: 6, top: 0, bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => widget.onOpenEngines(widget.asset),
                        child: Text('↬', style: TextStyle(fontSize: 32,
                            color: AppColors.red, fontWeight: FontWeight.bold,
                            shadows: [Shadow(
                                color: Colors.white.withValues(alpha: 0.9),
                                blurRadius: 6)])),
                      ),
                    ),
                  ),
                  // Chart info badge — candles since spike + score + signal
                  if (g != null)
                    Positioned(left: 8, top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${g.candlesSinceSpike}c since spike',
                              style: const TextStyle(fontSize: 9,
                                  fontFamily: 'monospace',
                                  color: AppColors.textDim),
                            ),
                            Text(
                              'Score ${g.score}/100',
                              style: TextStyle(fontSize: 9,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: _riskColor(g.score)),
                            ),
                            if (g.armed)
                              Text(
                                g.signal,
                                style: const TextStyle(fontSize: 9,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.red),
                              ),
                          ],
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Summary line ──
          Text(_summaryLine(),
              style: const TextStyle(fontSize: 11,
                  fontFamily: 'monospace', color: AppColors.textDim)),
          const SizedBox(height: 8),

          // ── Signal pill ──
          GestureDetector(
            onTap: _copySignal,
            child: Container(
              width: double.infinity,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: armed ? AppColors.red : AppColors.redFaint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                _justCopied ? 'COPIED ✓'
                    : !armed ? 'SCANNING'
                    : g?.signal == 'BUY' ? 'BUY NOW'
                    : 'SELL NOW',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                    color: armed ? Colors.white : AppColors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
