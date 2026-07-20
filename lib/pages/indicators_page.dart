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
// Garden of Swords — Indicators Page v5
//
// THREE nodes at 120° Sharingan tomoe positions, each rotated by its angle:
//   TOP          → NOX I  (value + ▲▼)
//   BOTTOM-LEFT  → NOX II (value + ▲▼)
//   BOTTOM-RIGHT → RISK   (HIGH 🔥 | LOW ❄)
//
// Stochastic completely removed.
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
  int _lastRisk = -1;

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
    if (g != null && g.riskPct != _lastRisk) {
      _lastRisk = g.riskPct;
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

        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
            ],
          ),
        ),

        // ── Radial ──────────────────────────────────────────────────────
        Expanded(
          child: g == null
              ? const Center(child: Text('Gathering data…',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)))
              : _GardenViewport(garden: g, popAnim: _popAnim),
        ),

        // ── Signal card ─────────────────────────────────────────────────
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
                        color: (g?.armed ?? false)
                            ? Colors.white : AppColors.red)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radial viewport — Sharingan 3-node at 120°, each rotated by position angle
// ─────────────────────────────────────────────────────────────────────────────
class _GardenViewport extends StatelessWidget {
  final GardenResult garden;
  final Animation<double> popAnim;
  const _GardenViewport({required this.garden, required this.popAnim});

