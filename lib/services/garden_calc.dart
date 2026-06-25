import 'dart:math' as math;
import '../models/candle.dart';
import 'indicators.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GardenCalc — matches the Garden of Swords HTML engine exactly:
//   · AO  : sma(hl2,5) - sma(hl2,34)
//   · AC  : AO - sma(AO,5)
//   · Stoch: slowed K from raw(25,8) + SMA-5/SMA-34 cross
//   · MMM : Silagadze quantum-tunneling minimax, window=14
//   · Score: 4×25 composite
// ─────────────────────────────────────────────────────────────────────────────

class GardenResult {
  final double ao;
  final double ac;
  final double stochK;   // slowed K, 0-100
  final double mmmDelta; // raw delta from MMM
  final double mmmPct;   // delta magnitude as % of recent range, 0-100
  final bool mmmBearish; // delta shrinking = bearish momentum growing
  final double aoPct;    // for ring fill: distance from zero as % of max, 0-100
  final double acPct;
  final int score;       // composite 0-100
  final String signal;   // 'SELL' | 'WAIT'
  final String dirLabel; // bottom-bar pill text
  final bool armed;      // bottom-bar pill state

  const GardenResult({
    required this.ao,
    required this.ac,
    required this.stochK,
    required this.mmmDelta,
    required this.mmmPct,
    required this.mmmBearish,
    required this.aoPct,
    required this.acPct,
    required this.score,
    required this.signal,
    required this.dirLabel,
    required this.armed,
  });
}

// Rolling histories kept between calls via static state
// (same pattern as the HTML's module-level arrays)
final List<double> _aoH = [], _acH = [], _kH = [], _deltaH = [];

