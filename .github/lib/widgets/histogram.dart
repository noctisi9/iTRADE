import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme.dart';

class Histogram extends StatelessWidget {
  final List<double> values;
  final double height;
  const Histogram({super.key, required this.values, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _HistPainter(values)),
    );
  }
}

class _HistPainter extends CustomPainter {
  final List<double> values;
  _HistPainter(this.values);

  void _dashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 4.0, dashSpace = 3.0;
    final total = (p2 - p1).distance;
    if (total <= 0) return;
    final dir = (p2 - p1) / total;
    double drawn = 0;
    while (drawn < total) {
      final segEnd = math.min(drawn + dashWidth, total);
      canvas.drawLine(p1 + dir * drawn, p1 + dir * segEnd, paint);
      drawn += dashWidth + dashSpace;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final finite = values.where((v) => v.isFinite).toList();
    if (finite.isEmpty) return;
    final tail = finite.length > 40 ? finite.sublist(finite.length - 40) : finite;
    final maxAbs = tail.map((v) => v.abs()).fold(0.0, math.max);
    final scale = maxAbs == 0 ? 1.0 : maxAbs;
    final midY = size.height / 2;
    final slotW = size.width / tail.length;

    final zeroPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    _dashedLine(canvas, Offset(0, midY), Offset(size.width, midY), zeroPaint);

    for (var i = 0; i < tail.length; i++) {
      final v = tail[i];
      final h = (v.abs() / scale) * (size.height / 2 - 2);
      final x = i * slotW + slotW * 0.15;
      final w = slotW * 0.7;
      final risingColor = i > 0 && v >= tail[i - 1] ? AppColors.black : AppColors.red;
      final paint = Paint()..color = v >= 0 ? AppColors.black : risingColor;
      final rect = v >= 0
          ? Rect.fromLTWH(x, midY - h, w, h)
          : Rect.fromLTWH(x, midY, w, h);
      canvas.drawRect(rect, paint..color = v >= 0 ? AppColors.black : AppColors.red);
    }
  }

  @override
  bool shouldRepaint(covariant _HistPainter oldDelegate) => oldDelegate.values != values;
}
