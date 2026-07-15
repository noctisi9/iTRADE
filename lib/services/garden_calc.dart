import 'dart:math' as math;
import '../models/candle.dart';
import 'indicators.dart';

// ─────────────────────────────────────────────────────────────────────────────
// garden_calc.dart — production engine v4
//
// Stoch(25, 5, 8)
//   Raw %K   = (Close − LowestLow_25) / (HighestHigh_25 − LowestLow_25) × 100
//   Slowed K = SMA(rawK, 5)
//   %D       = SMA(slowedK, 8)
//
// AO = SMA(hl2, 5) − SMA(hl2, 34)
// AC = AO − SMA(AO, 5)
//
// Signal conditions:
//   BOOM SELL: AO<0 AND AC<0 AND stochK<20 AND stochDescending
//   CRASH BUY: AO>0 AND AC>0 AND stochK>80 AND stochAscending
//
// Score: purely from indicator alignment (0–100)
//   stochScore = distance from 50, 0–50 pts
//   aoScore    = 25 if AO in correct direction
//   acScore    = 25 if AC in correct direction
//
// Risk meaning: LOW risk = conditions fully met (overbought/oversold + aligned)
//               HIGH risk = waiting for alignment (conditions not met = higher
//               uncertainty). Score 100 = fully aligned = lowest risk trade.
// ─────────────────────────────────────────────────────────────────────────────

enum AssetType { boom, crash }

AssetType assetType(String asset) {
  if (asset.startsWith('BOOM')) return AssetType.boom;
  return AssetType.crash;
}

class GardenResult {
  final double ao;
  final bool   aoRising;
  final double aoPct;

  final double ac;
  final bool   acRising;
  final double acPct;

  final double stochK;
  final double stochD;
  final bool   stochDescending;
  final bool   stochAscending;
  final String stochLabel;     // 'OVERBOUGHT' | 'OVERSOLD' | 'NEUTRAL'
  // Stochastic direction context for display
  final String stochTrend;     // 'RISING ▲' | 'FALLING ▼' | 'FLAT'

  final int    score;
  final String signal;
  final String dirLabel;
  final bool   armed;

  final int    candlesSinceSpike;

  const GardenResult({
    required this.ao,
    required this.aoRising,
    required this.aoPct,
    required this.ac,
    required this.acRising,
    required this.acPct,
    required this.stochK,
    required this.stochD,
    required this.stochDescending,
    required this.stochAscending,
    required this.stochLabel,
    required this.stochTrend,
    required this.score,
    required this.signal,
    required this.dirLabel,
    required this.armed,
    required this.candlesSinceSpike,
  });
}

class GardenState {
  final List<double> _aoH    = [];
  final List<double> _acH    = [];
  final List<double> _slowKH = [];
  double? _prevStochK;

