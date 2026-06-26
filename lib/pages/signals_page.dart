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
  final ValueChanged<String> onAssetChanged;
  final void Function(String asset) onOpenEngines;
  const SignalsPage({
    super.key,
    required this.initialAsset,
    required this.onAssetChanged,
    required this.onOpenEngines,
  });

  @override
  State<SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<SignalsPage> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = kAssets.indexOf(widget.initialAsset).clamp(0, kAssets.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          scrollDirection: Axis.vertical,
          itemCount: kAssets.length,
          onPageChanged: (i) {
            setState(() => _page = i);
            widget.onAssetChanged(kAssets[i]);
          },
          itemBuilder: (context, i) => _AssetSignalView(
            asset: kAssets[i],
            onOpenEngines: widget.onOpenEngines,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-asset view
// ─────────────────────────────────────────────────────────────────────────────
class _AssetSignalView extends StatefulWidget {
  final String asset;
  final void Function(String asset) onOpenEngines;
  const _AssetSignalView({required this.asset, required this.onOpenEngines});

  @override
  State<_AssetSignalView> createState() => _AssetSignalViewState();
}

class _AssetSignalViewState extends State<_AssetSignalView> {
  StreamSubscription<List<Candle>>? _sub;
  List<Candle> _candles = [];
  Timer? _ticker;
  Timer? _copiedTimer;
  int _secondsToClose = 60;
  int? _lastLoggedEpoch;
  SignalDirection _direction = SignalDirection.none;
  double _entry  = 0;
  double _target = 0;
  GardenResult? _garden;
  bool _justCopied = false;

  @override
  void initState() {
    super.initState();
    final symbol = assetSymbol[widget.asset]!;
    _candles = DerivFeed.instance.currentCandles(symbol);
    _computeGarden(_candles);

    // Gap-fill callback — journal any candles received while offline
    DerivFeed.instance.onGapFilled = (sym, gapCandles) {
      if (sym != symbol) return;
      _journalBatch(gapCandles);
    };

    _sub = DerivFeed.instance.stream(symbol).listen(_onCandles);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _copiedTimer?.cancel();
    super.dispose();
  }

  void _tickCountdown() {
    final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final left = 60 - (nowEpoch % 60);
    if (mounted) setState(() => _secondsToClose = left);
    if (left <= 10) SoundService.instance.countdownTick(left);
  }

  void _onCandles(List<Candle> candles) {
    if (!mounted) return;
    setState(() => _candles = candles);
    _computeGarden(candles);
    _maybeLog(candles);
  }

  void _computeGarden(List<Candle> candles) {
    final g = calcGarden(candles);
    if (g == null) return;

    final newDir = g.signal == 'BUY'
        ? SignalDirection.buy
        : g.signal == 'SELL'
            ? SignalDirection.sell
            : SignalDirection.none;

    final changed = newDir != _direction && newDir != SignalDirection.none;

    final atr = _atr(candles);
    final mult = isVix(widget.asset) ? 1.5 : 1.0;
    final entry = candles.isNotEmpty ? candles.last.c : 0.0;
    final target = newDir == SignalDirection.buy
        ? entry + atr * mult
        : newDir == SignalDirection.sell
            ? entry - atr * mult
            : entry;

    if (mounted) {
      setState(() {
        _garden   = g;
        _direction = newDir;
        _entry    = entry;
        _target   = target;
      });
    }
    if (changed) {
      SoundService.instance.signalAlert(
        asset: widget.asset,
        direction: g.signal,
      );
    }
  }

  double _atr(List<Candle> candles, {int period = 14}) {
    final tail = candles.length > period
        ? candles.sublist(candles.length - period)
        : candles;
    if (tail.isEmpty) return 0;
    return tail.map((c) => c.h - c.l).reduce((a, b) => a + b) / tail.length;
  }

  // ── Journal a single just-closed candle ──────────────────────────────────
  void _maybeLog(List<Candle> candles) {
    if (candles.length < 2) return;
    final closed = candles[candles.length - 2];
    if (_lastLoggedEpoch == closed.epoch) return;
    _lastLoggedEpoch = closed.epoch;

    final slice = candles.sublist(0, candles.length - 1);
    final g = calcGarden(slice);
    final ind = calcIndicators(slice);
    if (ind == null) return;

    JournalDb.instance.logCandle(_buildEntry(closed, g, ind));
  }

  // ── Journal a batch of gap-fill candles ──────────────────────────────────
  void _journalBatch(List<Candle> gapCandles) {
    final allCandles = List<Candle>.from(_candles);
    for (var i = 0; i < gapCandles.length; i++) {
      final c = gapCandles[i];
      // Reconstruct a slice ending at this candle for indicator calc
      final idx = allCandles.indexWhere((x) => x.epoch == c.epoch);
      if (idx < 1) continue;
      final slice = allCandles.sublist(0, idx);
      if (slice.length < 2) continue;
      final g   = calcGarden(slice);
      final ind = calcIndicators(slice);
      if (ind == null) continue;
      JournalDb.instance.logCandle(_buildEntry(c, g, ind));
    }
  }

  JournalEntry _buildEntry(Candle c, GardenResult? g, IndicatorResult ind) {
    return JournalEntry(
      asset: widget.asset,
      epoch: c.epoch,
      open: c.o,
      high: c.h,
      low: c.l,
      close: c.c,
      movement: c.c - c.o,
      ao: ind.ao,
      ac: ind.ac,
      stochK: g?.stochK ?? 50,
      mmmDelta: g?.mmmDelta ?? 0,
      riskPct: g?.score ?? 0,
      signal: g?.signal ?? 'WAIT',
      spike: c.spike,
      highLowSpread: c.h - c.l,
    );
  }

  // ── Summary line ──────────────────────────────────────────────────────────
  String _summaryLine() {
    final g = _garden;
    if (g == null) return 'Gathering data…';
    final risk = g.score;
    if (isVix(widget.asset)) {
      // VIX: show momentum direction instead of spike count
      final trend = g.mmmBearish ? 'BEARISH MOMENTUM' : 'BULLISH MOMENTUM';
      final maRel = g.ao > 0 ? 'ABOVE MA' : 'BELOW MA';
      return '$trend · $maRel · RISK $risk%';
    }
    return 'RISK $risk% · ${_riskLabel(risk)}';
  }

  String _riskLabel(int pct) {
    if (pct < 33) return 'LOW RISK';
    if (pct < 66) return 'MED RISK';
    return 'HIGH RISK';
  }

  // ── Signal copy text — NOX❄ format ───────────────────────────────────────
  String _signalText() {
    final g = _garden;
    final risk = g?.score ?? 0;
    final dirLabel = _direction == SignalDirection.buy
        ? 'BUY'
        : _direction == SignalDirection.sell
            ? 'SELL'
            : 'WAIT';
    final assetEmoji = widget.asset.startsWith('BOOM') ? '💥' : '📊';

    if (_direction == SignalDirection.none) {
      return '*_${widget.asset.toUpperCase()} $assetEmoji | NO SIGNAL |_*\n'
          '*NOX❄*';
    }

    return '*_📊 ${widget.asset} $dirLabel: NOW_*\n'
        '*_📈 Targets:_*\n'
        '    🎯TP¹: 5 Candles\n'
        '*_❌ Stop Loss: NONE_*\n'
        '*_🔘 MANAGE YOUR OWN RISK_*\n'
        '*_⚡ Risk Score: $risk%_*\n'
        ' *TRADE COMPLETE 👍_*❤️\n'
        '*NOX❄*';
  }

  String _invalidationText() {
    final assetEmoji = widget.asset.startsWith('BOOM') ? '💥' : '📊';
    return '*_${widget.asset.toUpperCase()} $assetEmoji | TRADE INVALIDATED |_*\n'
        ' *TRADE COMPLETE 👍_*❤️\n'
        '*NOX❄*';
  }

  void _copySignal() {
    Clipboard.setData(ClipboardData(text: _signalText()));
    _copiedTimer?.cancel();
    setState(() => _justCopied = true);
    _copiedTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _justCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final live    = _candles.isNotEmpty ? _candles.last.c : null;
    final urgent  = _secondsToClose <= 10;
    final armed   = _direction != SignalDirection.none;
    final g       = _garden;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Asset header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.asset,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.6,
                      color: AppColors.text)),
              Row(children: [
                Text(
                  live != null ? live.toStringAsFixed(3) : '—',
                  style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: AppColors.textDim),
                ),
                const SizedBox(width: 6),
                const PulsingDot(size: 7),
                const SizedBox(width: 6),
                Text('${_secondsToClose}s',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: urgent ? AppColors.red : AppColors.textDim)),
              ]),
            ],
          ),
          const SizedBox(height: 10),

          // ── Chart ──
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                ),
                child: Stack(
                  children: [
                    _candles.isEmpty
                        ? const Center(
                            child: Text('Connecting…',
                                style:
                                    TextStyle(color: AppColors.textMuted)))
                        : CandleChart(candles: _candles),
                    Positioned(
                      right: 6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: () => widget.onOpenEngines(widget.asset),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Text(
                                '↬',
                                style: TextStyle(
                                  fontSize: 32,
                                  color: AppColors.red,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Risk % badge on chart
                    if (g != null)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _riskColor(g.score).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _riskColor(g.score).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${g.score}% RISK',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: _riskColor(g.score),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Summary line ──
          Text(
            _summaryLine(),
            style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.textDim),
          ),
          const SizedBox(height: 10),

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
                _justCopied
                    ? 'COPIED ✓'
                    : !armed
                        ? 'SCANNING'
                        : _direction == SignalDirection.buy
                            ? 'BUY NOW'
                            : 'SELL NOW',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                  color: armed ? Colors.white : AppColors.red,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _riskColor(int pct) {
    if (pct < 33) return const Color(0xFF27AE60);
    if (pct < 66) return const Color(0xFFE67E22);
    return AppColors.red;
  }
}
