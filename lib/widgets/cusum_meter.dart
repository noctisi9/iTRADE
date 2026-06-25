import 'package:flutter/material.dart';
import '../theme.dart';

class CusumMeter extends StatelessWidget {
  final List<double> wave;
  final double threshold;
  final bool alert;
  final double height;
  const CusumMeter({
    super.key,
    required this.wave,
    required this.threshold,
    required this.alert,
    this.height = 70,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _CusumPainter(wave, threshold, alert)),
    );
  }
}

class _CusumPainter extends CustomPainter {
  final List<double> wave;
  final double threshold;
  final bool alert;
  _CusumPainter(this.wave, this.threshold, this.alert);

  @override
  void paint(Canvas canvas, Size size) {
    if (wave.isEmpty) return;
    final tail = wave.length > 40 ? wave.sublist(wave.length - 40) : wave;
    final maxV = [...tail, threshold].reduce((a, b) => a > b ? a : b);
    final scale = maxV == 0 ? 1.0 : maxV;
    final stepX = size.width / (tail.length - 1).clamp(1, double.infinity);

    final thresholdY = size.height - (threshold / scale) * (size.height - 8);
    final thresholdPaint = Paint()
      ..color = AppColors.redFaint
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, thresholdY), Offset(size.width, thresholdY), thresholdPaint);

    final path = Path();
    for (var i = 0; i < tail.length; i++) {
      final x = i * stepX;
      final y = size.height - (tail[i] / scale) * (size.height - 8);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final linePaint = Paint()
      ..color = alert ? AppColors.red : AppColors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _CusumPainter oldDelegate) =>
      oldDelegate.wave != wave || oldDelegate.alert != alert;
}
