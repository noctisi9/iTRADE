import 'package:flutter/material.dart';
import '../services/csv_export.dart';
import '../services/journal_db.dart';
import '../theme.dart';

class JournalPage extends StatefulWidget {
  final String initialAsset;
  const JournalPage({super.key, required this.initialAsset});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  late String _asset;
  DateTime _month    = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay;
  Map<String, DaySummary> _summaries = {};
  List<JournalEntry> _dayEntries = [];
  bool _loading     = true;
  bool _loadingDay  = false;

  @override
  void initState() {
    super.initState();
    _asset = widget.initialAsset;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await JournalDb.instance
        .getDaySummaries(_asset, _month.year, _month.month - 1);
    if (!mounted) return;
    setState(() {
      _summaries = s;
      _loading   = false;
    });
  }

  Future<void> _loadDay(DateTime day) async {
    setState(() => _loadingDay = true);
    final entries = await JournalDb.instance.getEntriesForDay(_asset, day);
    if (!mounted) return;
    setState(() {
      _dayEntries = entries;
      _loadingDay = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month       = DateTime(_month.year, _month.month + delta, 1);
      _selectedDay = null;
      _dayEntries  = [];
    });
    _load();
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _exportDay(DateTime day) async {
    final entries = await JournalDb.instance.getEntriesForDay(_asset, day);
    final content = generateDailyCSV(entries, _asset, day);
    await shareTextFile(content, '${_asset}_${_key(day)}.txt');
  }

  Future<void> _exportWeek(DateTime anyDayInWeek) async {
    final weekday  = anyDayInWeek.weekday % 7;
    final weekStart = anyDayInWeek.subtract(Duration(days: weekday));
    final entries  = await JournalDb.instance.getEntriesForWeek(_asset, weekStart);
    final content  = generateWeeklyCSV(entries, _asset, weekStart);
    await shareTextFile(content, '${_asset}_week_${_key(weekStart)}.txt');
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday  = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMonth   = DateTime(_month.year, _month.month + 1, 0).day;
    const monthNames    = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Column(
      children: [
        // ── Asset tabs ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: kAssets.map((a) {
              final active = a == _asset;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _asset       = a;
                    _selectedDay = null;
                    _dayEntries  = [];
                  });
                  _load();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? AppColors.red : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: active ? AppColors.red : AppColors.border),
                  ),
                  child: Text(shortAssetLabel(a),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: active ? Colors.white : AppColors.textDim)),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Month nav ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left)),
            Text('${monthNames[_month.month - 1]} ${_month.year}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right)),
          ],
        ),

        // ── Calendar grid ──
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator()),
        if (!_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
              itemCount: firstWeekday + daysInMonth,
              itemBuilder: (context, i) {
                if (i < firstWeekday) return const SizedBox.shrink();
                final day  = i - firstWeekday + 1;
                final date = DateTime(_month.year, _month.month, day);
                final summary = _summaries[_key(date)];
                final selected = _selectedDay != null &&
                    _selectedDay!.year  == date.year &&
                    _selectedDay!.month == date.month &&
                    _selectedDay!.day   == date.day;

                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedDay = date);
                    _loadDay(date);
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.red : AppColors.cardAlt,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('$day',
                            style: TextStyle(
                                fontSize: 12,
                                color: selected ? Colors.white : AppColors.text)),
                        if (summary != null) ...[
                          Container(
                            margin: const EdgeInsets.only(top: 1),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : AppColors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          // Avg risk indicator
                          Text(
                            '${summary.avgRisk}%',
                            style: TextStyle(
                              fontSize: 7,
                              color: selected
                                  ? Colors.white70
                                  : _riskColor(summary.avgRisk),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 10),

        // ── Day detail ──
        if (_selectedDay != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedDay!.day} ${monthNames[_selectedDay!.month - 1]} ${_selectedDay!.year}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _summaries[_key(_selectedDay!)] != null
                        ? '${_summaries[_key(_selectedDay!)]!.count} candles logged'
                        : 'No entries logged',
                    style: const TextStyle(
                        color: AppColors.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Candle list with Garden data
                  if (_loadingDay)
                    const Center(child: CircularProgressIndicator())
                  else
                    Expanded(
                      child: _dayEntries.isEmpty
                          ? const Center(
                              child: Text('No entries',
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12)))
                          : ListView.builder(
                              itemCount: _dayEntries.length,
                              itemBuilder: (context, i) {
                                final e = _dayEntries[i];
                                return _CandleRow(entry: e);
                              },
                            ),
                    ),

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _exportDay(_selectedDay!),
                          child: const Text('Export Day'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _exportWeek(_selectedDay!),
                          child: const Text('Export Week'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else
          const Expanded(
            child: Center(
              child: Text('Tap a day to view its journal',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12)),
            ),
          ),
      ],
    );
  }

  Color _riskColor(int pct) {
    if (pct < 33) return const Color(0xFF27AE60);
    if (pct < 66) return const Color(0xFFE67E22);
    return AppColors.red;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual candle row — shows OHLC + Garden indicators
// ─────────────────────────────────────────────────────────────────────────────
class _CandleRow extends StatelessWidget {
  final JournalEntry entry;
  const _CandleRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(
        entry.epoch * 1000, isUtc: true);
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final isBull = entry.close >= entry.open;
    final signalColor = entry.signal == 'BUY'
        ? const Color(0xFF27AE60)
        : entry.signal == 'SELL'
            ? AppColors.red
            : AppColors.textMuted;
    final riskColor = entry.riskPct < 33
        ? const Color(0xFF27AE60)
        : entry.riskPct < 66
            ? const Color(0xFFE67E22)
            : AppColors.red;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: time + signal + risk ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(hhmm,
                  style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDim)),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: signalColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(entry.signal,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: signalColor)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${entry.riskPct}% RISK',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: riskColor)),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 5),
          // ── OHLC ──
          Text(
            'O ${entry.open.toStringAsFixed(3)}  '
            'H ${entry.high.toStringAsFixed(3)}  '
            'L ${entry.low.toStringAsFixed(3)}  '
            'C ${entry.close.toStringAsFixed(3)}',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: isBull
                  ? const Color(0xFF27AE60)
                  : AppColors.red,
            ),
          ),
          const SizedBox(height: 4),
          // ── Garden indicators ──
          Row(
            children: [
              _chip('AO ${entry.ao >= 0 ? '+' : ''}${entry.ao.toStringAsFixed(3)}',
                  entry.ao >= 0
                      ? const Color(0xFF33D8FF)
                      : AppColors.red),
              const SizedBox(width: 6),
              _chip('AC ${entry.ac >= 0 ? '+' : ''}${entry.ac.toStringAsFixed(3)}',
                  entry.ac >= 0
                      ? const Color(0xFFD763FF)
                      : AppColors.red),
              const SizedBox(width: 6),
              _chip('K ${entry.stochK.toStringAsFixed(1)}',
                  entry.stochK > 80
                      ? AppColors.red
                      : entry.stochK < 20
                          ? const Color(0xFF47F05F)
                          : AppColors.textDim),
              const SizedBox(width: 6),
              _chip(
                  'MMM ${entry.mmmDelta >= 0 ? '+' : ''}${entry.mmmDelta.toStringAsFixed(4)}',
                  entry.mmmDelta < 0 ? AppColors.red : const Color(0xFF47F05F)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.bold)),
    );
  }
}
