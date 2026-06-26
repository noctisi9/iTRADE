import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JournalEntry — v2 schema
// Old spike / CUSUM columns removed. Garden of Swords fields added.
// riskPct = composite Garden score at time of logging (0-100).
// signal   = 'BUY' | 'SELL' | 'WAIT'
// ─────────────────────────────────────────────────────────────────────────────
class JournalEntry {
  final int? id;
  final String asset;
  final int epoch;
  final double open, high, low, close, movement;

  // Garden indicators
  final double ao, ac;
  final double stochK;   // slowed K, 0-100
  final double mmmDelta; // raw MMM delta
  final int riskPct;     // composite score 0-100
  final String signal;   // 'BUY' | 'SELL' | 'WAIT'

  // Legacy fields kept for CSV export compatibility — default to 0/false/''
  final bool spike;
  final int candlesSinceSpike;
  final String structureTag;
  final double? highLowSpread;
  final int? tickVolume;

  const JournalEntry({
    this.id,
    required this.asset,
    required this.epoch,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.movement,
    required this.ao,
    required this.ac,
    this.stochK = 50,
    this.mmmDelta = 0,
    this.riskPct = 0,
    this.signal = 'WAIT',
    this.spike = false,
    this.candlesSinceSpike = 0,
    this.structureTag = '',
    this.highLowSpread,
    this.tickVolume,
  });

  Map<String, dynamic> toMap() => {
        'asset': asset,
        'epoch': epoch,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'movement': movement,
        'ao': ao,
        'ac': ac,
        'stochK': stochK,
        'mmmDelta': mmmDelta,
        'riskPct': riskPct,
        'signal': signal,
        'spike': spike ? 1 : 0,
        'candlesSinceSpike': candlesSinceSpike,
        'structureTag': structureTag,
        'highLowSpread': highLowSpread,
        'tickVolume': tickVolume,
      };

  static JournalEntry fromMap(Map<String, dynamic> m) => JournalEntry(
        id: m['id'] as int?,
        asset: m['asset'] as String,
        epoch: m['epoch'] as int,
        open: (m['open'] as num).toDouble(),
        high: (m['high'] as num).toDouble(),
        low: (m['low'] as num).toDouble(),
        close: (m['close'] as num).toDouble(),
        movement: (m['movement'] as num).toDouble(),
        ao: (m['ao'] as num).toDouble(),
        ac: (m['ac'] as num).toDouble(),
        stochK: (m['stochK'] as num?)?.toDouble() ?? 50,
        mmmDelta: (m['mmmDelta'] as num?)?.toDouble() ?? 0,
        riskPct: (m['riskPct'] as num?)?.toInt() ?? 0,
        signal: m['signal'] as String? ?? 'WAIT',
        spike: ((m['spike'] as int?) ?? 0) == 1,
        candlesSinceSpike: (m['candlesSinceSpike'] as int?) ?? 0,
        structureTag: m['structureTag'] as String? ?? '',
        highLowSpread: (m['highLowSpread'] as num?)?.toDouble(),
        tickVolume: m['tickVolume'] as int?,
      );
}

class DaySummary {
  final int count;
  final double total;
  final int avgRisk;
  const DaySummary(this.count, this.total, {this.avgRisk = 0});
}

