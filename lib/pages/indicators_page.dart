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
// Garden of Swords — Indicators Page
//
// 3-node tomoe layout (positions only — node design unchanged):
//   TOP node          → AO   (value only, no label)
//   BOTTOM-RIGHT node → STOCH (OVERBOUGHT / OVERSOLD only, blank if neutral)
//   BOTTOM-LEFT node  → AC   (value only, no label)
//
// Below the radial: live data panel showing exact MT5-style readings
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
      body: SafeArea(
        child: Column(children: [

          // ── Header ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Text(widget.asset,
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.bold, color: AppColors.text)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.redFaint,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(widget.tf,
                        style: const TextStyle(fontSize: 10,
                            fontWeight: FontWeight.bold, color: AppColors.red,
                            letterSpacing: 1)),
                  ),
                  const SizedBox(width: 8),
                  const Text('ENGINES',
                      style: TextStyle(fontSize: 10, letterSpacing: 2,
                          fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                ]),
                Text('${_secondsToClose}s',
                    style: TextStyle(fontSize: 13, fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: urgent ? AppColors.red : AppColors.textDim)),
              ],
            ),
          ),

          // ── Radial viewport ──────────────────────────────────────────────────
          Expanded(
            flex: 5,
            child: g == null
                ? const Center(child: Text('Gathering candles…',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)))
                : _GardenViewport(garden: g, popAnim: _popAnim),
          ),

          // ── Live data panel — MT5-style readings ─────────────────────────────
          if (g != null) _DataPanel(garden: g, asset: widget.asset),

          // ── Signal card ──────────────────────────────────────────────────────
          if (g != null) _SignalCard(garden: g),

          const SizedBox(height: 4),
        ]),
      ),

      // ── Bottom bar ──────────────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.redFaint,
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.red, size: 28),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (g?.armed ?? false) ? AppColors.red : AppColors.redFaint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  g?.dirLabel ?? 'SCANNING…',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: (g?.armed ?? false) ? Colors.white : AppColors.red),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radial viewport — 4 floating nodes + central score
// ─────────────────────────────────────────────────────────────────────────────
class _GardenViewport extends StatelessWidget {
  final GardenResult garden;
  final Animation<double> popAnim;
  const _GardenViewport({required this.garden, required this.popAnim});

