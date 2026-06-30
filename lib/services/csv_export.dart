import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'journal_db.dart';

String _pad(int n) => n.toString().padLeft(2, '0');

String _hhmm(int epoch) {
  final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
  return '${_pad(d.hour)}:${_pad(d.minute)}';
}

const _months = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
];

String _longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _aoTag(double v) {
  if (v >  0.5) return 'BULLISH_GROWTH';
  if (v >  0)   return 'BULLISH';
  if (v < -0.5) return 'BEARISH_GROWTH';
  return 'BEARISH';
}

String _acTag(double v) {
  if (v >  0.05) return 'ACCELERATION_START';
  if (v >  0)    return 'MILD_ACCEL';
  if (v < -0.05) return 'DECELERATION';
  return 'FLAT';
}

List<String> _buildSequenceLines(List<JournalEntry> entries) {
  final lines = <String>[];
  for (final e in entries) {
    final o = e.open.toStringAsFixed(5);
    final c = e.close.toStringAsFixed(5);
    final t = _hhmm(e.epoch);
    final spikeTag = e.spike ? '  [SPIKE]' : '';
    lines.add('CANDLE ${e.candleNum} FORMED $o TO $c   {TIME:$t}$spikeTag');
    lines.add('');
  }
  return lines;
}

List<String> _buildIndicatorLines(List<JournalEntry> entries) {
  final lines = <String>[
    '',
    '==================== INDICATOR DATA ====================',
    ''
  ];
  for (final e in entries) {
    final t      = _hhmm(e.epoch);
    final aoStr  = '${e.ao >= 0 ? '+' : ''}${e.ao.toStringAsFixed(5)}';
    final acStr  = '${e.ac >= 0 ? '+' : ''}${e.ac.toStringAsFixed(5)}';
    lines.add('[$t] CANDLE ${e.candleNum}  |  movement: ${e.movement.toStringAsFixed(5)}');
    lines.add('        AO: $aoStr [${_aoTag(e.ao)}]  |  AC: $acStr [${_acTag(e.ac)}]');
    lines.add('        Stoch K: ${e.stochK.toStringAsFixed(2)} [${e.stochLabel}]  |  '
        '${e.timeframe.toUpperCase()} 4th node: ${e.mmmDelta.toStringAsFixed(6)} [${e.mmmDir}]');
    lines.add('        Risk Score: ${e.riskPct}%  |  Signal: ${e.signal}  |  '
        'Candles since spike: ${e.candlesSinceSpike}');
    lines.add('');
  }
  return lines;
}

String generateDailyCSV(
    List<JournalEntry> entries, String asset, String tf, DateTime date) {
  final timeStr = entries.isNotEmpty ? _hhmm(entries.first.epoch) : '--:--';
  final head = [
    asset, tf.toUpperCase(), '',
    'DATE: ${_longDate(date)}', '',
    'TIME: $timeStr', '', ''
  ];
  return [
    ...head,
    ..._buildSequenceLines(entries),
    ..._buildIndicatorLines(entries),
  ].join('\n');
}

String generateWeeklyCSV(
    List<JournalEntry> entries, String asset, String tf, DateTime weekStart) {
  final byDay = <String, List<JournalEntry>>{};
  for (final e in entries) {
    final d   = DateTime.fromMillisecondsSinceEpoch(e.epoch * 1000, isUtc: true);
    final key = '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
    byDay.putIfAbsent(key, () => []).add(e);
  }
  final lines = <String>[asset, tf.toUpperCase(), '', 'WEEK OF: ${_longDate(weekStart)}', ''];
  final keys  = byDay.keys.toList()..sort();
  for (final day in keys) {
    final dayEntries = byDay[day]!;
    final dDate      = DateTime.parse(day);
    lines.add('========== ${_longDate(dDate)} ==========');
    lines.add('');
    lines.addAll(_buildSequenceLines(dayEntries));
    lines.addAll(_buildIndicatorLines(dayEntries));
    lines.add('');
  }
  return lines.join('\n');
}

Future<void> shareTextFile(String content, String filename) async {
  final dir  = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
  await Share.shareXFiles([XFile(file.path)], text: filename);
}