class JournalDb {
  JournalDb._internal();
  static final JournalDb instance = JournalDb._internal();
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = join(dir, 'itrade_journal.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        open REAL, high REAL, low REAL, close REAL, movement REAL,
        ao REAL, ac REAL,
        stochK REAL DEFAULT 50,
        mmmDelta REAL DEFAULT 0,
        riskPct INTEGER DEFAULT 0,
        signal TEXT DEFAULT 'WAIT',
        spike INTEGER DEFAULT 0,
        candlesSinceSpike INTEGER DEFAULT 0,
        structureTag TEXT DEFAULT '',
        highLowSpread REAL,
        tickVolume INTEGER,
        UNIQUE(asset, epoch)
      )
    ''');
    await db.execute('CREATE INDEX idx_asset_epoch ON entries(asset, epoch)');
    await db.execute('''
      CREATE TABLE state (
        key TEXT PRIMARY KEY,
        view TEXT,
        activeAsset TEXT,
        journalAsset TEXT,
        soundOn INTEGER DEFAULT 1
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add Garden columns to existing installs without losing old data
      for (final sql in [
        'ALTER TABLE entries ADD COLUMN stochK REAL DEFAULT 50',
        'ALTER TABLE entries ADD COLUMN mmmDelta REAL DEFAULT 0',
        'ALTER TABLE entries ADD COLUMN riskPct INTEGER DEFAULT 0',
        "ALTER TABLE entries ADD COLUMN signal TEXT DEFAULT 'WAIT'",
        'ALTER TABLE state ADD COLUMN soundOn INTEGER DEFAULT 1',
      ]) {
        try { await db.execute(sql); } catch (_) { /* column may already exist */ }
      }
    }
  }

  Future<void> logCandle(JournalEntry entry) async {
    final db = await _open();
    await db.insert('entries', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> lastLoggedEpoch(String asset) async {
    final db = await _open();
    final rows = await db.rawQuery(
        'SELECT MAX(epoch) as e FROM entries WHERE asset = ?', [asset]);
    return rows.first['e'] as int?;
  }

  Future<List<JournalEntry>> getEntriesForDay(String asset, DateTime day) async {
    final db = await _open();
    final start = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch ~/ 1000;
    final end = start + 24 * 3600 - 1;
    final rows = await db.query('entries',
        where: 'asset = ? AND epoch BETWEEN ? AND ?',
        whereArgs: [asset, start, end],
        orderBy: 'epoch ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getEntriesForWeek(String asset, DateTime weekStart) async {
    final db = await _open();
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day)
            .millisecondsSinceEpoch ~/
        1000;
    final end = start + 7 * 24 * 3600;
    final rows = await db.query('entries',
        where: 'asset = ? AND epoch BETWEEN ? AND ?',
        whereArgs: [asset, start, end],
        orderBy: 'epoch ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// month is 0-indexed (0 = January)
  Future<Map<String, DaySummary>> getDaySummaries(
      String asset, int year, int month) async {
    final db = await _open();
    final start = DateTime(year, month + 1, 1).millisecondsSinceEpoch ~/ 1000;
    final end = DateTime(year, month + 2, 0, 23, 59, 59).millisecondsSinceEpoch ~/ 1000;
    final rows = await db.query('entries',
        where: 'asset = ? AND epoch BETWEEN ? AND ?', whereArgs: [asset, start, end]);
    final out = <String, DaySummary>{};
    final riskTotals = <String, int>{};
    for (final r in rows) {
      final e = JournalEntry.fromMap(r);
      final d = DateTime.fromMillisecondsSinceEpoch(e.epoch * 1000, isUtc: true);
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final prev = out[key] ?? const DaySummary(0, 0);
      riskTotals[key] = (riskTotals[key] ?? 0) + e.riskPct;
      out[key] = DaySummary(
        prev.count + 1,
        prev.total + e.movement,
        avgRisk: riskTotals[key]! ~/ (prev.count + 1),
      );
    }
    return out;
  }

  Future<void> saveState({
    required String view,
    required String activeAsset,
    required String journalAsset,
    required bool soundOn,
  }) async {
    final db = await _open();
    await db.insert(
      'state',
      {
        'key': 'appState',
        'view': view,
        'activeAsset': activeAsset,
        'journalAsset': journalAsset,
        'soundOn': soundOn ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadState() async {
    final db = await _open();
    final rows = await db.query('state', where: 'key = ?', whereArgs: ['appState']);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'view': r['view'] as String? ?? '',
      'activeAsset': r['activeAsset'] as String? ?? '',
      'journalAsset': r['journalAsset'] as String? ?? '',
      'soundOn': (r['soundOn'] as int?) ?? 1,
    };
  }
}
