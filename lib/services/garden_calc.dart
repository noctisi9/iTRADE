import 'dart:math' as math;
import '../models/candle.dart';
import 'indicators.dart';

// ─────────────────────────────────────────────────────────────────────────────
// garden_calc.dart — production engine built from MT5 screenshots
//
// Stoch(25, 5, 8)  — K period=25, slowing=5, D period=8
//   Raw %K   = (Close − LowestLow_25) / (HighestHigh_25 − LowestLow_25) × 100
//   Slowed K = SMA(rawK, 5)      ← the %K line shown on MT5
//   %D       = SMA(slowedK, 8)   ← the signal line shown on MT5
//
// AO = SMA(hl2, 5) − SMA(hl2, 34)
//   Bar rising  (AO > prev AO) = orange
//   Bar falling (AO < prev AO) = black
//   Level lines at 20 and 80
//
// AC = AO − SMA(AO, 5)
//   Bar rising  = orange
//   Bar falling = black
//   No level lines
//
// ── Signal conditions (from MT5 screenshots) ──────────────────────────────
//
// BOOM SELL (counter-spike):
//   AO < 0 AND AC < 0 AND stochK < 20 AND K < D
//   (BOOM Image 3,4,7: K=0.92, D=1.61; AO=-30.76, AC=-2.42)
//
// CRASH BUY (counter-spike):
//   AO > 0 AND AC > 0 AND stochK > 80 AND K > D
//
// ── Score ─────────────────────────────────────────────────────────────────
// Driven primarily by Stoch distance from neutral (50):
//   stochScore  = |K − 50| / 50 × 50      (0–50 pts)
//   aoScore     = ao aligned with signal ? 25 : 0
//   acScore     = ac aligned with signal ? 25 : 0
//   total clamped 0–100
// ─────────────────────────────────────────────────────────────────────────────

enum AssetType { boom, crash }

AssetType assetType(String asset) {
  if (asset.startsWith('BOOM')) return AssetType.boom;
  return AssetType.crash;
}

// ── Result ────────────────────────────────────────────────────────────────────
class GardenResult {
  // AO
  final double ao;
  final bool   aoRising;      // current AO bar is orange (ao > prevAo)
  final double aoPct;         // distance from zero as % of recent max, 0–100

  // AC
  final double ac;
  final bool   acRising;      // current AC bar is orange
  final double acPct;

  // Stoch(25,5,8)
  final double stochK;        // slowed K = SMA(rawK,5)
  final double stochD;        // D = SMA(slowedK,8)
  final bool   stochDescending; // K < D
  final bool   stochAscending;  // K > D
  final String stochLabel;    // 'OVERBOUGHT' | 'OVERSOLD' | 'NEUTRAL'

  // Composite score 0–100
  final int    score;
  final String scoreTrend;  // 'RISING' | 'FALLING' | 'FLAT' — momentum over last 5 candles

  // Confluence — how many of the 3 indicators (AO, AC, Stoch) currently
  // point the same direction, 0–3. Shown as a strength bar in the UI.
  final int    confluenceCount;
  final String confluenceDir; // 'BULLISH' | 'BEARISH' | 'MIXED'

  // Signal
  final String signal;    // 'BUY' | 'SELL' | 'WAIT'
  final String dirLabel;
  final bool   armed;

  // BOOM/CRASH spike tracking
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
    required this.score,
    required this.scoreTrend,
    required this.confluenceCount,
    required this.confluenceDir,
    required this.signal,
    required this.dirLabel,
    required this.armed,
    required this.candlesSinceSpike,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GardenState — one per asset×timeframe, holds rolling histories
// ─────────────────────────────────────────────────────────────────────────────
class GardenState {
  // Rolling histories (300 bars max)
  final List<double> _aoH     = [];
  final List<double> _acH     = [];
  final List<double> _slowKH  = [];  // slowed K history for D calculation
  final List<int>    _scoreH  = [];  // last 5 composite scores, for trend

