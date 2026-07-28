import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RadialNode
// White circle with:
//   · track ring (light grey)
//   · active arc (colored, fills by pct 0-100)
//   · pulsing ambient glow via boxShadow
//   · a small pin dot placed at pinAngle on the ring
//   · arbitrary child widget centred inside
// ─────────────────────────────────────────────────────────────────────────────

class RadialNode extends StatefulWidget {
  final double size;
  final Color color;
  final double pct;       // 0-100
  final double pinAngle;  // radians — where on the ring the pin sits
  final Widget child;

  const RadialNode({
    super.key,
    required this.size,
    required this.color,
    required this.pct,
    required this.pinAngle,
    required this.child,
  });

  @override
  State<RadialNode> createState() => _RadialNodeState();
}

class _RadialNodeState extends State<RadialNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (_, __) {
        final glowOpacity = 0.08 + _glowCtrl.value * 0.10;
        final blurRadius  = 18.0 + _glowCtrl.value * 6.0;

        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glowOpacity),
                blurRadius: blurRadius,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ring (track + active arc + pin)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RingPainter(
                    color: widget.color,
                    pct: widget.pct.clamp(0, 100).toDouble(),
                    pinAngle: widget.pinAngle,
                  ),
                ),
              ),
              // Content
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ring + pin painter
// ─────────────────────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final Color color;
  final double pct;
  final double pinAngle;

  _RingPainter({
    required this.color,
    required this.pct,
    required this.pinAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const startAngle = -math.pi / 2; // 12 o'clock
    const fullSweep  = 2 * math.pi;

    // ── Track ──
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      fullSweep,
      false,
      Paint()
        ..color = const Color(0xFFF4F4F4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );

    // ── Active arc ──
    if (pct > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        fullSweep * (pct / 100),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── Pin dot ──
    final pinX = center.dx + radius * math.cos(pinAngle);
    final pinY = center.dy + radius * math.sin(pinAngle);

    canvas.drawCircle(
      Offset(pinX, pinY),
      5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(pinX, pinY),
      5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.color != color || old.pct != pct || old.pinAngle != pinAngle;
}
