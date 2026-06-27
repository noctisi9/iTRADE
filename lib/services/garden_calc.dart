import 'dart:math' as math;
import '../models/candle.dart';
import 'indicators.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Garden of Swords — garden_calc.dart  (production v3)
//
// BOOM / CRASH — 4 nodes:
//   TOP    AO   (Awesome Oscillator: sma(hl2,5) − sma(hl2,34))
//   RIGHT  STOCH (K period=25, slowing=8; direction via SMA5/SMA34 on K history)
//   BOTTOM AC   (Accelerator: AO − sma(AO,5))
//   LEFT   MINIMAX (Moving MiniMax, Silagadze window=14)
//
//   Signal:
//     BOOM  → SELL only  (counter-spike)
//     CRASH → BUY  only  (counter-spike)
//   Condition: ao<0 AND ac<0 AND stochDescending AND mmmBearish AND safe (BOOM)
//              ao>0 AND ac>0 AND stochAscending  AND !mmmBearish AND safe (CRASH)
//
// VIX — 4 nodes:
//   TOP    AO
//   RIGHT  STOCH
//   BOTTOM AC
//   LEFT   MA CROSS  (AO above/below its own SMA-5 signal line,
//                     AND AC above/below its own SMA-5 signal line,
//                     confirmed together — the cross of momentum)
//
//   Signal:
//     SELL: ao<0 AND ac<0 AND MA cross bearish (both below their signal line)
//     BUY:  ao>0 AND ac>0 AND MA cross bullish (both above their signal line)
//
// Score: 4 × 25 = 100  (matches calcScore() in garden-of-swords.html)
// ─────────────────────────────────────────────────────────────────────────────

enum AssetType { boom, crash, vix }

AssetType assetType(String asset) {
  if (asset.startsWith('BOOM'))  return AssetType.boom;
  if (asset.startsWith('CRASH')) return AssetType.crash;
  return AssetType.vix;
}

// ── Result ────────────────────────────────────────────────────────────────────
class GardenResult {
  final double ao;
  final double ac;
  final double stochK;
  final bool   stochDescending;
  final bool   stochAscending;
  final String stochLabel;   // 'OVERBOUGHT' | 'OVERSOLD' | 'NEUTRAL'

  // BOOM/CRASH left node: MiniMax
  final double mmmDelta;
  final double mmmPct;       // magnitude as % of recent max, 0–100
  final bool   mmmBearish;

  // VIX left node: MA Cross
  final bool   maCrossBullish;  // AO and AC both above their SMA-5 signal lines
  final bool   maCrossBearish;  // AO and AC both below their SMA-5 signal lines
  final double maCrossPct;      // combined cross magnitude, 0–100
  final String maCrossLabel;    // 'BULLISH' | 'BEARISH' | 'NEUTRAL'

  // Generic 4th node values for the UI (maps to whichever applies)
  final String fourthNodeLabel; // 'MINIMAX' | 'MA CROSS'
  final String fourthBigVal;    // e.g. '62%' or 'BULL'
  final String fourthSubVal;    // 'BEARISH'/'BULLISH'/'NEUTRAL'
  final Color4 fourthColor;     // enum for the ring/glow color

  // Ring fill (0–100)
  final double aoPct;
  final double acPct;
  // stochK used directly as pct for STOCH ring
  final double fourthPct;       // ring fill for 4th node

  final int    score;
  final String signal;      // 'BUY' | 'SELL' | 'WAIT'
  final String dirLabel;
  final bool   armed;

  final int    candlesSinceSpike;  // BOOM/CRASH only

  const GardenResult({
    required this.ao,
    required this.ac,
    required this.stochK,
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
    required this.aoPct,
    required this.acPct,
    required this.fourthPct,
    required this.score,
    required this.signal,
    required this.dirLabel,
    required this.armed,
    required this.candlesSinceSpike,
  });
}

// Simple color token — avoids importing Flutter into a service file
enum Color4 { green, red, neutral }

// ─────────────────────────────────────────────────────────────────────────────
// GardenState — one instance per asset×timeframe
// ─────────────────────────────────────────────────────────────────────────────
class GardenState {
  final List<double> _aoH    = [];
  final List<double> _acH    = [];
  final List<double> _kH     = [];
  final List<double> _deltaH = [];

