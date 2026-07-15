import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
import '../services/garden_calc.dart';
import '../services/indicators.dart';
import '../theme.dart';
import '../widgets/radial_node.dart';
import '../widgets/particle_layer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Garden of Swords — Indicators Page v4
//
// 3-node Sharingan tomoe layout:
//   TOP          → AO   (value + ▲RISING / ▼FALLING)
//   BOTTOM-RIGHT → STOCH (K%, level bar 0–100, OVERBOUGHT/OVERSOLD/NEUTRAL,
//                         ▲RISING / ▼FALLING)
//   BOTTOM-LEFT  → AC   (value + ▲RISING / ▼FALLING)
//
// Data panel REMOVED per user request.
// ─────────────────────────────────────────────────────────────────────────────

class IndicatorsPage extends StatefulWidget {
  final String asset;
  final String tf;
  const IndicatorsPage({super.key, required this.asset, required this.tf});

  @override
  State<IndicatorsPage> createState() => _IndicatorsPageState();
}

class _IndicatorsPageState extends State<IndicatorsPage>
    with TickerProviderStateMixin {
  final GardenState _gardenState = GardenState();
  StreamSubscription<List<Candle>>? _sub;
  List<Candle> _candles = [];
  Timer? _ticker;
  int _secondsToClose = 60;
  GardenResult? _garden;

  late final AnimationController _popCtrl;
  late final Animation<double>   _popAnim;
  int _lastScore = -1;

  @override
  void initState() {
    super.initState();
    _popCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _popAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _popCtrl, curve: Curves.easeOut));

    final symbol = assetSymbol[widget.asset]!;
    _candles = DerivFeed.instance.current(symbol, widget.tf);
    _computeGarden();

    _sub = DerivFeed.instance.stream(symbol, widget.tf).listen((c) {
      if (mounted) setState(() { _candles = c; _computeGarden(); });
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now  = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final gran = kGranularities[widget.tf]!;
      if (mounted) setState(() => _secondsToClose = gran - (now % gran));
    });
  }

  void _computeGarden() {
    final g = _gardenState.compute(_candles, widget.asset);
    _garden = g;
    if (g != null && g.score != _lastScore) {
      _lastScore = g.score;
      _popCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _secondsToClose <= 10;
    final g      = _garden;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(child: Column(children: [

        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Text(widget.asset, style: const TextStyle(fontSize: 14,
                    fontWeight: FontWeight.bold, color: AppColors.text)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.redFaint,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(widget.tf, style: const TextStyle(fontSize: 10,
                      fontWeight: FontWeight.bold, color: AppColors.red,
                      letterSpacing: 1)),
                ),
                const SizedBox(width: 8),
                const Text('ENGINES', style: TextStyle(fontSize: 10,
                    letterSpacing: 2, fontWeight: FontWeight.bold,
                    color: AppColors.textMuted)),
              ]),
              Text('${_secondsToClose}s', style: TextStyle(fontSize: 13,
                  fontFamily: 'monospace', fontWeight: FontWeight.bold,
                  color: urgent ? AppColors.red : AppColors.textDim)),
            ]),
        ),

        // ── Radial ──────────────────────────────────────────────────────────
        Expanded(
          child: g == null
              ? const Center(child: Text('Gathering candles…',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)))
              : _GardenViewport(garden: g, popAnim: _popAnim),
        ),

        // ── Signal card ─────────────────────────────────────────────────────
        if (g != null) _SignalCard(garden: g),
        const SizedBox(height: 4),
      ])),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.redFaint,
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.red, size: 28)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 48, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (g?.armed ?? false) ? AppColors.red : AppColors.redFaint,
                  borderRadius: BorderRadius.circular(24)),
                child: Text(g?.dirLabel ?? 'SCANNING…',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: (g?.armed ?? false) ? Colors.white : AppColors.red)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radial viewport — 3-node Sharingan tomoe at 120° spacing
// ─────────────────────────────────────────────────────────────────────────────
class _GardenViewport extends StatelessWidget {
  final GardenResult garden;
  final Animation<double> popAnim;
  const _GardenViewport({required this.garden, required this.popAnim});