  @override
  Widget build(BuildContext context) {
    const sz      = 290.0;
    const nodeSz  = 84.0;
    const half    = sz / 2;
    const nodeH   = nodeSz / 2;
    final g       = garden;

    // ── Node colors ──────────────────────────────────────────────────────────
    // AO: orange when rising, red when falling and negative, cyan when positive
    final aoColor = g.ao < 0
        ? (g.aoRising ? const Color(0xFFFF8C00) : const Color(0xFFFF4A4A))
        : (g.aoRising ? const Color(0xFFFF8C00) : const Color(0xFF33D8FF));

    // AC: same color logic
    final acColor = g.ac < 0
        ? (g.acRising ? const Color(0xFFFF8C00) : const Color(0xFFFF4A4A))
        : (g.acRising ? const Color(0xFFFF8C00) : const Color(0xFFD763FF));

    // Stoch: overbought=red, oversold=green, neutral=orange
    final stochColor = g.stochK > 80
        ? const Color(0xFFFF4A4A)
        : g.stochK < 20
            ? const Color(0xFF47F05F)
            : const Color(0xFFFF8C00);

    // ── Tomoe positions — 3 nodes at 120° apart around the ring ───────────────
    // Angles measured from center; 0° = top, clockwise.
    //   AO           → top          (angle   0°)
    //   STOCH        → bottom-right (angle 120°)
    //   AC           → bottom-left  (angle 240°)
    const radius = half - nodeH * 0.15;
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

    return Center(
      child: SizedBox(width: sz, height: sz,
        child: Stack(clipBehavior: Clip.none, children: [

          Positioned.fill(child: ParticleLayer(garden: g)),

          // ── AO node — TOMOE TOP ──────────────────────────────────────────────
          Positioned(left: aoPos.dx, top: aoPos.dy,
            child: _FloatingNode(offset: const Offset(0, -5),
              child: RadialNode(
                size: nodeSz, color: aoColor, pct: g.aoPct,
                pinAngle: _ang(nodeSz, 78, 13),
                child: _NodeContent(
                  line1: _fmtOsc(g.ao),
                  line1Color: aoColor,
                )))),

          // ── STOCH node — TOMOE BOTTOM-RIGHT ─────────────────────────────────
          Positioned(left: stochPos.dx, top: stochPos.dy,
            child: _FloatingNode(offset: const Offset(5, 4),
              child: RadialNode(
                size: nodeSz, color: stochColor, pct: g.stochK,
                pinAngle: _ang(nodeSz, 76, 76),
                child: _NodeContent(
                  line1: g.stochLabel == 'NEUTRAL' ? '' : g.stochLabel,
                  line1Color: stochColor,
                )))),

          // ── AC node — TOMOE BOTTOM-LEFT ──────────────────────────────────────
          Positioned(left: acPos.dx, top: acPos.dy,
            child: _FloatingNode(offset: const Offset(-5, 4),
              child: RadialNode(
                size: nodeSz, color: acColor, pct: g.acPct,
                pinAngle: _ang(nodeSz, 12, 76),
                child: _NodeContent(
                  line1: _fmtOsc(g.ac),
                  line1Color: acColor,
                )))),

          // ── Central score ────────────────────────────────────────────────────
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(
                scale: popAnim,
                child: Text(
                  '${g.score}',
                  style: TextStyle(
                    fontSize: 56, fontWeight: FontWeight.w900,
                    letterSpacing: -2,
                    color: g.score >= 75
                        ? AppColors.red
                        : g.score >= 50
                            ? const Color(0xFFE67E22)
                            : AppColors.text,
                  ),
                ),
              ),
              const Text('/ 100',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500,
                      color: AppColors.textMuted)),
              const SizedBox(height: 2),
              // Confidence trend — momentum of confluence over last 5 candles
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  g.scoreTrend == 'RISING'  ? Icons.trending_up
                      : g.scoreTrend == 'FALLING' ? Icons.trending_down
                      : Icons.trending_flat,
                  size: 13,
                  color: g.scoreTrend == 'RISING'  ? const Color(0xFF27AE60)
                      : g.scoreTrend == 'FALLING' ? AppColors.red
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 3),
                Text(g.scoreTrend,
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: g.scoreTrend == 'RISING'  ? const Color(0xFF27AE60)
                            : g.scoreTrend == 'FALLING' ? AppColors.red
                            : AppColors.textMuted)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // Convert absolute pixel coords within node to ring angle (radians)
  double _ang(double ns, double py, double px) =>
      math.atan2(py - ns / 2, px - ns / 2);

  // Format oscillator value — show sign, 5 decimals
  String _fmtOsc(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v.abs() < 1 ? 5 : 3)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Live data panel — MT5-style exact readings below the radial
// ─────────────────────────────────────────────────────────────────────────────
class _DataPanel extends StatelessWidget {
  final GardenResult garden;
  final String asset;
  const _DataPanel({required this.garden, required this.asset});

  @override
  Widget build(BuildContext context) {
    final g    = garden;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Row 1: Stoch ──
        Row(children: [
          _dataLabel('Stoch(25,5,8)'),
          const Spacer(),
          _dataVal('K  ${g.stochK.toStringAsFixed(2)}',
              g.stochK > 80 ? AppColors.red
                  : g.stochK < 20 ? const Color(0xFF27AE60)
                  : AppColors.text),
          const SizedBox(width: 12),
          _dataVal('D  ${g.stochD.toStringAsFixed(2)}', AppColors.textDim),
          const SizedBox(width: 10),
          _badge(g.stochLabel,
              g.stochLabel == 'OVERBOUGHT' ? AppColors.red
                  : g.stochLabel == 'OVERSOLD' ? const Color(0xFF27AE60)
                  : AppColors.textMuted),
        ]),
        const SizedBox(height: 6),

        // ── Row 2: AO ──
        Row(children: [
          _dataLabel('AO'),
          const Spacer(),
          _dataVal(_fmtOsc(g.ao), g.ao < 0 ? AppColors.red : AppColors.text),
          const SizedBox(width: 10),
          _barBadge(g.aoRising),
          if (g.aoPct > 0) ...[
            const SizedBox(width: 6),
            _dataVal('${g.aoPct.round()}%', AppColors.textMuted,
                size: 10),
          ],
        ]),
        const SizedBox(height: 6),

        // ── Row 3: AC ──
        Row(children: [
          _dataLabel('AC'),
          const Spacer(),
          _dataVal(_fmtOsc(g.ac), g.ac < 0 ? AppColors.red : AppColors.text),
          const SizedBox(width: 10),
          _barBadge(g.acRising),
        ]),
        const SizedBox(height: 6),

        // ── Row 4: spike counter ──
        Row(children: [
          _dataLabel('Since last spike'),
          const Spacer(),
          _dataVal('${g.candlesSinceSpike} candles', AppColors.textDim),
        ]),
      ]),
    );
  }

  Widget _dataLabel(String t) => Text(t,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
          color: AppColors.textDim, fontFamily: 'monospace'));

