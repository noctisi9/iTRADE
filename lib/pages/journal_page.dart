import 'package:flutter/material.dart';
import '../services/csv_export.dart';
import '../services/journal_db.dart';
import '../services/deriv_feed.dart';
import '../theme.dart';

class JournalPage extends StatefulWidget {
  final String initialAsset;
  final String initialTf;
  const JournalPage(
      {super.key, required this.initialAsset, required this.initialTf});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  late String _asset;
  late String _tf;
  DateTime _month    = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selDay;
  Map<String, DaySummary> _sums    = {};
  List<JournalEntry>      _entries = [];
  bool _loading    = true;
  bool _loadingDay = false;

  @override
  void initState() {
    super.initState();
    _asset = widget.initialAsset;
    _tf    = widget.initialTf;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await JournalDb.instance.getDaySummaries(
        _asset, _tf, _month.year, _month.month);
    if (!mounted) return;
    setState(() { _sums = s; _loading = false; });
  }

  Future<void> _loadDay(DateTime day) async {
    setState(() => _loadingDay = true);
    final e = await JournalDb.instance.getEntriesForDay(_asset, _tf, day);
    if (!mounted) return;
    setState(() { _entries = e; _loadingDay = false; });
  }

  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  static const _months = [
    'January','February','March','April','May','June',
    'July','August','September','October','November','December'
  ];

  @override
  Widget build(BuildContext context) {
    final firstWd    = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMon  = DateTime(_month.year, _month.month + 1, 0).day;

    return Column(children: [
      // ── Asset + TF selectors ──
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Column(children: [
          // Asset tabs
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: kAssets.map((a) {
              final on = a == _asset;
              return GestureDetector(
                onTap: () { setState(() { _asset = a; _selDay = null; _entries = []; }); _load(); },
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
          // TF tabs
          Row(mainAxisAlignment: MainAxisAlignment.center,
            children: kGranularities.keys.map((tf) {
              final on = tf == _tf;
              return GestureDetector(
                onTap: () { setState(() { _tf = tf; _selDay = null; _entries = []; }); _load(); },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  decoration: BoxDecoration(
                    color: on ? AppColors.red.withValues(alpha: 0.1) : Colors.transparent,
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

      // ── Month navigation ──
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(onPressed: () { setState(() { _month = DateTime(_month.year, _month.month - 1, 1); _selDay = null; _entries = []; }); _load(); },
            icon: const Icon(Icons.chevron_left)),
        Text('${_months[_month.month - 1]} ${_month.year}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        IconButton(onPressed: () { setState(() { _month = DateTime(_month.year, _month.month + 1, 1); _selDay = null; _entries = []; }); _load(); },
            icon: const Icon(Icons.chevron_right)),
      ]),

      // ── Calendar grid ──
      if (_loading)
        const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
      if (!_loading)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
            itemCount: firstWd + daysInMon,
            itemBuilder: (_, i) {
              if (i < firstWd) return const SizedBox.shrink();
              final day  = i - firstWd + 1;
              final date = DateTime(_month.year, _month.month, day);
              final sum  = _sums[_key(date)];
              final sel  = _selDay != null && _selDay!.day == date.day &&
                  _selDay!.month == date.month && _selDay!.year == date.year;
              return GestureDetector(
                onTap: () { setState(() => _selDay = date); _loadDay(date); },
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.red : AppColors.cardAlt,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$day', style: TextStyle(fontSize: 11,
                        color: sel ? Colors.white : AppColors.text)),
                    if (sum != null) ...[
                      Container(width: 4, height: 4, margin: const EdgeInsets.only(top: 1),
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: sel ? Colors.white : _riskColor(sum.avgRisk))),
                      Text('${sum.avgRisk}%', style: TextStyle(fontSize: 7,
                          color: sel ? Colors.white70 : _riskColor(sum.avgRisk))),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 8),

      // ── Day detail ──
      if (_selDay != null)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${_selDay!.day} ${_months[_selDay!.month - 1]} ${_selDay!.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${_entries.length} candles  |  $_asset  |  $_tf',
                    style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
              ]),
              const SizedBox(height: 8),

              if (_loadingDay) const Center(child: CircularProgressIndicator())
              else if (_entries.isEmpty)
                const Center(child: Text('No entries logged for this day.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (_, i) => _CandleCard(entry: _entries[i],
                        isVix: isVix(_asset)),
                  ),
                ),

              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton(
                    onPressed: () async {
                      final e = await JournalDb.instance
                          .getEntriesForDay(_asset, _tf, _selDay!);
                      final txt = generateDailyCSV(e, _asset, _tf, _selDay!);
                      shareTextFile(txt, '${_asset}_${_tf}_${_key(_selDay!)}.txt');
                    },
                    child: const Text('Export Day'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(
                    onPressed: () async {
                      final wd = _selDay!.weekday % 7;
                      final ws = _selDay!.subtract(Duration(days: wd));
                      final e  = await JournalDb.instance
                          .getEntriesForWeek(_asset, _tf, ws);
                      final txt = generateWeeklyCSV(e, _asset, _tf, ws);
                      shareTextFile(txt, '${_asset}_${_tf}_week_${_key(ws)}.txt');
                    },
                    child: const Text('Export Week'))),
              ]),
            ]),
          ),
        )
      else
        const Expanded(child: Center(child: Text('Tap a day to view candles',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12)))),
    ]);
  }

  Color _riskColor(int p) =>
      p < 33 ? const Color(0xFF27AE60) : p < 66 ? const Color(0xFFE67E22) : AppColors.red;
}