  @override
  Widget build(BuildContext context) {
    const sz     = 300.0;
    const nodeSz = 88.0;
    const half   = sz / 2;
    const nodeH  = nodeSz / 2;
    final g      = garden;

    // ── Node colors ───────────────────────────────────────────────────────────
    // AO: cyan positive, red negative. Orange when bar is rising (regardless of sign)
    final aoColor = g.aoRising
        ? const Color(0xFFFF8C00)  // orange = bar rising
        : g.ao < 0
            ? const Color(0xFFFF4A4A) // red = negative and falling
            : const Color(0xFF33D8FF); // cyan = positive and falling

    // AC: purple positive, red negative. Orange rising.
    final acColor = g.acRising
        ? const Color(0xFFFF8C00)
        : g.ac < 0
            ? const Color(0xFFFF4A4A)
            : const Color(0xFFD763FF);

    // Stoch: red overbought, green oversold, orange neutral
    final stochColor = g.stochK > 80
        ? const Color(0xFFFF4A4A)
        : g.stochK < 20
            ? const Color(0xFF47F05F)
            : const Color(0xFFFF8C00);

    // ── Tomoe positions — 120° spacing, AO at top ─────────────────────────────
    // ── Tomoe positions — 120° spacing, inner ring (60%), each node
    // rotated by its own position angle (Sharingan spinning effect)
    const radius = half * 0.60;

    Offset tomoePos(double degrees) {
      final rad = (degrees - 90) * math.pi / 180;
      return Offset(
        half + radius * math.cos(rad) - nodeH,
        half + radius * math.sin(rad) - nodeH,
      );
    }

    final aoPos    = tomoePos(0);
    final stochPos = tomoePos(120);
    final acPos    = tomoePos(240);

    Widget rotNode(double deg, Widget child) =>
        Transform.rotate(angle: deg * math.pi / 180, child: child);
    Widget rotContent(double deg, Widget child) =>
        Transform.rotate(angle: -deg * math.pi / 180, child: child);

    return Center(
      child: SizedBox(width: sz, height: sz,
        child: Stack(clipBehavior: Clip.none, children: [

          Positioned.fill(child: ParticleLayer(garden: g)),

          // ── AO — TOP (0°) ────────────────────────────────────────────────
          Positioned(left: aoPos.dx, top: aoPos.dy,
            child: _FloatingNode(offset: const Offset(0, -4),
              child: rotNode(0, RadialNode(
                size: nodeSz, color: aoColor, pct: g.aoPct,
                pinAngle: _ang(nodeSz, 10, nodeH),
                child: rotContent(0, _OscNode(
                  label: 'AO',
                  value: _fmtOsc(g.ao),
                  valueColor: aoColor,
                  trend: g.aoRising ? '▲' : '▼',
                  trendColor: g.aoRising
                      ? const Color(0xFFFF8C00)
                      : const Color(0xFF888888),
                )))))),

          // ── STOCH — BOTTOM-RIGHT (120°) ───────────────────────────────────
          Positioned(left: stochPos.dx, top: stochPos.dy,
            child: _FloatingNode(offset: const Offset(4, 4),
              child: rotNode(120, RadialNode(
                size: nodeSz, color: stochColor, pct: g.stochK,
                pinAngle: _ang(nodeSz, nodeH * 1.6, nodeSz - 10),
                child: rotContent(120, _StochNode(
                  k: g.stochK,
                  label: g.stochLabel,
                  labelColor: stochColor,
                  trend: g.stochTrend,
                )))))),

          // ── AC — BOTTOM-LEFT (240°) ────────────────────────────────────────
          Positioned(left: acPos.dx, top: acPos.dy,
            child: _FloatingNode(offset: const Offset(-4, 4),
              child: rotNode(240, RadialNode(
                size: nodeSz, color: acColor, pct: g.acPct,
                pinAngle: _ang(nodeSz, nodeH * 1.6, 10),
                child: rotContent(240, _OscNode(
                  label: 'AC',
                  value: _fmtOsc(g.ac),
                  valueColor: acColor,
                  trend: g.acRising ? '▲' : '▼',
                  trendColor: g.acRising
                      ? const Color(0xFFFF8C00)
                      : const Color(0xFF888888),
                )))))),

                    // ── Central score ─────────────────────────────────────────────────
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(scale: popAnim,
              child: Text('${garden.score}',
                style: TextStyle(fontSize: 58, fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                  color: garden.score >= 75
                      ? AppColors.red
                      : garden.score >= 50
                          ? const Color(0xFFE67E22)
                          : AppColors.text))),
            const Text('/ 100', style: TextStyle(fontSize: 16,
                fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          ])),
        ]),
      ),
    );
  }

  double _ang(double ns, double py, double px) =>
      math.atan2(py - ns / 2, px - ns / 2);

  String _fmtOsc(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v.abs() < 1 ? 4 : 3)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// AO / AC node content
// ─────────────────────────────────────────────────────────────────────────────
class _OscNode extends StatelessWidget {
  final String label;
  final String value;
  final Color  valueColor;
  final String trend;       // '▲' or '▼'
  final Color  trendColor;

