import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Radial dial showing how many candles have formed since the last spike,
/// against a soft target ring of ~20 candles.
class SequenceDial extends StatelessWidget {
  final int count;
  final double size;
  const SequenceDial({super.key, required this.count, this.size = 110});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DialPainter(count),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$count',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.text)),
              const Text('CANDLES', style: TextStyle(fontSize: 8, color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final int count;
  _DialPainter(this.count);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    const startAngle = -math.pi / 2;
    const target = 20.0;
    final t = (count / target).clamp(0.0, 1.0);

    final track = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, math.pi * 2, false, track);

    final color = count > target ? AppColors.red : AppColors.black;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, math.pi * 2 * t, false, fill);
  }

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) => oldDelegate.count != count;
}