  // ── Public entry point ────────────────────────────────────────────────────
  GardenResult? compute(List<Candle> candles, String asset) {
    if (candles.length < 40) return null;
    final type = assetType(asset);

    // ── AO (matches HTML calcAO exactly) ─────────────────────────────────────
    final aoSeries = calcAO(candles);
    if (aoSeries.isEmpty) return null;
    final aoRaw = aoSeries.last;
    if (!aoRaw.isFinite) return null;
    final ao = _r4(aoRaw);
    _push(_aoH, ao);

    // ── AC (matches HTML calcAC exactly) ─────────────────────────────────────
    final acSeries = calcAC(aoSeries);
    if (acSeries.isEmpty) return null;
    final acRaw = acSeries.last;
    if (!acRaw.isFinite) return null;
    final ac = _r4(acRaw);
    _push(_acH, ac);

    // ── Stoch K(25, slowing=8) ────────────────────────────────────────────────
    final stochK = _calcStochK(candles);
    if (stochK == null) return null;
    _push(_kH, stochK);

    final kSMA5  = _smaLast(_kH, 5);
    final kSMA34 = _smaLast(_kH, 34);
    final stochDescending = kSMA5 != null && kSMA34 != null && kSMA5 < kSMA34;
    final stochAscending  = kSMA5 != null && kSMA34 != null && kSMA5 > kSMA34;
    final stochLabel = stochK > 80 ? 'OVERBOUGHT'
        : stochK < 20              ? 'OVERSOLD'
        :                            'NEUTRAL';

    // ── Distance-from-zero percentages (ring fill) ────────────────────────────
    final aoPct = _distPct(ao, _aoH);
    final acPct = _distPct(ac, _acH);
    final safe  = aoPct > 10 && acPct > 10;

    // ── BOOM/CRASH 4th node: MiniMax ─────────────────────────────────────────
    final mmmDelta = _calcMMM(candles) ?? 0.0;
    _push(_deltaH, mmmDelta);
    final prevDelta  = _deltaH.length >= 2 ? _deltaH[_deltaH.length - 2] : mmmDelta;
    final mmmBearish = mmmDelta < prevDelta;
    final dMax   = _deltaH.map((v) => v.abs()).fold(0.0, math.max);
    final mmmPct = dMax == 0 ? 0.0 : math.min(100.0, mmmDelta.abs() / dMax * 100.0);

    // ── VIX 4th node: AO/AC MA Cross ─────────────────────────────────────────
    //
    // Signal line for AO = SMA-5 of the running AO history
    // Signal line for AC = SMA-5 of the running AC history
    //
    // Cross BULLISH: AO > aoSignalLine  AND  AC > acSignalLine
    // Cross BEARISH: AO < aoSignalLine  AND  AC < acSignalLine
    //
    // Strength: average of how far AO and AC are above/below their signal lines,
    //           expressed as % of their respective recent maximum distances.
    final aoSigLine = _smaLast(_aoH, 5);
    final acSigLine = _smaLast(_acH, 5);

    final bool maCrossBullish;
    final bool maCrossBearish;
    double maCrossPct = 0;
    String maCrossLabel;

    if (aoSigLine != null && acSigLine != null) {
      final aoAbove = ao > aoSigLine;
      final acAbove = ac > acSigLine;
      maCrossBullish = aoAbove && acAbove;
      maCrossBearish = !aoAbove && !acAbove;

      // Strength = avg of normalised distances
      final aoDist = (ao - aoSigLine).abs();
      final acDist = (ac - acSigLine).abs();
      final aoMax  = _aoH.length > 1
          ? _aoH.map((v) => v.abs()).fold(0.0, math.max) : 1.0;
      final acMax  = _acH.length > 1
          ? _acH.map((v) => v.abs()).fold(0.0, math.max) : 1.0;
      final aoPct2 = aoMax == 0 ? 0.0 : math.min(100.0, aoDist / aoMax * 100.0);
      final acPct2 = acMax == 0 ? 0.0 : math.min(100.0, acDist / acMax * 100.0);
      maCrossPct  = (aoPct2 + acPct2) / 2;

      maCrossLabel = maCrossBullish ? 'BULLISH'
          : maCrossBearish           ? 'BEARISH'
          :                            'NEUTRAL';
    } else {
      maCrossBullish = false;
      maCrossBearish = false;
      maCrossLabel   = 'NEUTRAL';
    }

    // ── 4th node UI values (switches on asset type) ───────────────────────────
    final String fourthNodeLabel;
    final String fourthBigVal;
    final String fourthSubVal;
    final Color4 fourthColor;
    final double fourthPct;

    if (type == AssetType.vix) {
      fourthNodeLabel = 'MA CROSS';
      fourthBigVal    = maCrossLabel == 'BULLISH' ? 'BULL'
          : maCrossLabel == 'BEARISH'              ? 'BEAR'
          :                                          '—';
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

    // ── Score (matches HTML calcScore exactly) ────────────────────────────────
    //
    // HTML: aoS = ao<0 ? 25 : 0
    //       acS = ac<0 ? 25 : 0
    //       stochS = k<50 ? 25*(1-k/50) : 0
    //       mmmS   = delta<0 ? 25*min(1,|delta|*20) : 0
    //
    // For VIX we substitute mmmS with maCrossScore:
    //   maCrossScore = maCrossBearish ? 25*(maCrossPct/100) : 0  (for SELL)
    //   (when computing BUY score: aoS uses ao>0, acS uses ac>0, etc.)
    //
    // We compute a universal score: how aligned are indicators toward a trade?
    final aoS    = ao < 0 ? 25.0 : 0.0;
    final acS    = ac < 0 ? 25.0 : 0.0;
    final stochS = stochK < 50 ? 25.0 * (1 - stochK / 50) : 0.0;
    final double fourthS;
    if (type == AssetType.vix) {
      fourthS = maCrossBearish ? 25.0 * (maCrossPct / 100.0) : 0.0;
    } else {
      fourthS = mmmDelta < 0 ? 25.0 * math.min(1.0, mmmDelta.abs() * 20) : 0.0;
    }
    final score = (aoS + acS + stochS + fourthS).round().clamp(0, 100);

    // ── Signal — sustained, one fires until conditions break ──────────────────
    final String signal;
    switch (type) {
      case AssetType.boom:
        // Counter-spike: SELL only
        signal = (ao < 0 && ac < 0 && safe && stochDescending && mmmBearish)
            ? 'SELL' : 'WAIT';
      case AssetType.crash:
        // Counter-spike: BUY only
        signal = (ao > 0 && ac > 0 && safe && stochAscending && !mmmBearish)
            ? 'BUY' : 'WAIT';
      case AssetType.vix:
        if (ao < 0 && ac < 0 && safe && maCrossBearish) {
          signal = 'SELL';
        } else if (ao > 0 && ac > 0 && safe && maCrossBullish) {
          signal = 'BUY';
        } else {
          signal = 'WAIT';
        }
    }

    final armed    = signal != 'WAIT';
    final dirLabel = signal == 'SELL' ? 'SELL · SIGNAL'
        : signal == 'BUY' ? 'BUY · SIGNAL'
        : 'SCANNING…';

    // ── Candles since last spike (BOOM/CRASH only) ────────────────────────────
    int candlesSinceSpike = 0;
    if (type != AssetType.vix) {
      candlesSinceSpike = calcSpikeStats(candles)?.sequenceCount ?? 0;
    }

    return GardenResult(
      ao: ao, ac: ac,
      stochK: stochK,
      stochDescending: stochDescending,
      stochAscending: stochAscending,
      stochLabel: stochLabel,
      mmmDelta: mmmDelta,
      mmmPct: mmmPct,
      mmmBearish: mmmBearish,
      maCrossBullish: maCrossBullish,
      maCrossBearish: maCrossBearish,
      maCrossPct: maCrossPct,
      maCrossLabel: maCrossLabel,
      fourthNodeLabel: fourthNodeLabel,
      fourthBigVal: fourthBigVal,
      fourthSubVal: fourthSubVal,
      fourthColor: fourthColor,
      aoPct: aoPct,
      acPct: acPct,
      fourthPct: fourthPct,
      score: score,
      signal: signal,
      dirLabel: dirLabel,
      armed: armed,
      candlesSinceSpike: candlesSinceSpike,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stochastic K(25, slowing=8) — matches HTML calcStoch() exactly
  // ─────────────────────────────────────────────────────────────────────────
  double? _calcStochK(List<Candle> candles) {
    const kPeriod = 25, slowing = 8;
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
    return rawKs.sublist(rawKs.length - slowing).fold(0.0, (a, b) => a + b) / slowing;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Moving MiniMax (Silagadze, window=14) — matches HTML calcMMM() exactly
  // Used only for BOOM/CRASH
  // ─────────────────────────────────────────────────────────────────────────
  double? _calcMMM(List<Candle> candles) {
    const m = 14, scale = 100.0;
    if (candles.length < m) return null;
    final slice = candles.sublist(candles.length - m);
    final s = slice.map((c) => (c.h + c.l) / 2).toList();

    List<double> stateArray(bool invert) {
      final sign = invert ? -1.0 : 1.0;
      final q = List<double>.filled(m, 1.0);
      for (var i = 0; i < m; i++) {
        if (i > 0) {
          final ret = (s[i] - s[i - 1]) / s[i - 1];
          q[i] *= math.exp(sign * ret * scale);
        }
        if (i < m - 1) {
          final ret = (s[i + 1] - s[i]) / s[i];
          q[i] *= math.exp(sign * ret * scale);
        }
      }
      final p = List<double>.filled(m, 0.0);
      p[0] = q[0];
      for (var i = 1; i < m; i++) p[i] = p[i - 1] * q[i];
      final total = p.fold(0.0, (a, b) => a + b);
      if (total == 0) return p;
      return p.map((v) => v / total).toList();
    }

    final u = stateArray(false);
    final d = stateArray(true);
    return u[m - 1] - d[m - 1];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  void _push(List<double> list, double val) {
    list.add(val);
    if (list.length > 300) list.removeAt(0);
  }

  double _distPct(double val, List<double> hist) {
    if (hist.isEmpty) return 50;
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
// Summary line — used by SignalsPage below the chart
// ─────────────────────────────────────────────────────────────────────────────
String buildSummaryLine(GardenResult g, String asset) {
  final type = assetType(asset);
  if (type == AssetType.vix) {
    // VIX: show MA cross direction + AO/AC relation to MA + risk when armed
    final cross  = g.maCrossLabel;
    final maRel  = g.ao > 0 ? 'ABOVE MA' : 'BELOW MA';
    final risk   = g.armed ? '  ·  RISK ${g.score}%' : '';
    return 'MA CROSS $cross  ·  $maRel$risk';
  } else {
    // BOOM/CRASH: candles since spike + risk when armed
    final spikes = '${g.candlesSinceSpike} candles since spike';
    final risk   = g.armed ? '  ·  RISK ${g.score}%' : '';
    return '$spikes$risk';
  }
}
