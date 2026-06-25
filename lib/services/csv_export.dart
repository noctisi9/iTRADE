import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'journal_db.dart';

String _pad(int n) => n.toString().padLeft(2, '0');

String _hhmm(int epoch) {
  final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  return '${_pad(d.hour)}:${_pad(d.minute)}';
}

const _months = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
];

String _longDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _aoTag(double v) {
  if (v > 0.5) return 'BULLISH_GROWTH';
  if (v > 0) return 'BULLISH';
  if (v < -0.5) return 'BEARISH_GROWTH';
  return 'BEARISH';
}

String _acTag(double v) {
  if (v > 0.05) return 'ACCELERATION_START';
  if (v > 0) return 'MILD_ACCEL';
  if (v < -0.05) return 'DECELERATION';
  return 'FLAT';
}

List<String> _buildSequenceLines(List<JournalEntry> entries) {
  final lines = <String>[];
  var n = 0;
  for (final e in entries) {
    final o = e.open.toStringAsFixed(5);
    final c = e.close.toStringAsFixed(5);
    final t = _hhmm(e.epoch);
    if (e.spike) {
      lines.add('SPIKE OCCURRED FROM $o TO $c   {TIME:$t}');
      lines.add('');
      n = 0;
      continue;
    }
    n += 1;
    lines.add(n == 1
        ? 'A CANDLE FORMED $o TO $c   {TIME:$t}'
        : 'CANDLE $n FORMED $o TO $c   {TIME:$t}');
    lines.add('');
  }
  return lines;
}

List<String> _buildIndicatorLines(List<JournalEntry> entries) {
  final lines = <String>['', '==================== INDICATOR DATA ====================', ''];
  var n = 0;
  for (final e in entries) {
    final t = _hhmm(e.epoch);
    final spread = (e.highLowSpread ?? (e.high - e.low).abs()).toStringAsFixed(5);
    final aoStr = '${e.ao >= 0 ? '+' : ''}${e.ao.toStringAsFixed(5)}';
    final acStr = '${e.ac >= 0 ? '+' : ''}${e.ac.toStringAsFixed(5)}';
    final cusumLine =
        '        CUSUM S_H: ${(e.cusumH ?? 0).toStringAsFixed(5)} / H: ${(e.cusumThreshold ?? 0).toStringAsFixed(5)} | Survival: ${((e.survivalProb ?? 1) * 100).toStringAsFixed(2)}%';
    if (e.spike) {
      lines.add('[$t] SPIKE | bars-since-prev: ${e.candlesSinceSpike} | spread: $spread');
      lines.add('        AO: $aoStr [${_aoTag(e.ao)}] | AC: $acStr [${_acTag(e.ac)}]');
      lines.add(cusumLine);
      lines.add('');
      n = 0;
      continue;
    }
    n += 1;
    final label = n == 1 ? 'CANDLE 1' : 'CANDLE $n';
    lines.add('[$t] $label | seq: ${e.candlesSinceSpike} | spread: $spread | ticks: ${e.tickVolume ?? 0}');
    lines.add('        AO: $aoStr [${_aoTag(e.ao)}] | AC: $acStr [${_acTag(e.ac)}]');
    lines.add(cusumLine);
    lines.add('');
  }
  return lines;
}

String generateDailyCSV(List<JournalEntry> entries, String asset, DateTime date) {
  final timeStr = entries.isNotEmpty ? _hhmm(entries.first.epoch) : '--:--';
  final head = [asset, '', 'DATE: ${_longDate(date)}', '', 'TIME: $timeStr', '', ''];
  return [...head, ..._buildSequenceLines(entries), ..._buildIndicatorLines(entries)].join('\n');
}

String generateWeeklyCSV(List<JournalEntry> entries, String asset, DateTime weekStart) {
  final byDay = <String, List<JournalEntry>>{};
  for (final e in entries) {
    final d = DateTime.fromMillisecondsSinceEpoch(e.epoch * 1000);
    final key = '${d.year}-${_pad(d.month)}-${_pad(d.day)}';
    byDay.putIfAbsent(key, () => []).add(e);
  }
  final lines = <String>[asset, '', 'WEEK OF: ${_longDate(weekStart)}', ''];
  final keys = byDay.keys.toList()..sort();
  for (final day in keys) {
    final dayEntries = byDay[day]!;
    final dDate = DateTime.parse(day);
    lines.add('========== ${_longDate(dDate)} ==========');
    lines.add('');
    lines.addAll(_buildSequenceLines(dayEntries));
    lines.addAll(_buildIndicatorLines(dayEntries));
    lines.add('');
  }
  return lines.join('\n');
}

/// Writes [content] to a temp .txt file and opens the Android share sheet,
/// matching the web app's "download" behaviour.
Future<void> shareTextFile(String content, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
  await Share.shareXFiles([XFile(file.path)], text: filename);
}