  const _OscNode({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.trend,
    required this.trendColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 8,
          fontWeight: FontWeight.w700, color: AppColors.textMuted,
          letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w900, color: valueColor,
          fontFamily: 'monospace'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(trend, style: TextStyle(fontSize: 14,
          fontWeight: FontWeight.bold, color: trendColor)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stochastic node content — K value, level bar, label, trend
// ─────────────────────────────────────────────────────────────────────────────
class _StochNode extends StatelessWidget {
  final double k;
  final String label;      // OVERBOUGHT | OVERSOLD | NEUTRAL
  final Color  labelColor;
  final String trend;      // 'RISING ▲' | 'FALLING ▼' | 'FLAT'

  const _StochNode({
    required this.k,
    required this.label,
    required this.labelColor,
    required this.trend,
  });

  @override
  Widget build(BuildContext context) {
    // Level bar: 0–100 mapped to node width (56px usable)
    const barW = 52.0;
    final fillW = (k / 100).clamp(0.0, 1.0) * barW;

    // Zone color for the fill
    final fillColor = k > 80
        ? const Color(0xFFFF4A4A)
        : k < 20
            ? const Color(0xFF47F05F)
            : labelColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // K value
        Text('${k.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900,
                color: labelColor, fontFamily: 'monospace')),
        const SizedBox(height: 3),
        // Level bar (0 → 100)
        Stack(children: [
          Container(width: barW, height: 5,
              decoration: BoxDecoration(color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(3))),
          Container(width: fillW, height: 5,
              decoration: BoxDecoration(color: fillColor,
                  borderRadius: BorderRadius.circular(3))),
          // Overbought/oversold zone markers at 20% and 80%
          Positioned(left: barW * 0.20 - 0.5,
            child: Container(width: 1, height: 5,
                color: Colors.black.withValues(alpha: 0.15))),
          Positioned(left: barW * 0.80 - 0.5,
            child: Container(width: 1, height: 5,
                color: Colors.black.withValues(alpha: 0.15))),
        ]),
        const SizedBox(height: 3),
        // Label
        if (label != 'NEUTRAL')
          Text(label == 'OVERBOUGHT' ? 'OB' : 'OS',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                  color: labelColor, letterSpacing: 0.5)),
        // Trend
        Text(trend.replaceAll(' ', ''),
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                color: trend.contains('▲')
                    ? const Color(0xFFFF8C00)
                    : trend.contains('▼')
                        ? const Color(0xFF888888)
                        : AppColors.textMuted)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal card
// ─────────────────────────────────────────────────────────────────────────────
class _SignalCard extends StatelessWidget {
  final GardenResult garden;
  const _SignalCard({required this.garden});

  @override
  Widget build(BuildContext context) {
    final g      = garden;
    final isSell = g.signal == 'SELL';
    final isBuy  = g.signal == 'BUY';
    final armed  = isSell || isBuy;

    final sigColor = armed ? AppColors.red : AppColors.textMuted;
    final bgColor  = armed
        ? AppColors.red.withValues(alpha: 0.06) : AppColors.cardAlt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: armed
                  ? AppColors.red.withValues(alpha: 0.30) : AppColors.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(
                isSell ? Icons.trending_down_rounded
                    : isBuy ? Icons.trending_up_rounded
                    : Icons.trending_flat_rounded,
                color: sigColor, size: 26),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isSell ? 'BEARISH — SELL'
                        : isBuy ? 'BULLISH — BUY'
                        : 'SCANNING…',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        color: sigColor, letterSpacing: 1)),
                  Text(
                    armed
                        ? (g.score >= 75 ? 'High confluence — take the trade'
                            : 'Moderate — wait for stronger alignment')
                        : 'Waiting for full indicator alignment',
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.textMuted)),
                ]),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: armed
                    ? AppColors.red.withValues(alpha: 0.12) : AppColors.cardAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: armed
                    ? AppColors.red.withValues(alpha: 0.30) : AppColors.border)),
              child: Text('${g.score}%', style: TextStyle(fontSize: 16,
                  fontWeight: FontWeight.w800, color: sigColor)),
            ),
          ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating node wrapper
// ─────────────────────────────────────────────────────────────────────────────
class _FloatingNode extends StatefulWidget {
  final Widget child;
  final Offset offset;
  const _FloatingNode({required this.child, required this.offset});

  @override
  State<_FloatingNode> createState() => _FloatingNodeState();
}

class _FloatingNodeState extends State<_FloatingNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Transform.translate(
          offset: widget.offset *
              CurvedAnimation(parent: _c, curve: Curves.easeInOut).value,
          child: child),
      child: widget.child,
    );
  }
}