// ─────────────────────────────────────────────────────────────────────────────
// Single candle card — full data, clean layout
// ─────────────────────────────────────────────────────────────────────────────
class _CandleCard extends StatelessWidget {
  final JournalEntry entry;
  final bool isVix;
  const _CandleCard({required this.entry, required this.isVix});

  @override
  Widget build(BuildContext context) {
    final d = DateTime.fromMillisecondsSinceEpoch(
        entry.epoch * 1000, isUtc: true);
    final hhmm = '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    final bull = entry.close >= entry.open;
    final sigColor = entry.signal == 'BUY'
        ? const Color(0xFF27AE60)
        : entry.signal == 'SELL' ? AppColors.red : AppColors.textMuted;
    final riskColor = entry.riskPct < 33
        ? const Color(0xFF27AE60)
        : entry.riskPct < 66 ? const Color(0xFFE67E22) : AppColors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Row 1: candle number + time + spike badge + signal + risk ──
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.cardAlt,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border)),
            child: Text('C${entry.candleNum}', style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold,
                fontFamily: 'monospace', color: AppColors.textDim)),
          ),
          const SizedBox(width: 6),
          Text(hhmm, style: const TextStyle(fontSize: 11,
              fontFamily: 'monospace', color: AppColors.textDim)),
          if (entry.spike) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.redFaint,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('SPIKE', style: TextStyle(fontSize: 9,
                  fontWeight: FontWeight.bold, color: AppColors.red)),
            ),
          ],
          const Spacer(),
          // Signal pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: sigColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(6)),
            child: Text(entry.signal, style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.bold, color: sigColor)),
          ),
          const SizedBox(width: 6),
          // Risk pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6)),
            child: Text('${entry.riskPct}%', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.bold, fontFamily: 'monospace',
                color: riskColor)),
          ),
        ]),
        const SizedBox(height: 6),

        // ── Row 2: OHLC ──
        Row(children: [
          _ohlcItem('O', entry.open, AppColors.textDim),
          const SizedBox(width: 10),
          _ohlcItem('H', entry.high, const Color(0xFF27AE60)),
          const SizedBox(width: 10),
          _ohlcItem('L', entry.low,  AppColors.red),
          const SizedBox(width: 10),
          _ohlcItem('C', entry.close, bull ? const Color(0xFF27AE60) : AppColors.red),
          const Spacer(),
          Text(
            '${bull ? '▲' : '▼'} ${entry.movement.abs().toStringAsFixed(3)}',
            style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: bull ? const Color(0xFF27AE60) : AppColors.red),
          ),
        ]),
        const SizedBox(height: 6),

        // ── Row 3: Indicators ──
        Wrap(spacing: 6, runSpacing: 4, children: [
          _indChip('AO', entry.ao >= 0
              ? '+${entry.ao.toStringAsFixed(4)}' : entry.ao.toStringAsFixed(4),
              entry.ao >= 0 ? const Color(0xFF33D8FF) : AppColors.red),
          _indChip('AC', entry.ac >= 0
              ? '+${entry.ac.toStringAsFixed(4)}' : entry.ac.toStringAsFixed(4),
              entry.ac >= 0 ? const Color(0xFFD763FF) : AppColors.red),
          _indChip('STOCH ${entry.stochK.toStringAsFixed(1)}',
              entry.stochLabel,
              entry.stochLabel == 'OVERBOUGHT'
                  ? AppColors.red
                  : entry.stochLabel == 'OVERSOLD'
                  ? const Color(0xFF47F05F) : AppColors.textMuted),
          _indChip(isVix ? 'MA CROSS' : 'MINIMAX',
              '${entry.mmmDelta >= 0 ? '+' : ''}${entry.mmmDelta.toStringAsFixed(5)}  ${entry.mmmDir}',
              entry.mmmDir == 'BEARISH' ? AppColors.red : const Color(0xFF47F05F)),
          if (!isVix)
            _indChip('SPIKE#', '${entry.candlesSinceSpike}c', AppColors.textDim),
        ]),
      ]),
    );
  }

  Widget _ohlcItem(String label, double val, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
      Text(val.toStringAsFixed(3), style: TextStyle(fontSize: 10,
          fontFamily: 'monospace', fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _indChip(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.20))),
      child: RichText(text: TextSpan(children: [
        TextSpan(text: '$label: ', style: TextStyle(fontSize: 9,
            color: AppColors.textMuted, fontFamily: 'monospace')),
        TextSpan(text: val, style: TextStyle(fontSize: 9,
            fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace')),
      ])),
    );
  }
}
