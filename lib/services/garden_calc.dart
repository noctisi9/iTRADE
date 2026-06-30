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
// BOOM/CRASH 4th node: MiniMax (Silagadze, window=14)
//   delta = u[last] − d[last], range ≈ −1..+1
//   Bearish = delta < previous delta
//
// VIX 4th node: AO/AC MA Cross
//   AO signal line = SMA(AO history, 5)
//   AC signal line = SMA(AC history, 5)
//   Bullish cross  = AO > aoSigLine AND AC > acSigLine
//   Bearish cross  = AO < aoSigLine AND AC < acSigLine
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
// VIX SELL:
//   AO > 0 AND AC < 0 (deceleration) AND stochK > 80 AND K < D
//   OR: AO < 0 AND AC < 0 AND maCross bearish
//   (VIX Image 1: AO=173, AC=-50, K=87, D=90 — overbought, decelerating → SELL)
//
// VIX BUY:
//   AO > 0 AND AC > 0 AND maCross bullish AND stochK ascending
//   (VIX 1s Image 5,6: AO=32.6, AC=-0.33, K=95.75, D=95.02, K>D still → BUY)
//
// ── Score ─────────────────────────────────────────────────────────────────
// Driven primarily by Stoch distance from neutral (50):
//   stochScore  = |K − 50| / 50 × 40      (0–40 pts)
//   aoScore     = ao aligned with signal ? 20 : 0
//   acScore     = ac aligned with signal ? 20 : 0
//   fourthScore = 4th node aligned        ? 20 : 0
//   total clamped 0–100
// ─────────────────────────────────────────────────────────────────────────────

enum AssetType { boom, crash, vix }

AssetType assetType(String asset) {
  if (asset.startsWith('BOOM'))  return AssetType.boom;
  if (asset.startsWith('CRASH')) return AssetType.crash;
  return AssetType.vix;
}

