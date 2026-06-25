import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Radial gauge showing a rolling z-score clamped to [-3, 3].
class WelfordMeter extends StatelessWidget {
  final double z;
  final double size;
  const WelfordMeter({super.key, required this.z, this.size = 110});

  @override
  Widget build(BuildContext context) {
    final clamped = z.clamp(-3.0, 3.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MeterPainter(clamped.toDouble()),
        child: Center(
          child: Text(
            z.toStringAsFixed(2),
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

class _MeterPainter extends CustomPainter {
  final double z; // -3..3
  _MeterPainter(this.z);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    final track = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, track);

    final t = (z + 3) / 6; // 0..1
    final fillSweep = sweepAngle * t;
    final fill = Paint()
      ..color = z.abs() > 2 ? AppColors.red : AppColors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, fillSweep, false, fill);

    // needle
    final angle = startAngle + fillSweep;
    final needleEnd = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 12);
    final needlePaint = Paint()
      ..color = AppColors.red
      ..strokeWidth = 2;
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, 3, Paint()..color = AppColors.red);
  }

  @override
  bool shouldRepaint(covariant _MeterPainter oldDelegate) => oldDelegate.z != z;
}