  @override
  Widget build(BuildContext context) {
    const sz    = 300.0;
    const nodeSz = 88.0;
    const half  = sz / 2;
    const nodeH = nodeSz / 2;
    final g     = garden;

    // ── Node colors ────────────────────────────────────────────────────
    final noxIColor = g.noxIRising
        ? const Color(0xFFFF8C00)   // orange = rising
        : g.noxI < 0
            ? const Color(0xFFFF4A4A) // red = negative falling
            : const Color(0xFF33D8FF); // cyan = positive falling

    final noxIIColor = g.noxIIRising
        ? const Color(0xFFFF8C00)
        : g.noxII < 0
            ? const Color(0xFFFF4A4A)
            : const Color(0xFFD763FF);

    // Risk node: red = HIGH🔥, green-teal = LOW❄
    final riskColor = g.isHighRisk
        ? const Color(0xFFFF4A4A)
        : const Color(0xFF00C9A7);

    // ── Tomoe positions (60% radius, inner ring) ───────────────────────
    const radius = half * 0.60;

    Offset pos(double degrees) {
      final rad = (degrees - 90) * math.pi / 180;
      return Offset(
        half + radius * math.cos(rad) - nodeH,
        half + radius * math.sin(rad) - nodeH,
      );
    }

    final noxIPos  = pos(0);    // top
    final noxIIPos = pos(240);  // bottom-left
    final riskPos  = pos(120);  // bottom-right

    Widget rot(double deg, Widget child) =>
        Transform.rotate(angle: deg * math.pi / 180, child: child);
    Widget unrot(double deg, Widget child) =>
        Transform.rotate(angle: -deg * math.pi / 180, child: child);

    // Risk ring pct — scale 0-100 risk to fill %
    // Low risk = small fill (ring mostly empty = calm)
    // High risk = full fill (ring full = danger)
    final riskRingPct = g.riskPct.toDouble();

    return Center(
      child: SizedBox(width: sz, height: sz,
        child: Stack(clipBehavior: Clip.none, children: [

          Positioned.fill(child: ParticleLayer(garden: g)),

          // ── NOX I — TOP (0°) ─────────────────────────────────────────
          Positioned(left: noxIPos.dx, top: noxIPos.dy,
            child: _FloatingNode(offset: const Offset(0, -4),
              child: rot(0, RadialNode(
                size: nodeSz, color: noxIColor, pct: g.noxIPct,
                pinAngle: _ang(nodeSz, 10, nodeH),
                child: unrot(0, _OscNode(
                  label: 'NOX I',
                  value: _fmt(g.noxI),
                  color: noxIColor,
                  rising: g.noxIRising,
                )))))),

          // ── NOX II — BOTTOM-LEFT (240°) ──────────────────────────────
          Positioned(left: noxIIPos.dx, top: noxIIPos.dy,
            child: _FloatingNode(offset: const Offset(-4, 4),
              child: rot(240, RadialNode(
                size: nodeSz, color: noxIIColor, pct: g.noxIIPct,
                pinAngle: _ang(nodeSz, nodeH * 1.6, 10),
                child: unrot(240, _OscNode(
                  label: 'NOX II',
                  value: _fmt(g.noxII),
                  color: noxIIColor,
                  rising: g.noxIIRising,
                )))))),

          // ── RISK — BOTTOM-RIGHT (120°) ───────────────────────────────
          Positioned(left: riskPos.dx, top: riskPos.dy,
            child: _FloatingNode(offset: const Offset(4, 4),
              child: rot(120, RadialNode(
                size: nodeSz, color: riskColor, pct: riskRingPct,
                pinAngle: _ang(nodeSz, nodeH * 1.6, nodeSz - 10),
                child: unrot(120, _RiskNode(
                  label: g.riskLabel,
                  color: riskColor,
                  candlesSinceSpike: g.candlesSinceSpike,
                )))))),

          // ── Central score / risk display ──────────────────────────────
          Center(
            child: ScaleTransition(
              scale: popAnim,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(g.riskLabel,
                    style: TextStyle(
                      fontSize: g.isHighRisk ? 22 : 24,
                      fontWeight: FontWeight.w900,
                      color: g.isHighRisk
                          ? const Color(0xFFFF4A4A)
                          : const Color(0xFF00C9A7),
                    )),
                const SizedBox(height: 4),
                Text('${g.candlesSinceSpike}c since spike',
                    style: const TextStyle(fontSize: 10,
                        fontFamily: 'monospace',
                        color: AppColors.textMuted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  double _ang(double ns, double py, double px) =>
      math.atan2(py - ns / 2, px - ns / 2);

  String _fmt(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v.abs() < 1 ? 4 : 3)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// NOX I / NOX II node content
// ─────────────────────────────────────────────────────────────────────────────
class _OscNode extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  final bool   rising;
  const _OscNode({required this.label, required this.value,
      required this.color, required this.rising});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 8,
          fontWeight: FontWeight.w700, color: AppColors.textMuted,
          letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(fontSize: 11,
          fontWeight: FontWeight.w900, color: color,
          fontFamily: 'monospace'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 2),
      Text(rising ? '▲' : '▼',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold,
              color: rising ? const Color(0xFFFF8C00) : const Color(0xFF888888))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RISK node content — HIGH🔥 or LOW❄
// ─────────────────────────────────────────────────────────────────────────────
class _RiskNode extends StatelessWidget {
  final String label;  // 'HIGH 🔥' | 'LOW ❄'
  final Color  color;
  final int    candlesSinceSpike;
  const _RiskNode({required this.label, required this.color,
      required this.candlesSinceSpike});

  @override
  Widget build(BuildContext context) {
    final parts = label.split(' ');
    final word  = parts[0];   // HIGH | LOW
    final emoji = parts.length > 1 ? parts[1] : '';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 18)),
      Text(word, style: TextStyle(fontSize: 13,
          fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
      const SizedBox(height: 2),
      Text('${candlesSinceSpike}c',
          style: const TextStyle(fontSize: 9,
              fontFamily: 'monospace', color: AppColors.textMuted)),
    ]);
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: armed
              ? AppColors.red.withValues(alpha: 0.06) : AppColors.cardAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: armed
              ? AppColors.red.withValues(alpha: 0.30) : AppColors.border)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    isSell ? 'SELL SIGNAL'
                        : isBuy ? 'BUY SIGNAL'
                        : 'SCANNING…',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.bold, color: sigColor,
                        letterSpacing: 1)),
                  Text(
                    armed ? g.riskLabel : 'Waiting for alignment',
                    style: TextStyle(fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: armed ? (g.isHighRisk
                            ? const Color(0xFFFF4A4A)
                            : const Color(0xFF00C9A7))
                            : AppColors.textMuted)),
                ]),
            ]),
            // Candles since spike pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border)),
              child: Text('${g.candlesSinceSpike}c',
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                      color: AppColors.textDim)),
            ),
          ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating node + helpers
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
