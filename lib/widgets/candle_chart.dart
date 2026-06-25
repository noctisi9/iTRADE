import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../theme.dart';

class CandleChart extends StatefulWidget {
  final List<Candle> candles;
  const CandleChart({super.key, required this.candles});

  @override
  State<CandleChart> createState() => _CandleChartState();
}

class _CandleChartState extends State<CandleChart> {
  double _viewW = 30;
  double _offset = 0; // candles back from the live (right) edge
  double _startViewW = 30;
  double _startOffset = 0;
  Offset _startFocal = Offset.zero;
  double _lastWidth = 300;

  @override
  void didUpdateWidget(covariant CandleChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Snap back to the live edge whenever a brand new candle set length
    // appears and the user isn't actively panned away from live.
    if (widget.candles.length > oldWidget.candles.length && _offset == 0) {
      // already at live edge, nothing to do — new candle just shows.
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startViewW = _viewW;
    _startOffset = _offset;
    _startFocal = d.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      final maxView = widget.candles.isEmpty ? 60.0 : widget.candles.length.toDouble();
      if ((d.scale - 1.0).abs() > 0.01) {
        _viewW = (_startViewW / d.scale).clamp(8.0, maxView);
      }
      final dx = d.focalPoint.dx - _startFocal.dx;
      final slotW = _lastWidth / _viewW;
      final candleDelta = (dx / slotW).round();
      final maxOff = math.max(0.0, widget.candles.length - _viewW);
      _offset = (_startOffset + candleDelta).clamp(0.0, maxOff);
    });
  }

  void _resetZoom() {
    setState(() {
      _viewW = 30;
      _offset = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _lastWidth = constraints.maxWidth;
      return GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onDoubleTap: _resetZoom,
        child: Container(
          color: AppColors.card,
          width: double.infinity,
          height: double.infinity,
          child: CustomPaint(
            painter: _CandlePainter(
              candles: widget.candles,
              viewW: _viewW,
              offset: _offset,
            ),
            size: Size.infinite,
          ),
        ),
      );
    });
  }
}

class _CandlePainter extends CustomPainter {
  final List<Candle> candles;
  final double viewW;
  final double offset;
  _CandlePainter({required this.candles, required this.viewW, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.width <= 0 || size.height <= 0) return;

    final slots = viewW.round().clamp(1, candles.length);
    final end = (candles.length - offset.round()).clamp(0, candles.length);
    final start = (end - slots).clamp(0, candles.length);
    final visible = candles.sublist(start, end);
    if (visible.isEmpty) return;

    const padL = 6.0, padR = 54.0, padT = 10.0, padB = 10.0;
    final innerW = math.max(1.0, size.width - padL - padR);
    final innerH = math.max(1.0, size.height - padT - padB);
    final slotW = innerW / visible.length;

    final minV = visible.map((c) => c.l).reduce(math.min);
    final maxV = visible.map((c) => c.h).reduce(math.max);
    final range = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    double toY(double v) => padT + (1 - (v - minV) / range) * innerH;

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    const labelStyle = TextStyle(fontSize: 9, color: AppColors.textDim);

    for (var i = 0; i < 5; i++) {
      final t = i / 4;
      final y = padT + t * innerH;
      final v = maxV - t * range;
      _dashedLine(canvas, Offset(padL, y), Offset(size.width - padR, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: v.toStringAsFixed(3), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - padR + 4, y - 5));
    }

    for (var i = 0; i < visible.length; i++) {
      final c = visible[i];
      final x = padL + i * slotW + slotW / 2;
      final bodyTop = toY(math.max(c.o, c.c));
      final bodyBot = toY(math.min(c.o, c.c));
      final bodyH = math.max(1.5, bodyBot - bodyTop);
      final up = c.c >= c.o;
      final color = up ? AppColors.black : AppColors.red;
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = math.max(1.0, slotW * 0.12);
      canvas.drawLine(Offset(x, toY(c.h)), Offset(x, toY(c.l)), wickPaint);
      final bodyPaint = Paint()..color = color;
      final bodyW = math.max(1.5, slotW * 0.7);
      canvas.drawRect(Rect.fromLTWH(x - bodyW / 2, bodyTop, bodyW, bodyH), bodyPaint);
      if (c.spike) {
        final ring = Paint()
          ..color = AppColors.redGlow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset(x, toY(c.h) - 6), 3, ring);
      }
    }

    final last = visible.last;
    final y = toY(last.c);
    final linePaint = Paint()
      ..color = AppColors.red
      ..strokeWidth = 1;
    _dashedLine(canvas, Offset(padL, y), Offset(size.width - padR, y), linePaint);
    final boxPaint = Paint()..color = AppColors.red;
    canvas.drawRect(Rect.fromLTWH(size.width - padR + 2, y - 7, padR - 4, 14), boxPaint);
    final priceTp = TextPainter(
      text: TextSpan(
        text: last.c.toStringAsFixed(3),
        style: const TextStyle(
            fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    priceTp.paint(canvas, Offset(size.width - padR + 4, y - 5));
  }

  void _dashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 3.0, dashSpace = 3.0;
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
  bool shouldRepaint(covariant _CandlePainter oldDelegate) =>
      oldDelegate.candles != candles || oldDelegate.viewW != viewW || oldDelegate.offset != offset;
}
