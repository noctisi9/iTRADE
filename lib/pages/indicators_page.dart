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
// Garden of Swords — Indicators Page v3
// BOOM/CRASH: AO(top) · STOCH(right) · AC(bottom) · MINIMAX(left)
// VIX:        AO(top) · STOCH(right) · AC(bottom) · MOMENTUM(left)
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
  late final Animation<double> _popAnim;
  int _lastScore = -1;

  @override
  void initState() {
    super.initState();
    _popCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _popAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0),  weight: 50),
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
      final left = gran - (now % gran);
      if (mounted) setState(() => _secondsToClose = left);
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
        child: Column(
          children: [
            // ── Header strip ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text(widget.asset,
                        style: const TextStyle(fontSize: 15,
                            fontWeight: FontWeight.bold, color: AppColors.text)),
                    const SizedBox(width: 8),
                    Text(widget.tf,
                        style: const TextStyle(fontSize: 11,
                            fontWeight: FontWeight.bold, letterSpacing: 1.5,
                            color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    const Text('ENGINES',
                        style: TextStyle(fontSize: 11,
                            fontWeight: FontWeight.bold, letterSpacing: 2,
                            color: AppColors.red)),
                  ]),
                  Text('${_secondsToClose}s',
                      style: TextStyle(fontSize: 12,
                          fontFamily: 'monospace', fontWeight: FontWeight.bold,
                          color: urgent ? AppColors.red : AppColors.textDim)),
                ],
              ),
            ),

            Expanded(
              child: g == null
                  ? const Center(child: Text('Gathering candles…',
                      style: TextStyle(color: AppColors.textMuted)))
                  : _GardenViewport(
                      garden: g, popAnim: _popAnim, asset: widget.asset),
            ),

            if (g != null) _SignalCard(garden: g, asset: widget.asset),
          ],
        ),
      ),
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
              child: Container(
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
// Radial viewport
// ─────────────────────────────────────────────────────────────────────────────
class _GardenViewport extends StatelessWidget {
  final GardenResult garden;
  final Animation<double> popAnim;
  final String asset;
  const _GardenViewport(
      {required this.garden, required this.popAnim, required this.asset});

  @override
  Widget build(BuildContext context) {
    const size     = 300.0;
    const nodeSize = 86.0;
    const half     = size / 2;
    const nodeHalf = nodeSize / 2;
    final g        = garden;

    // ── Node colors ──
    final aoColor = g.ao < 0
        ? const Color(0xFFFF4A4A) : const Color(0xFF33D8FF);
    final acColor = g.ac < 0
        ? const Color(0xFFFF4A4A) : const Color(0xFFD763FF);
    final stochColor = g.stochK > 80
        ? const Color(0xFFFF4A4A)
        : g.stochK < 20 ? const Color(0xFF47F05F) : const Color(0xFFFF5A5A);
    // 4th node color from garden result (works for both MINIMAX and MA CROSS)
    final Color fourthColor;
    switch (g.fourthColor) {
      case Color4.red:
        fourthColor = const Color(0xFFFF4A4A);
      case Color4.green:
        fourthColor = const Color(0xFF47F05F);
      case Color4.neutral:
        fourthColor = const Color(0xFFAAAAAA);
    }

    return Center(
      child: SizedBox(
        width: size, height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          const Positioned.fill(child: ParticleLayer()),

          // AO — top
          Positioned(top: -nodeHalf, left: half - nodeHalf,
            child: _FloatingNode(offset: const Offset(0, -6),
              child: RadialNode(size: nodeSize, color: aoColor, pct: g.aoPct,
                pinAngle: _pin(nodeSize, 78, 13),
                child: _NodeContent(label: 'AO',
                    bigVal: g.ao.toStringAsFixed(4), color: aoColor)))),

          // STOCH — right
          Positioned(top: half - nodeHalf, right: -nodeHalf,
            child: _FloatingNode(offset: const Offset(6, 0),
              child: RadialNode(size: nodeSize, color: stochColor,
                pct: g.stochK, pinAngle: _pin(nodeSize, 76, 76),
                child: _NodeContent(label: 'STOCHASTIC',
                    bigVal: '${g.stochK.round()}%',
                    subVal: g.stochLabel, color: stochColor)))),

          // AC — bottom
          Positioned(bottom: -nodeHalf, left: half - nodeHalf,
            child: _FloatingNode(offset: const Offset(0, 6),
              child: RadialNode(size: nodeSize, color: acColor, pct: g.acPct,
                pinAngle: _pin(nodeSize, 12, 76),
                child: _NodeContent(label: 'AC',
                    bigVal: g.ac.toStringAsFixed(4), color: acColor)))),

          // 4th node: MINIMAX (BOOM/CRASH) or MA CROSS (VIX) — left
          Positioned(top: half - nodeHalf, left: -nodeHalf,
            child: _FloatingNode(offset: const Offset(-6, 0),
              child: RadialNode(size: nodeSize, color: fourthColor,
                pct: g.fourthPct, pinAngle: _pin(nodeSize, 12, 13),
                child: _NodeContent(
                    label: g.fourthNodeLabel,
                    bigVal: g.fourthBigVal,
                    subVal: g.fourthSubVal,
                    color: fourthColor)))),

          // Central score
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(
                scale: popAnim,
                child: Text(
                  g.score == -1 ? '—' : '${g.score}',
                  style: TextStyle(fontSize: 58,
                      fontWeight: FontWeight.w800, letterSpacing: -1.5,
                      color: g.score >= 75
                          ? const Color(0xFFFF4A4A) : AppColors.text),
                ),
              ),
              const Text('/ 100', style: TextStyle(fontSize: 18,
                  fontWeight: FontWeight.w500, color: AppColors.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }

  double _pin(double ns, double py, double px) {
    final cx = ns / 2, cy = ns / 2;
    return math.atan2(py - cy, px - cx);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating + node content widgets (unchanged from v2)
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
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
          offset: widget.offset * _anim.value, child: child),
      child: widget.child,
    );
  }
}

class _NodeContent extends StatelessWidget {
  final String label;
  final String bigVal;
  final String? subVal;
  final Color  color;
  const _NodeContent(
      {required this.label, required this.bigVal,
      this.subVal, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(fontSize: 8,
          fontWeight: FontWeight.w600, color: AppColors.textMuted,
          letterSpacing: -0.2)),
      const SizedBox(height: 1),
      Text(bigVal, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
          color: color, letterSpacing: -0.3)),
      if (subVal != null)
        Text(subVal!, style: TextStyle(fontSize: 8,
            fontWeight: FontWeight.w700, color: color)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal card (bottom of radial viewport)
// ─────────────────────────────────────────────────────────────────────────────
class _SignalCard extends StatelessWidget {
  final GardenResult garden;
  final String asset;
  const _SignalCard({required this.garden, required this.asset});

  @override
  Widget build(BuildContext context) {
    final g      = garden;
    final isSell = g.signal == 'SELL';
    final isBuy  = g.signal == 'BUY';
    final armed  = isSell || isBuy;

    final pillBg     = armed ? const Color(0xFFFFF0F0) : const Color(0xFFEEFDF1);
    final pillBorder = armed ? const Color(0xFFFFCDD2) : const Color(0xFFD2FCDA);
    final pillColor  = armed ? const Color(0xFFFF4A4A) : const Color(0xFF42F25B);
    final arrowBg    = armed ? const Color(0xFFFEE2E2) : const Color(0xFFEAFEEF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(
              color: armed
                  ? const Color(0xFFFF4A4A).withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 30, offset: const Offset(0, 10))],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 44, height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: arrowBg, width: 2),
                      color: Colors.white),
                  child: Icon(
                    isSell ? Icons.trending_down_rounded
                        : isBuy ? Icons.trending_up_rounded
                        : Icons.trending_flat_rounded,
                    color: armed ? pillColor : const Color(0xFF42F25B),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: pillBg,
                      border: Border.all(color: pillBorder),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${g.score}%', style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: pillColor)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF4F5F7),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(armed ? 'Valid Setup' : 'Monitoring',
                      style: const TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w600, color: Color(0xFF6A6A6A))),
                ),
              ]),
              Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isSell ? 'Bearish Signal'
                        : isBuy ? 'Bullish Signal'
                        : 'No Signal',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                        color: AppColors.text, height: 1.1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    armed ? (g.score >= 75 ? 'High Probability' : 'Moderate Setup')
                          : 'Waiting for confluence',
                    style: const TextStyle(fontSize: 12,
                        fontWeight: FontWeight.w500, color: AppColors.textMuted),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }
}
