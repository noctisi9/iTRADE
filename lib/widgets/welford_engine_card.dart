import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Engine 3 (BOOM/CRASH): horizontal z-score rail + sparkline + readout,
/// all inside one wide rounded card per the design spec.
class WelfordEngineCard extends StatelessWidget {
  final double z; // current rolling z-score
  final List<double> series; // recent z-score history, oldest -> newest

  const WelfordEngineCard({super.key, required this.z, required this.series});

  bool get _isOutlier => z.abs() > 2;

  @override
  Widget build(BuildContext context) {
    final tail = series.length > 32 ? series.sublist(series.length - 32) : series;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: _isOutlier ? AppColors.borderBright : AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ENGINE 3',
                  style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: AppColors.red,
                      letterSpacing: 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isOutlier ? AppColors.red : Colors.transparent,
                  border: Border.all(color: AppColors.red),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isOutlier ? '● OUTLIER' : 'STABLE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: _isOutlier ? Colors.white : AppColors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(height: 36, width: double.infinity, child: CustomPaint(painter: _ZTrackPainter(z))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('-3', style: TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace')),
                Text('0', style: TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace')),
                Text('+3', style: TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SizedBox(height: 28, child: CustomPaint(painter: _SparklinePainter(tail))),
              ),
              const SizedBox(width: 12),
              Text(
                '${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: _isOutlier ? AppColors.red : AppColors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZTrackPainter extends CustomPainter {
  final double z;
  _ZTrackPainter(this.z);

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final railPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2;

    // danger zones: outer 1/6 of the track on each side (~±2..3 sigma)
    final dangerW = size.width / 6;
    final dangerPaint = Paint()..color = AppColors.redFaint;
    canvas.drawRect(Rect.fromLTWH(0, midY - 6, dangerW, 12), dangerPaint);
    canvas.drawRect(Rect.fromLTWH(size.width - dangerW, midY - 6, dangerW, 12), dangerPaint);

    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), railPaint);

    // center tick
    final tickPaint = Paint()
      ..color = AppColors.textMuted
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(size.width / 2, midY - 8), Offset(size.width / 2, midY + 8), tickPaint);

    // moving dot
    final clamped = z.clamp(-3.0, 3.0);
    final t = (clamped + 3) / 6;
    final dotX = t * size.width;
    final outlier = z.abs() > 2;
    if (outlier) {
      canvas.drawCircle(Offset(dotX, midY), 14, Paint()..color = AppColors.redFaint);
    }
    canvas.drawCircle(
      Offset(dotX, midY),
      12,
      Paint()..color = outlier ? AppColors.red : AppColors.black,
    );
  }

  @override
  bool shouldRepaint(covariant _ZTrackPainter oldDelegate) => oldDelegate.z != z;
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  _SparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxAbs = values.map((v) => v.abs()).fold(0.0, math.max);
    final scale = maxAbs == 0 ? 1.0 : maxAbs;
    final midY = size.height / 2;
    final stepX = size.width / (values.length - 1);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * stepX;
      final y = midY - (values[i] / scale) * (size.height / 2 - 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.textDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) => oldDelegate.values != values;
}