  GardenResult? compute(List<Candle> candles, String asset) {
    if (candles.length < 40) return null;
    final type = assetType(asset);

    // ── AO = SMA(hl2,5) − SMA(hl2,34) ───────────────────────────────────────
    final aoSeries = calcAO(candles);
    if (aoSeries.isEmpty) return null;
    final aoRaw = aoSeries.last;
    if (!aoRaw.isFinite) return null;
    final ao = _r4(aoRaw);
    final aoRising = _aoH.isNotEmpty && ao > _aoH.last;
    _push(_aoH, ao);

    // ── AC = AO − SMA(AO,5) ──────────────────────────────────────────────────
    final acSeries = calcAC(aoSeries);
    if (acSeries.isEmpty) return null;
    final acRaw = acSeries.last;
    if (!acRaw.isFinite) return null;
    final ac = _r4(acRaw);
    final acRising = _acH.isNotEmpty && ac > _acH.last;
    _push(_acH, ac);

    // ── Stoch(25, 5, 8) ───────────────────────────────────────────────────────
    // Step 1: raw %K over 25-bar window
    // Step 2: slowed K = SMA(rawK, 5)
    // Step 3: D = SMA(slowedK, 8)
    final stochResult = _calcStoch(candles);
    if (stochResult == null) return null;
    final stochK = stochResult.$1;
    _push(_slowKH, stochK);
    final stochD = _smaLast(_slowKH, 8);
    if (stochD == null) return null;

    final stochDescending = stochK < stochD;
    final stochAscending  = stochK > stochD;
    final stochLabel = stochK > 80 ? 'OVERBOUGHT'
        : stochK < 20              ? 'OVERSOLD'
        :                            'NEUTRAL';

    // ── Distance-from-zero % (ring fill for AO and AC nodes) ─────────────────
    final aoPct = _distPct(ao, _aoH);
    final acPct = _distPct(ac, _acH);

    // safe guard: AO and AC must be meaningfully non-zero
    final safe = aoPct > 8 && acPct > 8;

    // ── Score — Stoch-primary, 0–100 ─────────────────────────────────────────
    //
    // Stoch is the primary driver because it directly shows overbought/oversold.
    // stochScore: distance of K from 50, normalised to 50 pts
    //   K=0   → 50 pts, K=50 → 0 pts, K=100 → 50 pts
    // aoScore:    25 if AO matches expected direction
    // acScore:    25 if AC matches expected direction

    final stochScore = (stochK - 50).abs() / 50 * 50;

    // Determine expected direction from Stoch + AO alignment
    final isBearishSetup = stochK < 50 && ao < 0;
    final isBullishSetup = stochK > 50 && ao > 0;

    final aoScore = (isBearishSetup && ao < 0) || (isBullishSetup && ao > 0)
        ? 25.0 : 0.0;
    final acScore = (isBearishSetup && ac < 0) || (isBullishSetup && ac > 0)
        ? 25.0 : 0.0;

    final score = (stochScore + aoScore + acScore)
        .round()
        .clamp(0, 100);

    // ── Confidence trend — momentum of the composite score over last 5 candles ─
    // Not just "is it 70 right now" but "is confluence building or fading".
    _scoreH.add(score);
    if (_scoreH.length > 5) _scoreH.removeAt(0);
    final String scoreTrend;
    if (_scoreH.length < 3) {
      scoreTrend = 'FLAT';
    } else {
      final delta = _scoreH.last - _scoreH.first;
      scoreTrend = delta > 4 ? 'RISING' : delta < -4 ? 'FALLING' : 'FLAT';
    }

    // ── Signal — exact MT5 conditions ────────────────────────────────────────
    final String signal;
    switch (type) {
      case AssetType.boom:
        // SELL only — counter-spike strategy
        // MT5 confirmation: AO<0, AC<0, K<20 (oversold), K<D (descending)
        signal = (ao < 0 && ac < 0 && safe && stochK < 20 &&
                stochDescending)
            ? 'SELL' : 'WAIT';

      case AssetType.crash:
        // BUY only — counter-spike strategy
        // Mirror of BOOM: AO>0, AC>0, K>80 (overbought), K>D (ascending)
        signal = (ao > 0 && ac > 0 && safe && stochK > 80 &&
                stochAscending)
            ? 'BUY' : 'WAIT';
    }

    final armed    = signal != 'WAIT';
    final dirLabel = signal == 'SELL' ? 'SELL · SIGNAL'
        : signal == 'BUY'  ? 'BUY · SIGNAL'
        : 'SCANNING…';

    // ── Confluence — how many of AO/AC/Stoch agree on direction ─────────────
    // Bullish lean: AO>0, AC>0, stochK>50. Bearish lean: the opposite.
    // Counted independently of the armed signal, so it's useful even while
    // still "SCANNING" — shows confluence building before the full signal fires.
    final aoBull    = ao > 0;
    final acBull    = ac > 0;
    final stochBull = stochK > 50;
    final bullVotes = [aoBull, acBull, stochBull].where((v) => v).length;
    final bearVotes = 3 - bullVotes;
    final confluenceCount = bullVotes >= bearVotes ? bullVotes : bearVotes;
    final confluenceDir   = bullVotes > bearVotes ? 'BULLISH'
        : bearVotes > bullVotes ? 'BEARISH'
        : 'MIXED';

    // ── Candles since spike ───────────────────────────────────────────────────
    final candlesSinceSpike = calcSpikeStats(candles)?.sequenceCount ?? 0;

    return GardenResult(
      ao: ao, aoRising: aoRising, aoPct: aoPct,
      ac: ac, acRising: acRising, acPct: acPct,
      stochK: stochK, stochD: stochD,
      stochDescending: stochDescending, stochAscending: stochAscending,
      stochLabel: stochLabel,
      score: score, scoreTrend: scoreTrend,
      confluenceCount: confluenceCount, confluenceDir: confluenceDir,
      signal: signal, dirLabel: dirLabel, armed: armed,
      candlesSinceSpike: candlesSinceSpike,
    );
  }

  // ── Stoch(25, 5, 8) ──────────────────────────────────────────────────────
  // Returns (slowedK, rawK) — D is computed externally from slowedK history
  (double, double)? _calcStoch(List<Candle> candles) {
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
    final slowK = rawKs.sublist(rawKs.length - slowing)
        .fold(0.0, (a, b) => a + b) / slowing;
    return (slowK, rawKs.last);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _push(List<double> list, double val) {
    list.add(val);
    if (list.length > 300) list.removeAt(0);
  }

  double _distPct(double val, List<double> hist) {
    if (hist.isEmpty) return 0;
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
// Summary line helper — used by SignalsPage
// ─────────────────────────────────────────────────────────────────────────────
String buildSummaryLine(GardenResult g, String asset) {
  final spikes = '${g.candlesSinceSpike} candles since spike';
  final risk   = g.armed ? '  ·  RISK ${g.score}%' : '';
  return '$spikes$risk';
}
