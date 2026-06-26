import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
import '../services/indicators.dart';
import '../services/garden_calc.dart';
import '../theme.dart';
import '../widgets/radial_node.dart';
import '../widgets/particle_layer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Garden of Swords — Indicators Page
// Faithfully recreates the HTML radial dashboard as a Flutter widget.
// 4 floating indicator nodes + central composite score + signal card.
// ─────────────────────────────────────────────────────────────────────────────

class IndicatorsPage extends StatefulWidget {
  final String asset;
  const IndicatorsPage({super.key, required this.asset});

  @override
  State<IndicatorsPage> createState() => _IndicatorsPageState();
}

class _IndicatorsPageState extends State<IndicatorsPage>
    with TickerProviderStateMixin {
  StreamSubscription<List<Candle>>? _sub;
  List<Candle> _candles = [];
  Timer? _ticker;
  int _secondsToClose = 60;

  // Computed garden state
  GardenResult? _garden;

  // Score pop animation
  late final AnimationController _popCtrl;
  late final Animation<double> _popAnim;
  int _lastScore = -1;

  @override
  void initState() {
    super.initState();
    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _popAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _popCtrl, curve: Curves.easeOut));

    final symbol = assetSymbol[widget.asset]!;
    _candles = DerivFeed.instance.currentCandles(symbol);
    _computeGarden();

    _sub = DerivFeed.instance.stream(symbol).listen((c) {
      if (mounted) {
        setState(() {
          _candles = c;
          _computeGarden();
        });
      }
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final nowEpoch =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (mounted) setState(() => _secondsToClose = 60 - (nowEpoch % 60));
    });
  }

  void _computeGarden() {
    _garden = calcGarden(_candles);
    if (_garden != null && _garden!.score != _lastScore) {
      _lastScore = _garden!.score;
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
    final g = _garden;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top strip: asset label + ENGINES + countdown ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text(widget.asset,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text)),
                    const SizedBox(width: 8),
                    const Text('ENGINES',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: AppColors.red)),
                  ]),
                  Text('${_secondsToClose}s',
                      style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: urgent ? AppColors.red : AppColors.textDim)),
                ],
              ),
            ),

            // ── Main body: radial viewport ──
            Expanded(
              child: g == null
                  ? const Center(
                      child: Text('Gathering candles…',
                          style: TextStyle(color: AppColors.textMuted)))
                  : _GardenViewport(garden: g, popAnim: _popAnim),
            ),

            // ── Signal card ──
            if (g != null)
              _SignalCard(garden: g)
            else
              const SizedBox(height: 84 + 20),
          ],
        ),
      ),
      // ── Bottom bar: back + signal pill ──
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.redFaint,
                    borderRadius: BorderRadius.circular(14),
                  ),
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
                    color: (g?.armed ?? false)
                        ? AppColors.red
                        : AppColors.redFaint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    g?.dirLabel ?? 'SCANNING…',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: (g?.armed ?? false)
                          ? Colors.white
                          : AppColors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Radial viewport: 340×340 square with 4 floating nodes + particles + score
// ─────────────────────────────────────────────────────────────────────────────
class _GardenViewport extends StatelessWidget {
  final GardenResult garden;
  final Animation<double> popAnim;
  const _GardenViewport({required this.garden, required this.popAnim});

