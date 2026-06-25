import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class JournalEntry {
  final int? id;
  final String asset;
  final int epoch;
  final double open, high, low, close, movement;
  final bool spike;
  final int candlesSinceSpike;
  final double ao, ac;
  final String structureTag;
  final double? cusumH, cusumThreshold, survivalProb, highLowSpread;
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
    required this.spike,
    required this.candlesSinceSpike,
    required this.ao,
    required this.ac,
    this.structureTag = '',
    this.cusumH,
    this.cusumThreshold,
    this.survivalProb,
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
        'spike': spike ? 1 : 0,
        'candlesSinceSpike': candlesSinceSpike,
        'ao': ao,
        'ac': ac,
        'structureTag': structureTag,
        'cusumH': cusumH,
        'cusumThreshold': cusumThreshold,
        'survivalProb': survivalProb,
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
        spike: (m['spike'] as int) == 1,
        candlesSinceSpike: m['candlesSinceSpike'] as int,
        ao: (m['ao'] as num).toDouble(),
        ac: (m['ac'] as num).toDouble(),
        structureTag: m['structureTag'] as String? ?? '',
        cusumH: (m['cusumH'] as num?)?.toDouble(),
        cusumThreshold: (m['cusumThreshold'] as num?)?.toDouble(),
        survivalProb: (m['survivalProb'] as num?)?.toDouble(),
        highLowSpread: (m['highLowSpread'] as num?)?.toDouble(),
        tickVolume: m['tickVolume'] as int?,
      );
}

class DaySummary {
  final int count;
  final double total;
  const DaySummary(this.count, this.total);
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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset TEXT NOT NULL,
            epoch INTEGER NOT NULL,
            open REAL, high REAL, low REAL, close REAL, movement REAL,
            spike INTEGER, candlesSinceSpike INTEGER,
            ao REAL, ac REAL, structureTag TEXT,
            cusumH REAL, cusumThreshold REAL, survivalProb REAL,
            highLowSpread REAL, tickVolume INTEGER,
            UNIQUE(asset, epoch)
          )
        ''');
        await db.execute('CREATE INDEX idx_asset_epoch ON entries(asset, epoch)');
        await db.execute('''
          CREATE TABLE state (
            key TEXT PRIMARY KEY,
            view TEXT, activeAsset TEXT, journalAsset TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> logCandle(JournalEntry entry) async {
    final db = await _open();
    await db.insert('entries', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
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

  /// month is 0-indexed (0 = January) to match the original app's convention.
  Future<Map<String, DaySummary>> getDaySummaries(
      String asset, int year, int month) async {
    final db = await _open();
    final start = DateTime(year, month + 1, 1).millisecondsSinceEpoch ~/ 1000;
    final end = DateTime(year, month + 2, 0, 23, 59, 59).millisecondsSinceEpoch ~/ 1000;
    final rows = await db.query('entries',
        where: 'asset = ? AND epoch BETWEEN ? AND ?', whereArgs: [asset, start, end]);
    final out = <String, DaySummary>{};
    for (final r in rows) {
      final e = JournalEntry.fromMap(r);
      final d = DateTime.fromMillisecondsSinceEpoch(e.epoch * 1000, isUtc: true);
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final prev = out[key] ?? const DaySummary(0, 0);
      out[key] = DaySummary(prev.count + 1, prev.total + e.movement);
    }
    return out;
  }

  Future<void> saveState(
      {required String view, required String activeAsset, required String journalAsset}) async {
    final db = await _open();
    await db.insert(
      'state',
      {'key': 'appState', 'view': view, 'activeAsset': activeAsset, 'journalAsset': journalAsset},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>?> loadState() async {
    final db = await _open();
    final rows = await db.query('state', where: 'key = ?', whereArgs: ['appState']);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'view': r['view'] as String? ?? '',
      'activeAsset': r['activeAsset'] as String? ?? '',
      'journalAsset': r['journalAsset'] as String? ?? '',
    };
  }
}
