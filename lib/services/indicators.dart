import 'dart:math' as math;
import '../models/candle.dart';

const Map<String, String> assetSymbol = {
  'BOOM1000': 'BOOM1000',
  'CRASH1000': 'CRASH1000',
  'VIX75': 'R_75',
  'VIX75 1s': '1HZ75V',
};

List<double> smaArr(List<double> values, int period) {
  final out = <double>[];
  double sum = 0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    out.add(i >= period - 1 ? sum / period : double.nan);
  }
  return out;
}

List<double> emaArr(List<double> values, int period) {
  final out = <double>[];
  final k = 2 / (period + 1);
  double prev = double.nan;
  for (var i = 0; i < values.length; i++) {
    if (prev.isNaN) {
      prev = values[i];
    } else {
      prev = values[i] * k + prev * (1 - k);
    }
    out.add(prev);
  }
  return out;
}

/// AO: sma(hl2,5) - sma(hl2,34) — exact MT5 algorithm
List<double> calcAO(List<Candle> candles) {
  final hl2 = candles.map((c) => (c.h + c.l) / 2).toList();
  final fast = smaArr(hl2, 5);
  final slow = smaArr(hl2, 34);
  return List.generate(fast.length, (i) {
    final f = fast[i];
    final s = slow[i];
    return (f.isFinite && s.isFinite) ? f - s : double.nan;
  });
}

/// AC: AO - sma(AO, 5) — exact MT5 algorithm
List<double> calcAC(List<double> aoSeries) {
  final valid = aoSeries.map((v) => v.isFinite ? v : 0.0).toList();
  final sig = smaArr(valid, 5);
  return List.generate(
      valid.length, (i) => sig[i].isFinite ? valid[i] - sig[i] : double.nan);
}

class IndicatorResult {
  final double ao, ac;
  final String aoBreakout; // 'max' | 'min' | 'none'
  final List<double> aoSeries, acSeries;
  IndicatorResult({
    required this.ao,
    required this.ac,
    required this.aoBreakout,
    required this.aoSeries,
    required this.acSeries,
  });
}

IndicatorResult? calcIndicators(List<Candle> candles) {
  if (candles.length < 35) return null;
  final ao = calcAO(candles);
  final aoLastRaw = ao.isNotEmpty ? ao.last : 0.0;
  final aoLast = aoLastRaw.isFinite ? aoLastRaw : 0.0;
  final ac = calcAC(ao);
  final acLastRaw = ac.isNotEmpty ? ac.last : 0.0;
  final acLast = acLastRaw.isFinite ? acLastRaw : 0.0;

  final tailStart = math.max(0, ao.length - 21);
  final tailEnd = math.max(0, ao.length - 1);
  final aoTail =
      tailEnd > tailStart ? ao.sublist(tailStart, tailEnd) : <double>[];
  final finite = aoTail.where((v) => v.isFinite).toList();
  final aoMax = finite.isEmpty ? double.negativeInfinity : finite.reduce(math.max);
  final aoMin = finite.isEmpty ? double.infinity : finite.reduce(math.min);

  String breakout = 'none';
  if (aoLast > aoMax) {
    breakout = 'max';
  } else if (aoLast < aoMin) {
    breakout = 'min';
  }

  return IndicatorResult(
    ao: double.parse(aoLast.toStringAsFixed(4)),
    ac: double.parse(acLast.toStringAsFixed(4)),
    aoBreakout: breakout,
    aoSeries: ao,
    acSeries: ac,
  );
}

class DensityPoint {
  final int t;
  final double f;
  const DensityPoint(this.t, this.f);
}

class SpikeStats {
  final int sequenceCount;
  final double ao, ac;
  final double welfordMean, welfordStd;
  final double cusumH, cusumL, cusumThreshold, cusumK;
  final List<double> cusumWave;
  final bool cusumAlert;
  final double survivalProb, spikeProb;
  final List<DensityPoint> densityWave;
  final double highLowSpread;
  final int tickVolume;

  SpikeStats({
    required this.sequenceCount,
    required this.ao,
    required this.ac,
    required this.welfordMean,
    required this.welfordStd,
    required this.cusumH,
    required this.cusumL,
    required this.cusumThreshold,
    required this.cusumK,
    required this.cusumWave,
    required this.cusumAlert,
    required this.survivalProb,
    required this.spikeProb,
    required this.densityWave,
    required this.highLowSpread,
    required this.tickVolume,
  });
}

class _MeanStd {
  final double mean, std;
  _MeanStd(this.mean, this.std);
}

_MeanStd _welfordRun(List<double> values) {
  double mean = 0, m2 = 0;
  int n = 0;
  for (final x in values) {
    if (!x.isFinite) continue;
    n++;
    final d1 = x - mean;
    mean += d1 / n;
    final d2 = x - mean;
    m2 += d1 * d2;
  }
  final variance = n > 1 ? m2 / (n - 1) : 0.0;
  return _MeanStd(mean, math.sqrt(math.max(0, variance)));
}

