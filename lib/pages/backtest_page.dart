import 'package:flutter/material.dart';
import '../models/candle.dart';
import '../services/deriv_feed.dart';
import '../services/journal_db.dart';
import '../theme.dart';
import '../widgets/candle_chart.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BacktestPage — rewind chart
//
// Same candlestick chart as the main Signals page, sourced entirely from
// SQLite instead of the live feed — so this page never touches the network
// and can never hit Deriv's rate limit. Pinch-zoom and pan (already built
// into CandleChart) let you scrub back through history, TradingView-style.
//
// History loads lazily: it starts with the most recent ~300 candles, and
// as you pan back near the oldest one currently loaded, the next page is
// pulled from SQLite and prepended automatically. This avoids ever asking
// for "everything" in one shot.
//
// Data only exists here once it's been seen on the live Signals page —
// every candle that arrives live gets written to SQLite in the background,
// which is what this page reads from. A freshly installed app (or an
// asset you've never opened live) has nothing to rewind through yet.
// ─────────────────────────────────────────────────────────────────────────────

class BacktestPage extends StatefulWidget {
  const BacktestPage({super.key});

  @override
  State<BacktestPage> createState() => _BacktestPageState();
}

class _BacktestPageState extends State<BacktestPage> {
  String _asset = kAssets.first;
  String _tf    = '1m';

  List<Candle> _candles = [];
  bool _loading   = true;
  bool _loadingMore = false;
  bool _noMoreHistory = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _noMoreHistory = false;
      _candles = [];
    });
    final c = await JournalDb.instance.loadCandles(_asset, _tf, limit: 300);
    if (!mounted) return;
    setState(() { _candles = c; _loading = false; });
  }

  Future<void> _loadOlder() async {
    if (_loadingMore || _noMoreHistory || _candles.isEmpty) return;
    setState(() => _loadingMore = true);
    final older = await JournalDb.instance.loadCandlesBefore(
        _asset, _tf, _candles.first.epoch, limit: 300);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (older.isEmpty) {
        _noMoreHistory = true;
      } else {
        _candles = [...older, ..._candles];
      }
    });
  }

  void _pickAsset(String a) {
    setState(() => _asset = a);
    _loadInitial();
  }

  void _pickTf(String tf) {
    setState(() => _tf = tf);
    _loadInitial();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        title: const Text('Backtest — Rewind',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(children: [
          // ── Asset selector ──
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: kAssets.map((a) {
                final active = a == _asset;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => _pickAsset(a),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: active ? AppColors.red : AppColors.cardAlt,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: active ? AppColors.red : AppColors.border),
                      ),
                      child: Text(shortAssetLabel(a),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                              color: active ? Colors.white : AppColors.textDim)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),

          // ── Timeframe selector ──
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: kGranularities.keys.map((tf) {
              final active = tf == _tf;
              return GestureDetector(
                onTap: () => _pickTf(tf),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                    color: active ? AppColors.red : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: active ? AppColors.red : AppColors.border),
                  ),
                  child: Text(tf, style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.bold, letterSpacing: 1.4,
                      color: active ? Colors.white : AppColors.textDim)),
                ),
              );
            }).toList()),
          const SizedBox(height: 10),

          // ── Chart ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(color: AppColors.border)),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _candles.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No cached history for $_asset · $_tf yet.\n\n'
                                  'Open this asset on the main Signals page first — '
                                  'every live candle gets saved automatically, and '
                                  'you\'ll be able to rewind through it here.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 12, height: 1.5),
                                ),
                              ),
                            )
                          : CandleChart(
                              candles: _candles,
                              onNearStart: _loadOlder,
                            ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Status line ──
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _loadingMore
                  ? 'Loading older candles…'
                  : _candles.isEmpty
                      ? ' '
                      : _noMoreHistory
                          ? '${_candles.length} candles loaded · start of history'
                          : '${_candles.length} candles loaded · pan left to load more',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ]),
      ),
    );
  }
}
