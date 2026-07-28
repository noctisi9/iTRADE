import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../services/indicators.dart';
import '../theme.dart';

const List<double> _fibRatios = [0, 0.25, 0.5, 0.75, 1];

class FibEngine extends StatelessWidget {
  final List<Candle> candles;
  const FibEngine({super.key, required this.candles});

  @override
  Widget build(BuildContext context) {
    if (candles.length < 35) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('Waiting for data…', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
      );
    }

    final window = candles.length > 60 ? candles.sublist(candles.length - 60) : candles;
    final high = window.map((c) => c.h).reduce((a, b) => a > b ? a : b);
    final low = window.map((c) => c.l).reduce((a, b) => a < b ? a : b);
    final range = (high - low) == 0 ? 1.0 : (high - low);
    final last = window.last.c;
    final pricePct = ((high - last) / range * 100).clamp(0, 100);

    // which fib level is current price nearest to (as a fraction 0..1 from the top)
    final nearestIdx = _fibRatios
        .asMap()
        .entries
        .reduce((a, b) =>
            (((pricePct / 100) - a.value).abs() < ((pricePct / 100) - b.value).abs()) ? a : b)
        .key;
    final lit = nearestIdx == 2 || nearestIdx == 3; // 50% or 75% line
    final targetLabel = nearestIdx <= 2 ? '50' : '75';

    final ao = calcAO(candles);
    final ac = calcAC(ao);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: lit ? AppColors.borderBright : AppColors.border),
        borderRadius: BorderRadius.circular(16),
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
                  color: lit ? AppColors.red : Colors.transparent,
                  border: Border.all(color: AppColors.red),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'FIB 25/50/75/100',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: lit ? Colors.white : AppColors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(painter: _FibPainter(window: window, ao: ao, ac: ac)),
          ),
          const SizedBox(height: 8),
          Text(
            'price at ${pricePct.toStringAsFixed(1)}%  ·  target FIB $targetLabel',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textDim),
          ),
        ],
      ),
    );
  }
}

class _FibPainter extends CustomPainter {
  final List<Candle> window;
  final List<double> ao;
  final List<double> ac;
  _FibPainter({required this.window, required this.ao, required this.ac});

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
    final high = window.map((c) => c.h).reduce((a, b) => a > b ? a : b);
    final low = window.map((c) => c.l).reduce((a, b) => a < b ? a : b);
    final range = (high - low) == 0 ? 1.0 : (high - low);
    double toY(double v) => (1 - (v - low) / range) * size.height;

    final dashedPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (final r in _fibRatios) {
      final y = toY(low + range * (1 - r));
      _dashedLine(canvas, Offset(0, y), Offset(size.width, y), dashedPaint);
    }

    // price polyline (red)
    final stepX = size.width / (window.length - 1).clamp(1, double.infinity);
    final pricePath = Path();
    for (var i = 0; i < window.length; i++) {
      final x = i * stepX;
      final y = toY(window[i].c);
      if (i == 0) {
        pricePath.moveTo(x, y);
      } else {
        pricePath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      pricePath,
      Paint()
        ..color = AppColors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // AO/AC overlays, rescaled into the same visible band purely for visual reference
    void drawOverlay(List<double> series, Paint paint, {bool dashed = false}) {
      final tail = series.length >= window.length
          ? series.sublist(series.length - window.length)
          : series;
      final finite = tail.where((v) => v.isFinite).toList();
      if (finite.isEmpty) return;
      final maxAbs = finite.map((v) => v.abs()).fold(0.0, math.max);
      final scale = maxAbs == 0 ? 1.0 : maxAbs;
      Offset? prev;
      for (var i = 0; i < tail.length; i++) {
        final v = tail[i].isFinite ? tail[i] : 0.0;
        final x = i * stepX;
        final norm = (v / scale); // -1..1
        final y = size.height / 2 - norm * (size.height / 2 - 6);
        final cur = Offset(x, y);
        if (prev != null) {
          if (dashed) {
            _dashedLine(canvas, prev, cur, paint);
          } else {
            canvas.drawLine(prev, cur, paint);
          }
        }
        prev = cur;
      }
    }

    drawOverlay(ao, Paint()
      ..color = AppColors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    drawOverlay(
        ac,
        Paint()
          ..color = AppColors.red.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
        dashed: true);
  }

  @override
  bool shouldRepaint(covariant _FibPainter oldDelegate) => true;
}
