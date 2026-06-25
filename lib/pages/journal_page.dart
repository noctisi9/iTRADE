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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _selectedDay;
  Map<String, DaySummary> _summaries = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _asset = widget.initialAsset;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await JournalDb.instance.getDaySummaries(_asset, _month.year, _month.month - 1);
    if (!mounted) return;
    setState(() {
      _summaries = s;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _selectedDay = null;
    });
    _load();
  }

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _exportDay(DateTime day) async {
    final entries = await JournalDb.instance.getEntriesForDay(_asset, day);
    final content = generateDailyCSV(entries, _asset, day);
    await shareTextFile(content, '${_asset}_${_key(day)}.txt');
  }

  Future<void> _exportWeek(DateTime anyDayInWeek) async {
    final weekday = anyDayInWeek.weekday % 7; // 0 = Sunday
    final weekStart = anyDayInWeek.subtract(Duration(days: weekday));
    final entries = await JournalDb.instance.getEntriesForWeek(_asset, weekStart);
    final content = generateWeeklyCSV(entries, _asset, weekStart);
    await shareTextFile(content, '${_asset}_week_${_key(weekStart)}.txt');
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: kAssets.map((a) {
              final active = a == _asset;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _asset = a;
                    _selectedDay = null;
                  });
                  _load();
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active ? AppColors.red : AppColors.cardAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: active ? AppColors.red : AppColors.border),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
            Text('${monthNames[_month.month - 1]} ${_month.year}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
        if (!_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
              itemCount: firstWeekday + daysInMonth,
              itemBuilder: (context, i) {
                if (i < firstWeekday) return const SizedBox.shrink();
                final day = i - firstWeekday + 1;
                final date = DateTime(_month.year, _month.month, day);
                final summary = _summaries[_key(date)];
                final selected = _selectedDay != null &&
                    _selectedDay!.year == date.year &&
                    _selectedDay!.month == date.month &&
                    _selectedDay!.day == date.day;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = date),
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
                        if (summary != null)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : AppColors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        if (_selectedDay != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedDay!.day} ${monthNames[_selectedDay!.month - 1]} ${_selectedDay!.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _summaries[_key(_selectedDay!)] != null
                        ? '${_summaries[_key(_selectedDay!)]!.count} candles logged'
                        : 'No entries logged',
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
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
              child: Text('Tap a day to view or export its journal',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          ),
      ],
    );
  }
}
