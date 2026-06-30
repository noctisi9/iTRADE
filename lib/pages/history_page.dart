import 'package:flutter/material.dart';
import '../services/deriv_feed.dart';
import '../services/journal_db.dart';
import '../theme.dart';

class HistoryPage extends StatefulWidget {
  final String initialAsset;
  final String initialTf;
  const HistoryPage(
      {super.key, required this.initialAsset, required this.initialTf});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late String _asset;
  late String _tf;
  List<SignalSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _asset = widget.initialAsset;
    _tf    = widget.initialTf;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await JournalDb.instance.getSessions(asset: _asset, tf: _tf);
    if (!mounted) return;
    setState(() { _sessions = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Filters ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Column(children: [
          // Asset
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: kAssets.map((a) {
              final on = a == _asset;
              return GestureDetector(
                onTap: () { setState(() { _asset = a; }); _load(); },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: on ? AppColors.red : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? AppColors.red : AppColors.border),
                  ),
                  child: Text(shortAssetLabel(a), style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: on ? Colors.white : AppColors.textDim)),
                ),
              );
            }).toList(),
          ),
          // TF
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: kGranularities.keys.map((tf) {
              final on = tf == _tf;
              return GestureDetector(
                onTap: () { setState(() { _tf = tf; }); _load(); },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: on ? AppColors.red.withValues(alpha: 0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: on ? AppColors.red : AppColors.border),
                  ),
                  child: Text(tf, style: TextStyle(fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: on ? AppColors.red : AppColors.textMuted)),
                ),
              );
            }).toList(),
          ),
        ]),
      ),

      // ── Content ──
      if (_loading)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (_sessions.isEmpty)
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history_rounded, size: 48, color: AppColors.border),
              const SizedBox(height: 12),
              Text('No completed signals yet for $_asset / $_tf',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              const Text('Sessions are recorded when a signal opens and closes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            itemCount: _sessions.length,
            itemBuilder: (_, i) => _SessionCard(session: _sessions[i]),
          ),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session card — clean, professional, structured
// ─────────────────────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final SignalSession session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final s        = session;
    final isBuy    = s.signal == 'BUY';
    final sigColor = isBuy ? const Color(0xFF27AE60) : AppColors.red;
    final sigBg    = isBuy
        ? const Color(0xFF27AE60).withValues(alpha: 0.08)
        : AppColors.redFaint;

    final openTime  = _hhmm(s.openEpoch);
    final closeTime = _hhmm(s.closeEpoch);
    final pnl       = s.estimatedPnl;
    final pnlPositive = isBuy
        ? s.exitPrice > s.entryPrice
        : s.exitPrice < s.entryPrice;
    final pnlColor = pnlPositive
        ? const Color(0xFF27AE60) : AppColors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header bar ──
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: AppColors.cardAlt,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16))),
          child: Row(children: [
            // Signal badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: sigBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sigColor.withValues(alpha: 0.30))),
              child: Text(s.signal, style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.bold, color: sigColor,
                  letterSpacing: 1)),
            ),
            const SizedBox(width: 10),
            Text(s.asset, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.bold, color: AppColors.text)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: AppColors.border.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(s.timeframe, style: const TextStyle(fontSize: 10,
                  fontWeight: FontWeight.bold, color: AppColors.textDim)),
            ),
            const Spacer(),
            // Duration
            Text(s.durationStr, style: const TextStyle(fontSize: 12,
                fontFamily: 'monospace', color: AppColors.textDim)),
          ]),
        ),

        // ── Body ──
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(children: [

            // Time row
            _row(
              left: _labeledVal('Entry Time', openTime),
              right: _labeledVal('Exit Time', closeTime),
            ),
            const SizedBox(height: 10),

            // Price row
            _row(
              left: _labeledVal('Entry Price',
                  s.entryPrice.toStringAsFixed(3)),
              right: _labeledVal('Exit Price',
                  s.exitPrice.toStringAsFixed(3)),
            ),
            const SizedBox(height: 10),

            // Point move + candles
            _row(
              left: _labeledVal('Point Move',
                  s.pointMove.toStringAsFixed(3)),
              right: _labeledVal('Candles Held',
                  '${s.candlesHeld}'),
            ),
            const SizedBox(height: 10),

            // P&L
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: pnlColor.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: pnlColor.withValues(alpha: 0.20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('EST. P&L', style: TextStyle(fontSize: 9,
                          color: AppColors.textMuted, letterSpacing: 1)),
                      const Text('0.20 lot · \$0.50/pt',
                          style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
                    ]),
                  Text(
                    '${pnlPositive ? '+' : ''}\$${pnl.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                        color: pnlColor),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('PEAK RISK', style: TextStyle(fontSize: 9,
                          color: AppColors.textMuted, letterSpacing: 1)),
                      Text('${s.peakScore}%', style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.bold, color: AppColors.red)),
                    ]),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _row({required Widget left, required Widget right}) {
    return Row(children: [
      Expanded(child: left),
      const SizedBox(width: 10),
      Expanded(child: right),
    ]);
  }

  Widget _labeledVal(String label, String val) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 9,
          letterSpacing: 0.8, color: AppColors.textMuted)),
      const SizedBox(height: 2),
      Text(val, style: const TextStyle(fontSize: 13,
          fontWeight: FontWeight.bold, fontFamily: 'monospace',
          color: AppColors.text)),
    ]);
  }

  String _hhmm(int epoch) {
    final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')} UTC';
  }
}
