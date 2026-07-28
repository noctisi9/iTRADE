import 'dart:math' as math;
import '../models/candle.dart';
import 'indicators.dart';

// ─────────────────────────────────────────────────────────────────────────────
// garden_calc v5 — Production engine
//
// THREE nodes:
//   NOX I  (top)          — was AO: SMA(hl2,5) − SMA(hl2,34)
//   NOX II (bottom-left)  — was AC: NOX I − SMA(NOX I, 5)
//   RISK   (bottom-right) — confluence risk: HIGH🔥 or LOW❄
//
// STOCHASTIC COMPLETELY REMOVED.
//
// Signal rule (BOOM SELL / CRASH BUY):
//   NOX I  < 0 AND NOX II < 0 AND both ≥ 2% from zero → BOOM SELL
//   NOX I  > 0 AND NOX II > 0 AND both ≥ 2% from zero → CRASH BUY
//
//   The 2% buffer prevents false signals right at the zero crossing.
//   Once fired, signal holds until GENUINE misalignment
//   (both must return toward zero and lose alignment — not just a flicker).
//
// Risk curve (confluence risk %):
//   HIGH 🔥 when risk ≥ 50%
//   LOW  ❄  when risk < 50%
//
//   Risk is HIGH on both ends of the distance scale:
//   - Just crossed zero (fragile, could flip)         → HIGH
//   - Sweet spot (committed, not exhausted)           → LOW
//   - Extended run (reversal anticipated)             → HIGH
//   - Spike overdue (candles since spike very high)   → raises risk
// ─────────────────────────────────────────────────────────────────────────────

enum AssetType { boom, crash }

AssetType assetType(String asset) =>
    asset.startsWith('BOOM') ? AssetType.boom : AssetType.crash;

class GardenResult {
  // NOX I (formerly AO)
  final double noxI;
  final bool   noxIRising;
  final double noxIPct;      // distance from zero as % of recent max, 0–100

  // NOX II (formerly AC)
  final double noxII;
  final bool   noxIIRising;
  final double noxIIPct;

  // Confluence risk
  final int    riskPct;      // 0–100 internal
  final bool   isHighRisk;   // true = HIGH🔥, false = LOW❄
  final String riskLabel;    // 'HIGH 🔥' | 'LOW ❄'

  // Candles since spike
  final int    candlesSinceSpike;

  // Signal
  final String signal;       // 'BUY' | 'SELL' | 'WAIT'
  final String dirLabel;
  final bool   armed;

