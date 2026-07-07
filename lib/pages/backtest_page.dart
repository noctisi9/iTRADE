import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
import '../services/garden_calc.dart';
import '../services/indicators.dart';
import '../services/journal_db.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BacktestPage
// Automated backtesting: replays the garden engine candle-by-candle over
// everything cached in SQLite for the chosen asset/timeframe, and reports
// how the signals that fired actually would have played out N candles later
// (using the same "5 candles forward" convention as the live signal text).
//
// This is the automated variant — it runs the whole history and reports
// statistics, rather than manually scrolling through candles.
// ─────────────────────────────────────────────────────────────────────────────

class BacktestPage extends StatefulWidget {
  const BacktestPage({super.key});

  @override
  State<BacktestPage> createState() => _BacktestPageState();
}

class _BacktestResult {
  final int totalSignals;
  final int wins;
  final int losses;
  final double avgPointsWin;
  final double avgPointsLoss;
  final int candlesAnalyzed;
  const _BacktestResult({
    required this.totalSignals, required this.wins, required this.losses,
    required this.avgPointsWin, required this.avgPointsLoss,
    required this.candlesAnalyzed,
  });
  double get winRate => totalSignals == 0 ? 0 : wins / totalSignals * 100;
}

class _BacktestPageState extends State<BacktestPage> {
  String _asset = kAssets.first;
  String _tf    = '1m';
  int    _forwardCandles = 5;
  bool   _running = false;
  _BacktestResult? _result;
  String? _error;

  Future<void> _run() async {
    setState(() { _running = true; _result = null; _error = null; });

    try {
      // Pull everything cached for this asset/timeframe. Falls back to
      // whatever's live in memory if SQLite has nothing yet.
      var candles = await JournalDb.instance.loadCandles(_asset, _tf, limit: 5000);
      if (candles.isEmpty) {
        final symbol = assetSymbol[_asset]!;
        candles = DerivFeed.instance.current(symbol, _tf);
      }

      if (candles.length < 60) {
        setState(() {
          _running = false;
          _error = 'Not enough cached history yet (${candles.length} candles). '
              'Leave the app open on this asset/timeframe for a while, or '
              'wait for the 5000-candle warm-start fetch to complete, then try again.';
        });
        return;
      }

      final result = _replay(candles);
      setState(() { _running = false; _result = result; });
    } catch (e) {
      setState(() { _running = false; _error = 'Backtest failed: $e'; });
    }
  }

  _BacktestResult _replay(List<Candle> candles) {
    final state = GardenState();
    var prevSignal = 'WAIT';
    var wins = 0, losses = 0;
    final winPoints = <double>[];
    final lossPoints = <double>[];

    // Walk forward candle by candle, feeding progressively larger windows —
    // exactly what "visual backtesting" would show you scrolling through,
    // just automated and scored.
    for (var i = 40; i < candles.length - _forwardCandles; i++) {
      final window = candles.sublist(0, i + 1);
      final g = state.compute(window, _asset);
      if (g == null) continue;

      if (g.signal != 'WAIT' && prevSignal == 'WAIT') {
        // Signal just fired at this candle's close.
        final entry = candles[i].c;
        final future = candles[i + _forwardCandles].c;
        final move = future - entry;
        // BOOM=SELL only (wins on down move), CRASH=BUY only (wins on up move)
        final favorable = g.signal == 'SELL' ? move < 0 : move > 0;
        final points = move.abs();
        if (favorable) {
          wins++; winPoints.add(points);
        } else {
          losses++; lossPoints.add(points);
        }
      }
      prevSignal = g.signal;
    }

    return _BacktestResult(
      totalSignals: wins + losses,
      wins: wins,
      losses: losses,
      avgPointsWin: winPoints.isEmpty ? 0 : winPoints.reduce((a, b) => a + b) / winPoints.length,
      avgPointsLoss: lossPoints.isEmpty ? 0 : lossPoints.reduce((a, b) => a + b) / lossPoints.length,
      candlesAnalyzed: candles.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: const Text('Backtest', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // ── Asset selector ──
          const Text('Asset', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: kAssets.map((a) {
            final active = a == _asset;
            return GestureDetector(
              onTap: () => setState(() => _asset = a),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? AppColors.red : AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: active ? AppColors.red : AppColors.border),
                ),
                child: Text(shortAssetLabel(a), style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : AppColors.textDim)),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),

          // ── Timeframe selector ──
          const Text('Timeframe', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: kGranularities.keys.map((tf) {
            final active = tf == _tf;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _tf = tf),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? AppColors.red : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? AppColors.red : AppColors.border),
                  ),
                  child: Text(tf, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                      color: active ? Colors.white : AppColors.textDim)),
                ),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),

          // ── Forward window ──
          Row(children: [
            const Text('Check outcome after: ',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            DropdownButton<int>(
              value: _forwardCandles,
              items: const [3, 5, 10, 20].map((n) =>
                  DropdownMenuItem(value: n, child: Text('$n candles'))).toList(),
              onChanged: (v) => setState(() => _forwardCandles = v ?? 5),
            ),
          ]),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _running ? null : _run,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(_running ? 'RUNNING…' : 'RUN BACKTEST',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ),
          const SizedBox(height: 20),

          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),

          if (r != null) Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_asset · $_tf · ${r.candlesAnalyzed} candles analyzed',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              const SizedBox(height: 12),
              _statRow('Total signals fired', '${r.totalSignals}'),
              _statRow('Wins', '${r.wins}', color: const Color(0xFF27AE60)),
              _statRow('Losses', '${r.losses}', color: AppColors.red),
              _statRow('Win rate', '${r.winRate.toStringAsFixed(1)}%', big: true),
              const Divider(height: 24, color: AppColors.border),
              _statRow('Avg points on wins', r.avgPointsWin.toStringAsFixed(2)),
              _statRow('Avg points on losses', r.avgPointsLoss.toStringAsFixed(2)),
            ]),
          ),

          const SizedBox(height: 16),
          const Text(
            'This replays the exact live signal engine over cached candle '
            'history — the same AO/AC/Stoch counter-spike logic used on the '
            'Signals page, checked candle-by-candle. More cached history '
            'gives a more reliable result; the warm-start fetch builds this '
            'up automatically the longer you use the app.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11, height: 1.4),
          ),
        ]),
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color, bool big = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
        Text(value, style: TextStyle(
            color: color ?? AppColors.text,
            fontWeight: FontWeight.w900,
            fontSize: big ? 20 : 14)),
      ]),
    );
  }
}
