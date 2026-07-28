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
  SessionStats _stats = SessionStats.empty;
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
    final s     = await JournalDb.instance.getSessions(asset: _asset, tf: _tf);
    final stats = await JournalDb.instance.getSessionStats(asset: _asset, tf: _tf);
    if (!mounted) return;
    setState(() { _sessions = s; _stats = stats; _loading = false; });
  }

  Future<void> _openTagSheet(SignalSession s) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TagTradeSheet(session: s),
    );
    if (saved == true) _load();
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

      // ── Session stats header ──
      if (!_loading && _sessions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _StatsHeader(stats: _stats),
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
            itemBuilder: (_, i) => _SessionCard(
                session: _sessions[i],
                onTagTap: () => _openTagSheet(_sessions[i])),
          ),
        ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session stats header — win rate, streaks, averages
// ─────────────────────────────────────────────────────────────────────────────
class _StatsHeader extends StatelessWidget {
  final SessionStats stats;
  const _StatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final streakLabel = s.currentStreak == 0 ? '—'
        : s.currentStreak > 0 ? '${s.currentStreak}W streak'
        : '${-s.currentStreak}L streak';
    final streakColor = s.currentStreak > 0
        ? const Color(0xFF27AE60)
        : s.currentStreak < 0 ? AppColors.red : AppColors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _stat('WIN RATE', '${s.winRatePct.toStringAsFixed(0)}%',
            color: s.winRatePct >= 50 ? const Color(0xFF27AE60) : AppColors.red),
        _stat('AVG PTS', s.avgPoints.toStringAsFixed(2)),
        _stat('BEST', '\$${s.bestSessionPnl.toStringAsFixed(2)}',
            color: const Color(0xFF27AE60)),
        _stat('WORST', '\$${s.worstSessionPnl.toStringAsFixed(2)}',
            color: AppColors.red),
        _stat('STREAK', streakLabel, color: streakColor),
      ]),
    );
  }

  Widget _stat(String label, String val, {Color? color}) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 8,
          color: AppColors.textMuted, letterSpacing: 0.6)),
      const SizedBox(height: 2),
      Text(val, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
          color: color ?? AppColors.text)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session card — clean, professional, structured
// ─────────────────────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  final SignalSession session;
  final VoidCallback onTagTap;
  const _SessionCard({required this.session, required this.onTagTap});

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
    final pnl       = s.actualPnl;
    final pnlPositive = pnl > 0;
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
                      Text(s.tagged ? 'ACTUAL P&L' : 'EST. P&L',
                          style: const TextStyle(fontSize: 9,
                          color: AppColors.textMuted, letterSpacing: 1)),
                      Text(s.tagged
                              ? '${s.actualLot!.toStringAsFixed(2)} lot · your numbers'
                              : '0.20 lot · \$0.50/pt',
                          style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
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
            const SizedBox(height: 10),

            // Manual trade tagging
            GestureDetector(
              onTap: onTagTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(s.tagged ? Icons.edit_note_rounded : Icons.add_circle_outline_rounded,
                      size: 14, color: AppColors.textDim),
                  const SizedBox(width: 6),
                  Text(s.tagged ? 'Edit actual trade details' : 'Tag your actual trade',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: AppColors.textDim)),
                ]),
              ),
            ),
            if (s.tagged && (s.notes?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              Text('"${s.notes}"',
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic,
                      color: AppColors.textMuted)),
            ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Manual trade tagging sheet — actual entry/exit/lot/notes, real P&L
// ─────────────────────────────────────────────────────────────────────────────
class _TagTradeSheet extends StatefulWidget {
  final SignalSession session;
  const _TagTradeSheet({required this.session});

  @override
  State<_TagTradeSheet> createState() => _TagTradeSheetState();
}

class _TagTradeSheetState extends State<_TagTradeSheet> {
  late final TextEditingController _entryCtrl;
  late final TextEditingController _exitCtrl;
  late final TextEditingController _lotCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _entryCtrl = TextEditingController(
        text: (s.actualEntry ?? s.entryPrice).toStringAsFixed(3));
    _exitCtrl  = TextEditingController(
        text: (s.actualExit ?? s.exitPrice).toStringAsFixed(3));
    _lotCtrl   = TextEditingController(text: (s.actualLot ?? 0.20).toStringAsFixed(2));
    _notesCtrl = TextEditingController(text: s.notes ?? '');
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _exitCtrl.dispose();
    _lotCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final entry = double.tryParse(_entryCtrl.text);
    final exit  = double.tryParse(_exitCtrl.text);
    final lot   = double.tryParse(_lotCtrl.text);
    if (entry == null || exit == null || lot == null || widget.session.id == null) return;

    setState(() => _saving = true);
    await JournalDb.instance.tagSession(
      widget.session.id!,
      actualEntry: entry, actualExit: exit, actualLot: lot,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Tag your actual trade',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                  color: AppColors.text)),
          const SizedBox(height: 4),
          Text('${widget.session.asset} · ${widget.session.signal}',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 16),

          _numField('Actual entry price', _entryCtrl),
          const SizedBox(height: 10),
          _numField('Actual exit price', _exitCtrl),
          const SizedBox(height: 10),
          _numField('Actual lot size', _lotCtrl),
          const SizedBox(height: 10),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Notes (optional)',
              labelStyle: const TextStyle(color: AppColors.textMuted),
              filled: true, fillColor: AppColors.cardAlt,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: Text(_saving ? 'SAVING…' : 'SAVE',
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        filled: true, fillColor: AppColors.cardAlt,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.red)),
      ),
    );
  }
}
