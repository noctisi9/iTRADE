import 'package:flutter/material.dart';
import '../services/journal_db.dart';
import '../theme.dart';

class _TradeRun {
  final String direction; // BUY | SELL
  final DateTime start, end;
  final double entry, exit;
  final int candleCount;
  _TradeRun({
    required this.direction,
    required this.start,
    required this.end,
    required this.entry,
    required this.exit,
    required this.candleCount,
  });
}

class HistoryPage extends StatefulWidget {
  final String initialAsset;
  const HistoryPage({super.key, required this.initialAsset});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late String _asset;
  bool _loading = true;
  List<_TradeRun> _runs = [];

  @override
  void initState() {
    super.initState();
    _asset = widget.initialAsset;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final entries = <JournalEntry>[];
    for (var i = 0; i < 5; i++) {
      final day = now.subtract(Duration(days: i));
      entries.addAll(await JournalDb.instance.getEntriesForDay(_asset, day));
    }
    entries.sort((a, b) => a.epoch.compareTo(b.epoch));

    final runs = <_TradeRun>[];
    String? dir;
    List<JournalEntry> buf = [];
    void flush() {
      if (dir != null && buf.length >= 3) {
        runs.add(_TradeRun(
          direction: dir,
          start: DateTime.fromMillisecondsSinceEpoch(buf.first.epoch * 1000),
          end: DateTime.fromMillisecondsSinceEpoch(buf.last.epoch * 1000),
          entry: buf.first.open,
          exit: buf.last.close,
          candleCount: buf.length,
        ));
      }
      buf = [];
    }

    for (final e in entries) {
      if (e.spike) {
        flush();
        dir = null;
        continue;
      }
      final d = (e.ao > 0 && e.ac > 0) ? 'BUY' : (e.ao < 0 && e.ac < 0) ? 'SELL' : null;
      if (d == null) {
        flush();
        dir = null;
        continue;
      }
      if (dir != d) {
        flush();
        dir = d;
      }
      buf.add(e);
    }
    flush();
    runs.sort((a, b) => b.end.compareTo(a.end));

    if (!mounted) return;
    setState(() {
      _runs = runs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  setState(() => _asset = a);
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
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _runs.isEmpty
                  ? const Center(
                      child: Text('No clear trend runs detected in the last 5 days',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 12)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _runs.length,
                      itemBuilder: (context, i) {
                        final r = _runs[i];
                        final move = r.exit - r.entry;
                        final win = (r.direction == 'BUY' && move > 0) || (r.direction == 'SELL' && move < 0);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: r.direction == 'BUY' ? AppColors.black : AppColors.red,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(r.direction,
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${r.candleCount} candles',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textDim)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${r.entry.toStringAsFixed(3)} → ${r.exit.toStringAsFixed(3)}',
                                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                                  ),
                                  Text(
                                    '${r.start.hour.toString().padLeft(2, '0')}:${r.start.minute.toString().padLeft(2, '0')}'
                                    ' – ${r.end.hour.toString().padLeft(2, '0')}:${r.end.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                              Icon(
                                win ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                color: win ? AppColors.black : AppColors.red,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