// ── Color token (no Flutter import in service layer) ──────────────────────────
enum Color4 { green, red, orange, neutral }

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

  // BOOM/CRASH left node: MiniMax
  final double mmmDelta;
  final double mmmPct;        // magnitude % of recent max, 0–100
  final bool   mmmBearish;

  // VIX left node: AO/AC MA Cross
  final bool   maCrossBullish;
  final bool   maCrossBearish;
  final double maCrossPct;    // strength 0–100
  final String maCrossLabel;  // 'BULLISH' | 'BEARISH' | 'NEUTRAL'

  // Generic 4th node (maps to whichever applies per asset)
  final String fourthNodeLabel;
  final String fourthBigVal;
  final String fourthSubVal;
  final Color4 fourthColor;
  final double fourthPct;

  // Composite score 0–100
  final int    score;

  // Signal
  final String signal;    // 'BUY' | 'SELL' | 'WAIT'
  final String dirLabel;
  final bool   armed;

  // BOOM/CRASH only
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
    required this.mmmDelta,
    required this.mmmPct,
    required this.mmmBearish,
    required this.maCrossBullish,
    required this.maCrossBearish,
    required this.maCrossPct,
    required this.maCrossLabel,
    required this.fourthNodeLabel,
    required this.fourthBigVal,
    required this.fourthSubVal,
    required this.fourthColor,
    required this.fourthPct,
    required this.score,
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
  final List<double> _deltaH  = [];

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

    // ── MiniMax (BOOM/CRASH 4th node) ─────────────────────────────────────────
    final mmmDelta = _calcMMM(candles) ?? 0.0;
    final mmmBearish = _deltaH.isNotEmpty && mmmDelta < _deltaH.last;
    _push(_deltaH, mmmDelta);
    final dMax   = _deltaH.map((v) => v.abs()).fold(0.0, math.max);
    final mmmPct = dMax == 0 ? 0.0 : math.min(100.0, mmmDelta.abs() / dMax * 100.0);

    // ── AO/AC MA Cross (VIX 4th node) ────────────────────────────────────────
    // AO signal line = SMA-5 of running AO history
    // AC signal line = SMA-5 of running AC history
    final aoSigLine = _smaLast(_aoH, 5);
    final acSigLine = _smaLast(_acH, 5);
    bool maCrossBullish = false;
    bool maCrossBearish = false;
    double maCrossPct   = 0;
    String maCrossLabel = 'NEUTRAL';

    if (aoSigLine != null && acSigLine != null) {
      final aoAbove = ao > aoSigLine;
      final acAbove = ac > acSigLine;
      maCrossBullish = aoAbove && acAbove;
      maCrossBearish = !aoAbove && !acAbove;

      final aoMax  = _aoH.map((v) => v.abs()).fold(0.0, math.max);
      final acMax  = _acH.map((v) => v.abs()).fold(0.0, math.max);
      final aoPct2 = aoMax == 0 ? 0.0
          : math.min(100.0, (ao - aoSigLine).abs() / aoMax * 100.0);
      final acPct2 = acMax == 0 ? 0.0
          : math.min(100.0, (ac - acSigLine).abs() / acMax * 100.0);
      maCrossPct   = (aoPct2 + acPct2) / 2;
      maCrossLabel = maCrossBullish ? 'BULLISH'
          : maCrossBearish           ? 'BEARISH'
          :                            'NEUTRAL';
    }

    // ── 4th node UI values ────────────────────────────────────────────────────
    final String fourthNodeLabel;
    final String fourthBigVal;
    final String fourthSubVal;
    final Color4 fourthColor;
    final double fourthPct;

    if (type == AssetType.vix) {
      fourthNodeLabel = 'MA CROSS';
      fourthBigVal    = maCrossBullish ? 'BULL' : maCrossBearish ? 'BEAR' : '—';
      fourthSubVal    = maCrossLabel;
      fourthColor     = maCrossBullish ? Color4.green
          : maCrossBearish              ? Color4.red
          :                               Color4.neutral;
      fourthPct       = maCrossPct;
    } else {
      fourthNodeLabel = 'MINIMAX';
      fourthBigVal    = '${mmmPct.round()}%';
      fourthSubVal    = mmmBearish ? 'BEARISH' : 'BULLISH';
      fourthColor     = mmmBearish ? Color4.red : Color4.green;
      fourthPct       = mmmPct;
    }

    // ── Score — Stoch-primary, 0–100 ─────────────────────────────────────────
    //
    // Stoch is the primary driver because it directly shows overbought/oversold.
    // From MT5: BOOM K=0.92 (deeply oversold) = strong SELL confidence.
    //           VIX K=95.75 (deeply overbought) while AC negative = high SELL.
    //
    // stochScore: distance of K from 50, normalised to 40 pts
    //   K=0   → 40 pts, K=50 → 0 pts, K=100 → 40 pts
    // aoScore:    20 if AO matches expected direction
    // acScore:    20 if AC matches expected direction
    // fourthScore:20 if 4th node confirms

    final stochScore = (stochK - 50).abs() / 50 * 40;

    // Determine expected direction from Stoch + AO alignment
    final isBearishSetup = stochK < 50 && ao < 0;
    final isBullishSetup = stochK > 50 && ao > 0;

    final aoScore = (isBearishSetup && ao < 0) || (isBullishSetup && ao > 0)
        ? 20.0 : 0.0;
    final acScore = (isBearishSetup && ac < 0) || (isBullishSetup && ac > 0)
        ? 20.0 : 0.0;

    double fourthScore = 0.0;
    if (type == AssetType.vix) {
      fourthScore = (isBearishSetup && maCrossBearish) ||
              (isBullishSetup && maCrossBullish)
          ? 20.0 : 0.0;
    } else {
      fourthScore = (isBearishSetup && mmmBearish) ||
              (isBullishSetup && !mmmBearish)
          ? 20.0 : 0.0;
    }

    final score = (stochScore + aoScore + acScore + fourthScore)
        .round()
        .clamp(0, 100);

    // ── Signal — exact MT5 conditions ────────────────────────────────────────
    final String signal;
    switch (type) {
      case AssetType.boom:
        // SELL only — counter-spike strategy
        // MT5 confirmation: AO<0, AC<0, K<20 (oversold), K<D (descending)
        signal = (ao < 0 && ac < 0 && safe && stochK < 20 &&
                stochDescending && mmmBearish)
            ? 'SELL' : 'WAIT';

      case AssetType.crash:
        // BUY only — counter-spike strategy
        // Mirror of BOOM: AO>0, AC>0, K>80 (overbought), K>D (ascending)
        signal = (ao > 0 && ac > 0 && safe && stochK > 80 &&
                stochAscending && !mmmBearish)
            ? 'BUY' : 'WAIT';

      case AssetType.vix:
        // VIX SELL: MT5 Image 1 — AO=173(+), AC=-50(-), K=87, D=90, K<D
        //   = AO positive but decelerating (AC<0), stoch overbought rolling over
        // VIX BUY: MT5 Image 5,6 — AO=32(+), AC=-0.33(-), K=95, D=95, K>D
        //   = AO positive, still ascending stoch, MA cross bullish
        //
        // SELL condition:
        //   (AC < 0) AND (stochK > 80) AND stochDescending AND maCrossBearish
        //   OR: AO<0 AND AC<0 AND maCrossBearish
        //
        // BUY condition:
        //   AO > 0 AND stochK > 50 AND stochAscending AND maCrossBullish
        if (ac < 0 && stochK > 80 && stochDescending && safe) {
          signal = 'SELL';
        } else if (ao < 0 && ac < 0 && safe && maCrossBearish) {
          signal = 'SELL';
        } else if (ao > 0 && stochK > 50 && stochAscending && safe && maCrossBullish) {
          signal = 'BUY';
        } else {
          signal = 'WAIT';
        }
    }

    final armed    = signal != 'WAIT';
    final dirLabel = signal == 'SELL' ? 'SELL · SIGNAL'
        : signal == 'BUY'  ? 'BUY · SIGNAL'
        : 'SCANNING…';

    // ── Candles since spike (BOOM/CRASH only) ─────────────────────────────────
    final candlesSinceSpike = (type != AssetType.vix)
        ? (calcSpikeStats(candles)?.sequenceCount ?? 0) : 0;

    return GardenResult(
      ao: ao, aoRising: aoRising, aoPct: aoPct,
      ac: ac, acRising: acRising, acPct: acPct,
      stochK: stochK, stochD: stochD,
      stochDescending: stochDescending, stochAscending: stochAscending,
      stochLabel: stochLabel,
      mmmDelta: mmmDelta, mmmPct: mmmPct, mmmBearish: mmmBearish,
      maCrossBullish: maCrossBullish, maCrossBearish: maCrossBearish,
      maCrossPct: maCrossPct, maCrossLabel: maCrossLabel,
      fourthNodeLabel: fourthNodeLabel,
      fourthBigVal: fourthBigVal, fourthSubVal: fourthSubVal,
      fourthColor: fourthColor, fourthPct: fourthPct,
      score: score, signal: signal, dirLabel: dirLabel, armed: armed,
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

  // ── MiniMax (Silagadze, window=14) ───────────────────────────────────────
  double? _calcMMM(List<Candle> candles) {
    const m = 14, scale = 100.0;
    if (candles.length < m) return null;
    final slice = candles.sublist(candles.length - m);
    final s = slice.map((c) => (c.h + c.l) / 2).toList();

    List<double> state(bool invert) {
      final sign = invert ? -1.0 : 1.0;
      final q = List<double>.filled(m, 1.0);
      for (var i = 0; i < m; i++) {
        if (i > 0) {
          q[i] *= math.exp(sign * (s[i] - s[i-1]) / s[i-1] * scale);
        }
        if (i < m - 1) {
          q[i] *= math.exp(sign * (s[i+1] - s[i]) / s[i] * scale);
        }
      }
      final p = List<double>.filled(m, 0.0);
      p[0] = q[0];
      for (var i = 1; i < m; i++) {
        p[i] = p[i-1] * q[i];
      }
      final total = p.fold(0.0, (a, b) => a + b);
      if (total == 0) return p;
      return p.map((v) => v / total).toList();
    }

    return state(false)[m-1] - state(true)[m-1];
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
  final type = assetType(asset);
  if (type == AssetType.vix) {
    final cross = g.maCrossLabel;
    final maRel = g.ao > 0 ? 'ABOVE MA' : 'BELOW MA';
    final risk  = g.armed ? '  ·  RISK ${g.score}%' : '';
    return 'MA CROSS $cross  ·  $maRel$risk';
  } else {
    final spikes = '${g.candlesSinceSpike} candles since spike';
    final risk   = g.armed ? '  ·  RISK ${g.score}%' : '';
    return '$spikes$risk';
  }
}
