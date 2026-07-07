import 'package:flutter/material.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ConfluenceBar
// Visual 0/3 → 3/3 strip showing how many of AO/AC/Stoch currently agree
// on direction. Experts scan this at a glance without reading the score.
// ─────────────────────────────────────────────────────────────────────────────

class ConfluenceBar extends StatelessWidget {
  final int    count;   // 0-3
  final String dir;     // 'BULLISH' | 'BEARISH' | 'MIXED'

  const ConfluenceBar({super.key, required this.count, required this.dir});

  Color get _color => dir == 'BULLISH'
      ? const Color(0xFF27AE60)
      : dir == 'BEARISH'
          ? AppColors.red
          : AppColors.textMuted;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ...List.generate(3, (i) {
        final filled = i < count;
        return Container(
          width: 16, height: 6,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: filled ? _color : AppColors.border,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
      const SizedBox(width: 6),
      Text('$count/3',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
              fontFamily: 'monospace', color: _color)),
    ]);
  }
}