GardenResult? calcGarden(List<Candle> candles) {
  if (candles.length < 40) return null;

  // ── AO ──────────────────────────────────────────────────────────────────
  final aoSeries = calcAO(candles);
  if (aoSeries.isEmpty) return null;
  final aoRaw = aoSeries.last;
  if (!aoRaw.isFinite) return null;
  final ao = double.parse(aoRaw.toStringAsFixed(4));
  _aoH.add(ao);
  if (_aoH.length > 300) _aoH.removeAt(0);

  // ── AC ──────────────────────────────────────────────────────────────────
  final acSeries = calcAC(aoSeries);
  if (acSeries.isEmpty) return null;
  final acRaw = acSeries.last;
  if (!acRaw.isFinite) return null;
  final ac = double.parse(acRaw.toStringAsFixed(4));
  _acH.add(ac);
  if (_acH.length > 300) _acH.removeAt(0);

  // ── Stochastic K(25, slowing=8) ─────────────────────────────────────────
  final stochK = _calcStochK(candles);
  if (stochK == null) return null;
  _kH.add(stochK);
  if (_kH.length > 300) _kH.removeAt(0);

  final kSMA5  = _smaLast(_kH, 5);
  final kSMA34 = _smaLast(_kH, 34);
  final stochDescending =
      kSMA5 != null && kSMA34 != null && kSMA5 < kSMA34;

  // ── Moving Mini Max ──────────────────────────────────────────────────────
  final delta = _calcMMM(candles);
  if (delta == null) return null;
  _deltaH.add(delta);
  if (_deltaH.length > 300) _deltaH.removeAt(0);

  final prevDelta =
      _deltaH.length >= 2 ? _deltaH[_deltaH.length - 2] : delta;
  final mmmBearish = delta < prevDelta;

  final dMax =
      _deltaH.map((v) => v.abs()).fold(0.0, math.max);
  final mmmPct =
      dMax == 0 ? 0.0 : math.min(100.0, (delta.abs() / dMax) * 100);

  // ── Ring percentages ────────────────────────────────────────────────────
  final aoPct  = _distPct(ao,  _aoH);
  final acPct  = _distPct(ac,  _acH);

  // ── Exit guard: must be > 10% of range from zero ─────────────────────────
  final safe = aoPct > 10 && acPct > 10;

  // ── Composite score ──────────────────────────────────────────────────────
  final aoScore    = ao < 0 ? 25.0 : 0.0;
  final acScore    = ac < 0 ? 25.0 : 0.0;
  final stochScore = stochK < 50 ? 25.0 * (1 - stochK / 50) : 0.0;
  final mmmScore   = (mmmBearish && delta < 0)
      ? 25.0 * math.min(1.0, delta.abs() * 20)
      : 0.0;
  final score = (aoScore + acScore + stochScore + mmmScore).round().clamp(0, 100);

  // ── Signal ───────────────────────────────────────────────────────────────
  final isSell = ao < 0 && ac < 0 && safe && stochDescending && mmmBearish;
  final isBuy  = ao > 0 && ac > 0; // standard AO/AC BUY for CRASH / VIX

  final String signal;
  final String dirLabel;
  final bool armed;
  if (isSell) {
    signal   = 'SELL';
    dirLabel = 'SELL · SIGNAL';
    armed    = true;
  } else if (isBuy) {
    signal   = 'BUY';
    dirLabel = 'BUY · SIGNAL';
    armed    = true;
  } else {
    signal   = 'WAIT';
    dirLabel = 'SCANNING…';
    armed    = false;
  }

  return GardenResult(
    ao: ao,
    ac: ac,
    stochK: stochK,
    mmmDelta: delta,
    mmmPct: mmmPct,
    mmmBearish: mmmBearish,
    aoPct: aoPct,
    acPct: acPct,
    score: score,
    signal: signal,
    dirLabel: dirLabel,
    armed: armed,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stochastic K(25, slowing=8)
// Raw K = (Close - LowestLow_25) / (HighestHigh_25 - LowestLow_25) × 100
// Slowed K = SMA(rawK, 8)
// ─────────────────────────────────────────────────────────────────────────────
double? _calcStochK(List<Candle> candles) {
  const kPeriod = 25, slowing = 8;
  final need = kPeriod + slowing - 1;
  if (candles.length < need) return null;

  final slice = candles.sublist(candles.length - need);
  final rawKs = <double>[];

  for (var i = kPeriod - 1; i < slice.length; i++) {
    final window = slice.sublist(i - kPeriod + 1, i + 1);
    final hi = window.map((c) => c.h).reduce(math.max);
    final lo = window.map((c) => c.l).reduce(math.min);
    final close = slice[i].c;
    rawKs.add(hi == lo ? 50.0 : ((close - lo) / (hi - lo)) * 100.0);
  }

  if (rawKs.length < slowing) return null;
  final sum =
      rawKs.sublist(rawKs.length - slowing).fold(0.0, (a, b) => a + b);
  return sum / slowing;
}

// ─────────────────────────────────────────────────────────────────────────────
// Moving Mini Max (Silagadze, window=14)
// Returns delta = u[last] - d[last], range ≈ −1..+1
// ─────────────────────────────────────────────────────────────────────────────
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
    for (var i = 1; i < m; i++) {
      p[i] = p[i - 1] * q[i];
    }
    final total = p.fold(0.0, (a, b) => a + b);
    if (total == 0) return p;
    return p.map((v) => v / total).toList();
  }

  final u = stateArray(false);
  final d = stateArray(true);
  return u[m - 1] - d[m - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Distance of val from zero as % of max absolute magnitude in history.
double _distPct(double val, List<double> hist) {
  if (hist.isEmpty) return 50;
  final mx = hist.map((v) => v.abs()).fold(0.0, math.max);
  return mx == 0 ? 0 : math.min(100.0, (val.abs() / mx) * 100.0);
}

/// SMA of the last n values in a list (or null if too short).
double? _smaLast(List<double> values, int n) {
  if (values.length < n) return null;
  return values.sublist(values.length - n).fold(0.0, (a, b) => a + b) / n;
}