  Widget _dataVal(String t, Color c, {double size = 12}) => Text(t,
      style: TextStyle(fontSize: size, fontWeight: FontWeight.bold,
          color: c, fontFamily: 'monospace'));

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25))),
    child: Text(label, style: TextStyle(fontSize: 9,
        fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
  );

  Widget _barBadge(bool rising) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
        color: rising
            ? const Color(0xFFFF8C00).withValues(alpha: 0.10)
            : const Color(0xFF888888).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6)),
    child: Text(rising ? '▲ ORANGE' : '▼ BLACK',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold,
            color: rising ? const Color(0xFFFF8C00) : const Color(0xFF888888))),
  );

  String _fmtOsc(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(v.abs() < 1 ? 5 : 3)}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal card
// ─────────────────────────────────────────────────────────────────────────────
class _SignalCard extends StatelessWidget {
  final GardenResult garden;
  const _SignalCard({required this.garden});

  @override
  Widget build(BuildContext context) {
    final g     = garden;
    final isSell = g.signal == 'SELL';
    final isBuy  = g.signal == 'BUY';
    final armed  = isSell || isBuy;

    final sigColor  = isSell ? AppColors.red
        : isBuy     ? const Color(0xFF27AE60)
        :               AppColors.textMuted;
    final bgColor   = armed
        ? sigColor.withValues(alpha: 0.06) : AppColors.cardAlt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: armed ? sigColor.withValues(alpha: 0.30) : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Direction icon + score
            Row(children: [
              Icon(
                isSell ? Icons.trending_down_rounded
                    : isBuy ? Icons.trending_up_rounded
                    : Icons.trending_flat_rounded,
                color: sigColor, size: 26,
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isSell ? 'BEARISH SIGNAL'
                        : isBuy ? 'BULLISH SIGNAL'
                        : 'SCANNING…',
                    style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.bold, color: sigColor,
                        letterSpacing: 1),
                  ),
                  Text(
                    armed
                        ? (g.score >= 75 ? 'High probability' : 'Moderate setup')
                        : 'Waiting for confluence',
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ]),
            ]),

            // Score pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: armed
                    ? sigColor.withValues(alpha: 0.12) : AppColors.cardAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: armed
                        ? sigColor.withValues(alpha: 0.30) : AppColors.border),
              ),
              child: Text('${g.score}%',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w800, color: sigColor)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating node wrapper — gentle oscillation
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

// ─────────────────────────────────────────────────────────────────────────────
// Node content — up to 3 text lines
// ─────────────────────────────────────────────────────────────────────────────
class _NodeContent extends StatelessWidget {
  final String  line1;
  final Color   line1Color;

  const _NodeContent({
    required this.line1,
    required this.line1Color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Big value (or status word) — no name label, no sub-lines
          Text(line1,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                  color: line1Color, fontFamily: 'monospace'),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
    );
  }
}