  const GardenResult({
    required this.noxI,
    required this.noxIRising,
    required this.noxIPct,
    required this.noxII,
    required this.noxIIRising,
    required this.noxIIPct,
    required this.riskPct,
    required this.isHighRisk,
    required this.riskLabel,
    required this.candlesSinceSpike,
    required this.signal,
    required this.dirLabel,
    required this.armed,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GardenState — one per asset × timeframe
// ─────────────────────────────────────────────────────────────────────────────
class GardenState {
  final List<double> _noxIH  = [];   // running history for signal line calc
  final List<double> _noxIIH = [];

  // Previous values for rising/falling detection
  double? _prevNoxI;
  double? _prevNoxII;

  // Signal persistence — track last confirmed signal to avoid rapid flipping
  String _confirmedSignal = 'WAIT';
  int    _confirmCount    = 0;       // candles the current signal has been held
  static const _minConfirmCandles = 2; // must hold for 2 candles before firing

  GardenResult? compute(List<Candle> candles, String asset) {
    if (candles.length < 40) return null;
    final type = assetType(asset);

    // ── NOX I = AO = SMA(hl2,5) − SMA(hl2,34) ────────────────────────────
    final aoSeries = calcAO(candles);
    if (aoSeries.isEmpty) return null;
    final noxIRaw = aoSeries.last;
    if (!noxIRaw.isFinite) return null;
    final noxI = _r4(noxIRaw);
    final noxIRising = _prevNoxI != null && noxI > _prevNoxI!;
    _prevNoxI = noxI;
    _push(_noxIH, noxI);

    // ── NOX II = AC = NOX I − SMA(NOX I, 5) ──────────────────────────────
    final acSeries = calcAC(aoSeries);
    if (acSeries.isEmpty) return null;
    final noxIIRaw = acSeries.last;
    if (!noxIIRaw.isFinite) return null;
    final noxII = _r4(noxIIRaw);
    final noxIIRising = _prevNoxII != null && noxII > _prevNoxII!;
    _prevNoxII = noxII;
    _push(_noxIIH, noxII);

    // ── Distance from zero as % of recent maximum ─────────────────────────
    final noxIPct  = _distPct(noxI,  _noxIH);
    final noxIIPct = _distPct(noxII, _noxIIH);

    // ── 2% buffer: both must be ≥ 2% from zero to avoid false signals ─────
    final noxISafe  = noxIPct  >= 2.0;
    final noxIISafe = noxIIPct >= 2.0;
    final bothSafe  = noxISafe && noxIISafe;

    // ── Raw alignment ──────────────────────────────────────────────────────
    final rawBoomSell  = noxI  < 0 && noxII  < 0 && bothSafe;
    final rawCrashBuy  = noxI  > 0 && noxII  > 0 && bothSafe;

    // ── Signal persistence: require _minConfirmCandles consecutive candles ─
    // before announcing a new signal. This stops rapid BUY→SELL→BUY flipping.
    final String rawSignal;
    switch (type) {
      case AssetType.boom:
        rawSignal = rawBoomSell ? 'SELL' : 'WAIT';
      case AssetType.crash:
        rawSignal = rawCrashBuy ? 'BUY'  : 'WAIT';
    }

    if (rawSignal == _confirmedSignal && rawSignal != 'WAIT') {
      // Continuing same signal — increment hold count
      _confirmCount++;
    } else if (rawSignal != 'WAIT' && rawSignal != _confirmedSignal) {
      // New potential signal — start confirmation count from 1
      if (_confirmCount >= _minConfirmCandles ||
          _confirmedSignal == 'WAIT') {
        // Previous signal was held long enough — accept new one
        _confirmedSignal = rawSignal;
        _confirmCount    = 1;
      } else {
        // Too early — don't flip yet, keep previous
        _confirmCount = 0;
      }
    } else {
      // rawSignal = WAIT = misalignment confirmed
      _confirmedSignal = 'WAIT';
      _confirmCount    = 0;
    }

    final signal   = _confirmedSignal;
    final armed    = signal != 'WAIT';
    final dirLabel = signal == 'SELL' ? 'SELL · SIGNAL'
        : signal == 'BUY' ? 'BUY · SIGNAL'
        : 'SCANNING…';

    // ── Candles since spike ────────────────────────────────────────────────
    final candlesSinceSpike = calcSpikeStats(candles)?.sequenceCount ?? 0;

    // ── Confluence risk curve ──────────────────────────────────────────────
    final avgDist  = (noxIPct + noxIIPct) / 2;
    final riskPct  = _calcRisk(avgDist, candlesSinceSpike);
    final isHigh   = riskPct >= 50;
    final riskLabel = isHigh ? 'HIGH 🔥' : 'LOW ❄';

    return GardenResult(
      noxI: noxI, noxIRising: noxIRising, noxIPct: noxIPct,
      noxII: noxII, noxIIRising: noxIIRising, noxIIPct: noxIIPct,
      riskPct: riskPct, isHighRisk: isHigh, riskLabel: riskLabel,
      candlesSinceSpike: candlesSinceSpike,
      signal: signal, dirLabel: dirLabel, armed: armed,
    );
  }

  // ── Confluence risk curve ─────────────────────────────────────────────────
  // HIGH on both ends, LOW in the sweet spot (40–60% from zero)
  int _calcRisk(double distPct, int candlesSinceSpike) {
    double base;
    if (distPct < 15) {
      // Just crossed zero — fragile, could flip back
      base = 90 - (distPct / 15) * 20;        // 90 → 70
    } else if (distPct < 45) {
      // Building conviction
      base = 70 - ((distPct - 15) / 30) * 60; // 70 → 10
    } else if (distPct < 55) {
      // Sweet spot — committed momentum
      base = 10 - ((distPct - 45) / 10) * 5;  // 10 → 5
    } else if (distPct < 75) {
      // Extended run — reversal building
      base = 5 + ((distPct - 55) / 20) * 50;  // 5 → 55
    } else {
      // Exhaustion — reversal expected
      base = 55 + ((distPct - 75) / 25) * 35; // 55 → 90
    }

    // Spike timing modifier
    final spikeAdj = candlesSinceSpike < 20  ? -5
        : candlesSinceSpike < 50             ?  0
        : candlesSinceSpike < 100            ? 10
        :                                      20;

    return (base + spikeAdj).round().clamp(2, 98);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _push(List<double> list, double val) {
    list.add(val);
    if (list.length > 500) list.removeAt(0);
  }

  double _distPct(double val, List<double> hist) {
    if (hist.length < 2) return 0;
    final mx = hist.map((v) => v.abs()).fold(0.0, math.max);
    return mx == 0 ? 0 : math.min(100.0, val.abs() / mx * 100.0);
  }

  double _r4(double v) => double.parse(v.toStringAsFixed(4));
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary line for signals page
// ─────────────────────────────────────────────────────────────────────────────
String buildSummaryLine(GardenResult g) {
  final spike = '${g.candlesSinceSpike}c since spike';
  final risk  = g.riskLabel;
  final sig   = g.armed ? '  ·  ${g.signal}' : '';
  return '$spike  ·  $risk$sig';
}