SpikeStats? calcSpikeStats(List<Candle> candles) {
  if (candles.length < 35) return null;
  final aoSeries = calcAO(candles);
  final acSeries = calcAC(aoSeries);
  final aoLastRaw = aoSeries.isNotEmpty ? aoSeries.last : 0.0;
  final ao = aoLastRaw.isFinite ? aoLastRaw : 0.0;
  final acLastRaw = acSeries.isNotEmpty ? acSeries.last : 0.0;
  final ac = acLastRaw.isFinite ? acLastRaw : 0.0;

  final spikeIdxs = <int>[];
  for (var i = 0; i < candles.length; i++) {
    if (candles[i].spike) spikeIdxs.add(i);
  }
  final lastSpike = spikeIdxs.isNotEmpty ? spikeIdxs.last : -1;
  final sequenceCount = candles.length - 1 - lastSpike;

  final acClean = acSeries.where((v) => v.isFinite).toList();
  final w = _welfordRun(acClean);
  final welfordMean = w.mean, welfordStd = w.std;

  final k = 0.5 * (welfordStd != 0 ? welfordStd : 1e-6);
  final h = 4.0 * (welfordStd != 0 ? welfordStd : 1e-6);
  double sH = 0, sL = 0;
  final cusumWave = <double>[];
  for (final x in acClean) {
    sH = math.max(0, sH + (x - welfordMean) - k);
    sL = math.max(0, sL + (welfordMean - x) - k);
    cusumWave.add(sH);
  }
  final cusumAlert = sH > h || sL > h;

  final intervals = <int>[];
  for (var i = 1; i < spikeIdxs.length; i++) {
    intervals.add(spikeIdxs[i] - spikeIdxs[i - 1]);
  }

  final di = <int, int>{};
  for (final t in intervals) {
    di[t] = (di[t] ?? 0) + 1;
  }
  double survival(int t) {
    double s = 1;
    for (var ti = 1; ti <= t; ti++) {
      final d = di[ti] ?? 0;
      if (d == 0) continue;
      var n = 0;
      for (final x in intervals) {
        if (x >= ti) n++;
      }
      if (n > 0) s *= 1 - d / n;
    }
    return s;
  }

  final survivalProb = intervals.isNotEmpty ? survival(sequenceCount) : 1.0;
  final spikeProb = 1 - survivalProb;

  final tMax = math.max(sequenceCount + 20, 40);
  final densityWave = <DensityPoint>[];
  double ht = 0;
  for (var t = 1; t <= tMax; t++) {
    final d = di[t] ?? 0;
    var n = 0;
    for (final x in intervals) {
      if (x >= t) n++;
    }
    if (n > 0 && d > 0) ht += d / n;
    densityWave.add(DensityPoint(t, ht * survival(t)));
  }

  final last = candles.last;
  return SpikeStats(
    sequenceCount: sequenceCount,
    ao: double.parse(ao.toStringAsFixed(5)),
    ac: double.parse(ac.toStringAsFixed(5)),
    welfordMean: double.parse(welfordMean.toStringAsFixed(5)),
    welfordStd: double.parse(welfordStd.toStringAsFixed(5)),
    cusumH: double.parse(sH.toStringAsFixed(5)),
    cusumL: double.parse(sL.toStringAsFixed(5)),
    cusumThreshold: double.parse(h.toStringAsFixed(5)),
    cusumK: double.parse(k.toStringAsFixed(5)),
    cusumWave: cusumWave,
    cusumAlert: cusumAlert,
    survivalProb: double.parse(survivalProb.toStringAsFixed(4)),
    spikeProb: double.parse(spikeProb.toStringAsFixed(4)),
    densityWave: densityWave,
    highLowSpread: double.parse((last.h - last.l).toStringAsFixed(5)),
    tickVolume:
        ((last.h - last.l) / math.max(welfordStd, 1e-6) * 30).round(),
  );
}

/// Rolling z-score (Welford window) used by Engine 3 on the indicators page.
List<double> welfordSeries(List<double> values, {int win = 14}) {
  final out = <double>[];
  for (var i = 0; i < values.length; i++) {
    final sliceStart = math.max(0, i - win + 1);
    final slice = values.sublist(sliceStart, i + 1);
    double mean = 0, m2 = 0;
    var n = 0;
    for (final v in slice) {
      n++;
      final delta = v - mean;
      mean += delta / n;
      m2 += delta * (v - mean);
    }
    final stdev = n > 1 ? math.sqrt(m2 / (n - 1)) : 0.0;
    final z = stdev > 0 ? (values[i] - mean) / stdev : 0.0;
    out.add(z);
  }
  return out;
}
