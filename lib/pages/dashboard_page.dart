import 'dart:async';
import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
import '../services/garden_calc.dart';
import '../services/indicators.dart';
import '../theme.dart';
import 'indicators_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DashboardPage
// All assets × all timeframes in one scannable grid — see every instrument's
// current signal and score at a glance instead of paging through each one.
// Tap a cell to jump straight into that asset/timeframe's indicator engines.
// ─────────────────────────────────────────────────────────────────────────────

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: const Text('Multi-Asset Dashboard',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: kGranularities.keys.map((tf) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(tf.toUpperCase(),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900,
                          letterSpacing: 1.4, color: AppColors.red)),
                ),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8, crossAxisSpacing: 8,
                  childAspectRatio: 2.5,
                  children: kAssets.map((asset) =>
                      _DashboardCell(asset: asset, tf: tf)).toList(),
                ),
              ]),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DashboardCell extends StatefulWidget {
  final String asset;
  final String tf;
  const _DashboardCell({required this.asset, required this.tf});

  @override
  State<_DashboardCell> createState() => _DashboardCellState();
}

class _DashboardCellState extends State<_DashboardCell> {
  final GardenState _gardenState = GardenState();
  StreamSubscription<List<Candle>>? _sub;
  GardenResult? _g;

  @override
  void initState() {
    super.initState();
    final symbol = assetSymbol[widget.asset]!;
    final initial = DerivFeed.instance.current(symbol, widget.tf);
    if (initial.isNotEmpty) _g = _gardenState.compute(initial, widget.asset);
    _sub = DerivFeed.instance.stream(symbol, widget.tf).listen((candles) {
      if (!mounted) return;
      setState(() => _g = _gardenState.compute(candles, widget.asset));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color get _statusColor {
    final g = _g;
    if (g == null || !g.armed) return AppColors.textMuted;
    return g.signal == 'BUY' ? const Color(0xFF27AE60) : AppColors.red;
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => IndicatorsPage(asset: widget.asset, tf: widget.tf))),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: g != null && g.armed
                  ? _statusColor.withValues(alpha: 0.5)
                  : AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(shortAssetLabel(widget.asset),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                    color: AppColors.text),
                overflow: TextOverflow.ellipsis),
          ),
          if (g == null)
            const Text('…', style: TextStyle(color: AppColors.textMuted, fontSize: 11))
          else ...[
            Text('${g.score}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900,
                    fontFamily: 'monospace', color: _statusColor)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                !g.armed ? 'WAIT' : g.signal,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800,
                    letterSpacing: 0.4, color: _statusColor),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