  @override
  Widget build(BuildContext context) {
    const size = 300.0;
    const nodeSize = 86.0;
    const half = size / 2;
    const nodeHalf = nodeSize / 2;

    final g = garden;

    // AO node color (top)
    final aoColor = g.ao < 0
        ? const Color(0xFFFF4A4A)
        : const Color(0xFF33D8FF);

    // AC node color (bottom)
    final acColor = g.ac < 0
        ? const Color(0xFFFF4A4A)
        : const Color(0xFFD763FF);

    // STOCH node (right)
    final double stochK = g.stochK;
    final stochColor = stochK > 80
        ? const Color(0xFFFF4A4A)
        : stochK < 20
            ? const Color(0xFF47F05F)
            : const Color(0xFFFF5A5A);

    // MMM node (left)
    final mmmColor = g.mmmBearish
        ? const Color(0xFFFF4A4A)
        : const Color(0xFF47F05F);

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Particle layer (behind nodes)
            const Positioned.fill(child: ParticleLayer()),

            // ── AO node — TOP ──
            Positioned(
              top: -nodeHalf,
              left: half - nodeHalf,
              child: _FloatingNode(
                offset: const Offset(0, -6),
                child: RadialNode(
                  size: nodeSize,
                  color: aoColor,
                  pct: g.aoPct,
                  pinAngle: _pinAngleFromOffset(nodeSize, 78, 13),
                  child: _NodeContent(
                    topLabel: 'AO',
                    bigValue: g.ao.toStringAsFixed(4),
                    bigColor: aoColor,
                  ),
                ),
              ),
            ),

            // ── STOCH node — RIGHT ──
            Positioned(
              top: half - nodeHalf,
              right: -nodeHalf,
              child: _FloatingNode(
                offset: const Offset(6, 0),
                child: RadialNode(
                  size: nodeSize,
                  color: stochColor,
                  pct: stochK,
                  pinAngle: _pinAngleFromOffset(nodeSize, 76, 76),
                  child: _NodeContent(
                    topLabel: 'STOCH',
                    bigValue: '${stochK.round()}%',
                    bigColor: stochColor,
                    smallValue: '${math.max(0, stochK.round() - 10)} left',
                  ),
                ),
              ),
            ),

            // ── AC node — BOTTOM ──
            Positioned(
              bottom: -nodeHalf,
              left: half - nodeHalf,
              child: _FloatingNode(
                offset: const Offset(0, 6),
                child: RadialNode(
                  size: nodeSize,
                  color: acColor,
                  pct: g.acPct,
                  pinAngle: _pinAngleFromOffset(nodeSize, 12, 76),
                  child: _NodeContent(
                    topLabel: 'AC',
                    bigValue: g.ac.toStringAsFixed(4),
                    bigColor: acColor,
                  ),
                ),
              ),
            ),

            // ── MOMENTUM node — LEFT ──
            Positioned(
              top: half - nodeHalf,
              left: -nodeHalf,
              child: _FloatingNode(
                offset: const Offset(-6, 0),
                child: RadialNode(
                  size: nodeSize,
                  color: mmmColor,
                  pct: g.mmmPct,
                  pinAngle: _pinAngleFromOffset(nodeSize, 12, 13),
                  child: _NodeContent(
                    topLabel: 'MOMENTUM',
                    bigValue: '${g.mmmPct.round()}%',
                    bigColor: mmmColor,
                    smallValue: g.mmmBearish ? 'BEARISH' : 'BULLISH',
                    smallColor: mmmColor,
                  ),
                ),
              ),
            ),

            // ── Central score ──
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: popAnim,
                    child: Text(
                      g.score == -1 ? '—' : '${g.score}',
                      style: TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                        color: g.score >= 75
                            ? const Color(0xFFFF4A4A)
                            : AppColors.text,
                      ),
                    ),
                  ),
                  const Text(
                    '/ 100',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Convert absolute pin coordinates (px within nodeSize) to an angle in radians
  // so RadialNode can place the dot on the ring arc.
  double _pinAngleFromOffset(double ns, double py, double px) {
    final cx = ns / 2, cy = ns / 2;
    return math.atan2(py - cy, px - cx);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating node: continuously oscillates in one axis
// ─────────────────────────────────────────────────────────────────────────────
class _FloatingNode extends StatefulWidget {
  final Widget child;
  final Offset offset; // max displacement
  const _FloatingNode({required this.child, required this.offset});

  @override
  State<_FloatingNode> createState() => _FloatingNodeState();
}

class _FloatingNodeState extends State<_FloatingNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4000))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: widget.offset * _anim.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Node inner content layout
// ─────────────────────────────────────────────────────────────────────────────
class _NodeContent extends StatelessWidget {
  final String topLabel;
  final String bigValue;
  final Color bigColor;
  final String? smallValue;
  final Color? smallColor;

  const _NodeContent({
    required this.topLabel,
    required this.bigValue,
    required this.bigColor,
    this.smallValue,
    this.smallColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(topLabel,
            style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: -0.2)),
        const SizedBox(height: 1),
        Text(bigValue,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: bigColor,
                letterSpacing: -0.3)),
        if (smallValue != null)
          Text(smallValue!,
              style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: smallColor ?? AppColors.textMuted)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal card at the bottom of the main area
// ─────────────────────────────────────────────────────────────────────────────
class _SignalCard extends StatelessWidget {
  final GardenResult garden;
  const _SignalCard({required this.garden});

  @override
  Widget build(BuildContext context) {
    final g = garden;
    final isSell = g.signal == 'SELL';

    final pillBg = isSell
        ? const Color(0xFFFFF0F0)
        : const Color(0xFFEEFDF1);
    final pillBorder = isSell
        ? const Color(0xFFFFCDD2)
        : const Color(0xFFD2FCDA);
    final pillColor = isSell
        ? const Color(0xFFFF4A4A)
        : const Color(0xFF42F25B);

    final arrowBorder = isSell
        ? const Color(0xFFFEE2E2)
        : const Color(0xFFEAFEEF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: 84,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: isSell
                  ? const Color(0xFFFF4A4A).withValues(alpha: 0.20)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: arrow circle + rate pill + status pill
              Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: arrowBorder, width: 2),
                    color: Colors.white,
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: isSell ? (math.pi * 3 / 4) : (math.pi / 4),
                      child: Transform.translate(
                        offset: const Offset(1, 1),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CustomPaint(
                            painter: _ArrowPainter(
                              color: isSell
                                  ? const Color(0xFFFF4A4A)
                                  : const Color(0xFF42F25B),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: pillBg,
                    border: Border.all(color: pillBorder),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${g.score}%',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: pillColor),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F5F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isSell ? 'Valid Setup' : 'Monitoring',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6A6A6A)),
                  ),
                ),
              ]),

              // Right: heading + sub
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isSell ? 'Bearish Signal' : 'No Signal',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                        height: 1.1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSell
                        ? (g.score >= 75
                            ? 'High Probability'
                            : 'Moderate Setup')
                        : 'Waiting for confluence',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Arrow chevron painter (top-left corner only, rotated to direction)
// ─────────────────────────────────────────────────────────────────────────────
class _ArrowPainter extends CustomPainter {
  final Color color;
  const _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    // left arm
    canvas.drawLine(Offset(0, size.height), const Offset(0, 0), paint);
    // top arm
    canvas.drawLine(const Offset(0, 0), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color;
}