  GardenResult? compute(List<Candle> candles, String asset) {
    // Need minimum 40 candles for stable SMA(34)
    if (candles.length < 40) return null;
    final type = assetType(asset);

    // ── AO ───────────────────────────────────────────────────────────────────
    final aoSeries = calcAO(candles);
    if (aoSeries.isEmpty) return null;
    final aoRaw = aoSeries.last;
    if (!aoRaw.isFinite) return null;
    final ao = _r4(aoRaw);
    final aoRising = _aoH.isNotEmpty && ao > _aoH.last;
    _push(_aoH, ao);

    // ── AC ───────────────────────────────────────────────────────────────────
    final acSeries = calcAC(aoSeries);
    if (acSeries.isEmpty) return null;
    final acRaw = acSeries.last;
    if (!acRaw.isFinite) return null;
    final ac = _r4(acRaw);
    final acRising = _acH.isNotEmpty && ac > _acH.last;
    _push(_acH, ac);

    // ── Stoch(25, 5, 8) ───────────────────────────────────────────────────────
    final stochRaw = _calcStochK(candles);
    if (stochRaw == null) return null;
    _push(_slowKH, stochRaw);

    // D requires 8 slowed-K values. If we don't have 8 yet, use stochRaw as D.
    // This prevents the engine from returning null during warm-up, but keeps
    // signal conditions accurate (descending/ascending won't fire prematurely
    // because K≈D when D is estimated).
    final stochK = stochRaw;
    final stochD = _slowKH.length >= 8
        ? _smaLast(_slowKH, 8)!
        : stochRaw; // fallback to K itself → no false K<D or K>D

    final stochDescending = stochK < stochD - 0.5; // 0.5 hysteresis to avoid noise
    final stochAscending  = stochK > stochD + 0.5;

    final stochLabel = stochK > 80 ? 'OVERBOUGHT'
        : stochK < 20             ? 'OVERSOLD'
        :                           'NEUTRAL';

    // Stoch trend vs previous K
    final String stochTrend;
    if (_prevStochK == null) {
      stochTrend = 'FLAT';
    } else if (stochK > _prevStochK! + 0.3) {
      stochTrend = 'RISING ▲';
    } else if (stochK < _prevStochK! - 0.3) {
      stochTrend = 'FALLING ▼';
    } else {
      stochTrend = 'FLAT';
    }
    _prevStochK = stochK;

    // ── Ring fill percentages ─────────────────────────────────────────────────
    final aoPct = _distPct(ao, _aoH);
    final acPct = _distPct(ac, _acH);

    // Relaxed safe guard — require at least a tiny move (2% of recent range)
    // Removes false blocking during first few candles of a new session
    final safe = aoPct > 2 && acPct > 2;

    // ── Score ─────────────────────────────────────────────────────────────────
    // Score = how aligned all indicators are toward a valid trade.
    // Score 100 = fully aligned = low-risk high-confidence trade.
    // Score 0   = no alignment  = do not trade.
    //
    // For BOOM (SELL setup): AO<0, AC<0, Stoch oversold and descending
    // For CRASH (BUY setup): AO>0, AC>0, Stoch overbought and ascending
    final stochScore = (stochK - 50).abs() / 50 * 50; // 0–50

    final isBearish = type == AssetType.boom;  // BOOM wants bearish
    final isBullish = type == AssetType.crash; // CRASH wants bullish

    final aoScore = (isBearish && ao < 0) || (isBullish && ao > 0) ? 25.0 : 0.0;
    final acScore = (isBearish && ac < 0) || (isBullish && ac > 0) ? 25.0 : 0.0;

    final score = (stochScore + aoScore + acScore).round().clamp(0, 100);

    // ── Signal ────────────────────────────────────────────────────────────────
    final String signal;
    switch (type) {
      case AssetType.boom:
        signal = (ao < 0 && ac < 0 && safe && stochK < 20 && stochDescending)
            ? 'SELL' : 'WAIT';
      case AssetType.crash:
        signal = (ao > 0 && ac > 0 && safe && stochK > 80 && stochAscending)
            ? 'BUY' : 'WAIT';
    }

    final armed    = signal != 'WAIT';
    final dirLabel = signal == 'SELL' ? 'SELL · SIGNAL'
        : signal == 'BUY' ? 'BUY · SIGNAL'
        : 'SCANNING…';

    final candlesSinceSpike = calcSpikeStats(candles)?.sequenceCount ?? 0;

    return GardenResult(
      ao: ao, aoRising: aoRising, aoPct: aoPct,
      ac: ac, acRising: acRising, acPct: acPct,
      stochK: stochK, stochD: stochD,
      stochDescending: stochDescending, stochAscending: stochAscending,
      stochLabel: stochLabel, stochTrend: stochTrend,
      score: score,
      signal: signal, dirLabel: dirLabel, armed: armed,
      candlesSinceSpike: candlesSinceSpike,
    );
  }

  // ── Stoch(25, slowing=5) — returns slowed K ───────────────────────────────
  double? _calcStochK(List<Candle> candles) {
    const kPeriod = 25, slowing = 5;
    const need = kPeriod + slowing - 1;
    if (candles.length < need) return null;
    final slice = candles.sublist(candles.length - need);
    final rawKs = <double>[];
    for (var i = kPeriod - 1; i < slice.length; i++) {
      final w  = slice.sublist(i - kPeriod + 1, i + 1);
      final hi = w.map((c) => c.h).reduce(math.max);
      final lo = w.map((c) => c.l).reduce(math.min);
      rawKs.add(hi == lo ? 50.0 : ((slice[i].c - lo) / (hi - lo)) * 100.0);
    }
    if (rawKs.length < slowing) return null;
    return rawKs.sublist(rawKs.length - slowing)
        .fold(0.0, (a, b) => a + b) / slowing;
  }

  void _push(List<double> list, double val) {
    list.add(val);
    if (list.length > 500) list.removeAt(0);
  }

  double _distPct(double val, List<double> hist) {
    if (hist.length < 2) return 0;
    final mx = hist.map((v) => v.abs()).fold(0.0, math.max);
    return mx == 0 ? 0 : math.min(100.0, val.abs() / mx * 100.0);
  }

  double? _smaLast(List<double> vals, int n) {
    if (vals.length < n) return null;
    return vals.sublist(vals.length - n).fold(0.0, (a, b) => a + b) / n;
  }

  double _r4(double v) => double.parse(v.toStringAsFixed(4));
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary line for signals page chart
// ─────────────────────────────────────────────────────────────────────────────
String buildSummaryLine(GardenResult g, String asset) {
  final type   = assetType(asset);
  final spikes = '${g.candlesSinceSpike} candles since spike';
  final risk   = 'Score ${g.score}/100';
  final sig    = g.armed ? ' · ${g.signal}' : '';
  return '$spikes  ·  $risk$sig';
}
