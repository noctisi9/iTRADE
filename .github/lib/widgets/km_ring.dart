import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Ring showing spike probability (1 - survival) as a percentage fill.
class KmRing extends StatelessWidget {
  final double spikeProb; // 0..1
  final double size;
  const KmRing({super.key, required this.spikeProb, this.size = 110});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(spikeProb),
        child: Center(
          child: Text(
            '${(spikeProb * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double p;
  _RingPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const startAngle = -math.pi / 2;

    final track = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, math.pi * 2, false, track);

    final fill = Paint()
      ..color = p > 0.7 ? AppColors.red : AppColors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, math.pi * 2 * p.clamp(0, 1), false, fill);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.p != p;
}
