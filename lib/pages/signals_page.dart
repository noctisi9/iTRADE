import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
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
                  color: active ? AppColors.red : AppColors.textMuted.withValues(alpha: 0.4),
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
  double _entry = 0, _target = 0;
  double _spikeProb = 0;
  int _sequenceCount = 0;
  bool _justCopied = false;

  @override
  void initState() {
    super.initState();
    final symbol = assetSymbol[widget.asset]!;
    _candles = DerivFeed.instance.currentCandles(symbol);
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
    _recomputeSignal(candles);
    _maybeLog(candles);
  }

  void _recomputeSignal(List<Candle> candles) {
    final ind = calcIndicators(candles);
    final spike = calcSpikeStats(candles);
    if (ind == null || candles.isEmpty) return;
    final entry = candles.last.c;
    final atr = _atr(candles);
    SignalDirection dir = SignalDirection.none;
    if (ind.ao > 0 && ind.ac > 0) {
      dir = SignalDirection.buy;
    } else if (ind.ao < 0 && ind.ac < 0) {
      dir = SignalDirection.sell;
    }
    final mult = isVix(widget.asset) ? 1.5 : 1.0;
    final target = dir == SignalDirection.buy
        ? entry + atr * mult
        : dir == SignalDirection.sell
            ? entry - atr * mult
            : entry;

    final changed = dir != _direction;
    setState(() {
      _direction = dir;
      _entry = entry;
      _target = target;
      _spikeProb = spike?.spikeProb ?? 0;
      _sequenceCount = spike?.sequenceCount ?? 0;
    });
    if (changed && dir != SignalDirection.none) {
      SoundService.instance.signalAlert();
    }
  }

  double _atr(List<Candle> candles, {int period = 14}) {
    final tail = candles.length > period ? candles.sublist(candles.length - period) : candles;
    if (tail.isEmpty) return 0;
    final spreads = tail.map((c) => c.h - c.l);
    return spreads.reduce((a, b) => a + b) / tail.length;
  }

  void _maybeLog(List<Candle> candles) {
    if (candles.length < 2) return;
    final closed = candles[candles.length - 2];
    if (_lastLoggedEpoch == closed.epoch) return;
    _lastLoggedEpoch = closed.epoch;

    final upToClosed = candles.sublist(0, candles.length - 1);
    final ind = calcIndicators(upToClosed);
    final spike = calcSpikeStats(upToClosed);
    if (ind == null) return;

    JournalDb.instance.logCandle(JournalEntry(
      asset: widget.asset,
      epoch: closed.epoch,
      open: closed.o,
      high: closed.h,
      low: closed.l,
      close: closed.c,
      movement: closed.c - closed.o,
      spike: closed.spike,
      candlesSinceSpike: spike?.sequenceCount ?? 0,
      ao: ind.ao,
      ac: ind.ac,
      cusumH: spike?.cusumH,
      cusumThreshold: spike?.cusumThreshold,
      survivalProb: spike?.survivalProb,
      highLowSpread: spike?.highLowSpread,
      tickVolume: spike?.tickVolume,
    ));
  }

  String _riskLabel(double p) {
    if (p < 0.33) return 'LOW RISK';
    if (p < 0.66) return 'MED RISK';
    return 'HIGH RISK';
  }

  String _summaryLine() {
    final base = '$_sequenceCount candles since last spike';
    if (isVix(widget.asset)) return base;
    final pct = (_spikeProb * 100).round();
    return '$base · ${_riskLabel(_spikeProb)} $pct%';
  }

  String _signalText() {
    final dirLabel = _direction == SignalDirection.buy
        ? 'BUY'
        : _direction == SignalDirection.sell
            ? 'SELL'
            : 'WAIT';
    final now = DateTime.now().toUtc();
    final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} UTC';
    return '*NOCTIS SIGNAL — ${widget.asset}*\n'
        'Direction: *$dirLabel*\n'
        'Entry: ${_entry.toStringAsFixed(3)} → Target: ${_target.toStringAsFixed(3)}\n'
        '_${t}_';
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
    final live = _candles.isNotEmpty ? _candles.last.c : null;
    final urgent = _secondsToClose <= 10;
    final armed = _direction != SignalDirection.none;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.asset,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.6,
                  color: AppColors.text,
                ),
              ),
              Row(
                children: [
                  Text(
                    live != null ? live.toStringAsFixed(3) : '—',
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: AppColors.textDim,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const PulsingDot(size: 7),
                  const SizedBox(width: 6),
                  Text(
                    '${_secondsToClose}s',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: urgent ? AppColors.red : AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                            child: Text('Connecting to live feed…',
                                style: TextStyle(color: AppColors.textMuted)))
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
                                    Shadow(color: Colors.white.withValues(alpha: 0.9), blurRadius: 6),
                                  ],
                                ),
                              ),
                            ),
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
          Text(
            _summaryLine(),
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textDim),
          ),
          const SizedBox(height: 10),
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
}
