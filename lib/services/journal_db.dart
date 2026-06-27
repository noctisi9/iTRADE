import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JournalEntry — every closed candle per asset×timeframe
// Records full OHLC, all 4 indicator values, signal state, risk score.
// ─────────────────────────────────────────────────────────────────────────────
class JournalEntry {
  final int?    id;
  final String  asset;
  final String  timeframe;   // '1m' | '5m' | '15m'
  final int     epoch;       // candle open epoch (seconds UTC)
  final int     candleNum;   // sequential number within session
  final double  open, high, low, close, movement;
  final bool    spike;

  // Indicator states
  final double  ao, ac;
  final double  stochK;
  final String  stochLabel;  // 'OVERBOUGHT' | 'OVERSOLD' | 'NEUTRAL'
  final double  mmmDelta;
  final String  mmmDir;      // 'BEARISH' | 'BULLISH'
  final int     riskPct;
  final String  signal;      // 'BUY' | 'SELL' | 'WAIT'

  // BOOM/CRASH spike tracking
  final int     candlesSinceSpike;

  const JournalEntry({
    this.id,
    required this.asset,
    required this.timeframe,
    required this.epoch,
    required this.candleNum,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.movement,
    this.spike = false,
    required this.ao,
    required this.ac,
    this.stochK = 50,
    this.stochLabel = 'NEUTRAL',
    this.mmmDelta = 0,
    this.mmmDir = 'NEUTRAL',
    this.riskPct = 0,
    this.signal = 'WAIT',
    this.candlesSinceSpike = 0,
  });

  Map<String, dynamic> toMap() => {
    'asset': asset, 'timeframe': timeframe, 'epoch': epoch,
    'candleNum': candleNum,
    'open': open, 'high': high, 'low': low, 'close': close,
    'movement': movement, 'spike': spike ? 1 : 0,
    'ao': ao, 'ac': ac,
    'stochK': stochK, 'stochLabel': stochLabel,
    'mmmDelta': mmmDelta, 'mmmDir': mmmDir,
    'riskPct': riskPct, 'signal': signal,
    'candlesSinceSpike': candlesSinceSpike,
  };

  static JournalEntry fromMap(Map<String, dynamic> m) => JournalEntry(
    id: m['id'] as int?,
    asset: m['asset'] as String,
    timeframe: m['timeframe'] as String? ?? '1m',
    epoch: m['epoch'] as int,
    candleNum: m['candleNum'] as int? ?? 0,
    open:     _d(m['open']),  high: _d(m['high']),
    low:      _d(m['low']),   close: _d(m['close']),
    movement: _d(m['movement']),
    spike: ((m['spike'] as int?) ?? 0) == 1,
    ao: _d(m['ao']),  ac: _d(m['ac']),
    stochK: _d(m['stochK'] ?? 50),
    stochLabel: m['stochLabel'] as String? ?? 'NEUTRAL',
    mmmDelta: _d(m['mmmDelta'] ?? 0),
    mmmDir:   m['mmmDir'] as String? ?? 'NEUTRAL',
    riskPct:  (m['riskPct'] as int?) ?? 0,
    signal:   m['signal'] as String? ?? 'WAIT',
    candlesSinceSpike: (m['candlesSinceSpike'] as int?) ?? 0,
  );

  static double _d(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// SignalSession — a completed trade signal from open to close
// ─────────────────────────────────────────────────────────────────────────────
class SignalSession {
  final int?   id;
  final String asset;
  final String timeframe;
  final String signal;       // 'BUY' | 'SELL'
  final int    openEpoch;
  final int    closeEpoch;
  final double entryPrice;
  final double exitPrice;
  final int    candlesHeld;
  final double pointMove;    // abs(exit - entry)
  final int    peakScore;    // highest risk score during session

  const SignalSession({
    this.id,
    required this.asset,
    required this.timeframe,
    required this.signal,
    required this.openEpoch,
    required this.closeEpoch,
    required this.entryPrice,
    required this.exitPrice,
    required this.candlesHeld,
    required this.pointMove,
    required this.peakScore,
  });

  // P&L at standard 0.20 lot size (configurable later)
  double get estimatedPnl {
    // Each point = $0.50 on 0.20 lot for BOOM/CRASH 1000
    // VIX: each point = $0.50 on 0.20 lot
    return pointMove * 0.5 * 0.20;
  }

  String get durationStr {
    final secs = closeEpoch - openEpoch;
    final mins = secs ~/ 60;
    final hrs  = mins ~/ 60;
    if (hrs > 0) return '${hrs}h ${mins % 60}m';
    return '${mins}m';
  }

  Map<String, dynamic> toMap() => {
    'asset': asset, 'timeframe': timeframe, 'signal': signal,
    'openEpoch': openEpoch, 'closeEpoch': closeEpoch,
    'entryPrice': entryPrice, 'exitPrice': exitPrice,
    'candlesHeld': candlesHeld, 'pointMove': pointMove,
    'peakScore': peakScore,
  };

  static SignalSession fromMap(Map<String, dynamic> m) => SignalSession(
    id:          m['id'] as int?,
    asset:       m['asset'] as String,
    timeframe:   m['timeframe'] as String? ?? '1m',
    signal:      m['signal'] as String,
    openEpoch:   m['openEpoch'] as int,
    closeEpoch:  m['closeEpoch'] as int,
    entryPrice:  _d(m['entryPrice']),
    exitPrice:   _d(m['exitPrice']),
    candlesHeld: m['candlesHeld'] as int? ?? 0,
    pointMove:   _d(m['pointMove']),
    peakScore:   m['peakScore'] as int? ?? 0,
  );

  static double _d(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// DaySummary — calendar dot data
// ─────────────────────────────────────────────────────────────────────────────
class DaySummary {
  final int    count;
  final double movement;
  final int    avgRisk;
  const DaySummary(this.count, this.movement, {this.avgRisk = 0});
}

// ─────────────────────────────────────────────────────────────────────────────
// JournalDb
// ─────────────────────────────────────────────────────────────────────────────
class JournalDb {
  JournalDb._();
  static final JournalDb instance = JournalDb._();
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'itrade_v3.db');
    _db = await openDatabase(path, version: 1,
        onCreate: _onCreate);
    return _db!;
  }

  Future<void> _onCreate(Database db, int _) async {
    // Full candle journal
    await db.execute('''
      CREATE TABLE entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset TEXT NOT NULL,
        timeframe TEXT NOT NULL DEFAULT '1m',
        epoch INTEGER NOT NULL,
        candleNum INTEGER DEFAULT 0,
        open REAL, high REAL, low REAL, close REAL, movement REAL,
        spike INTEGER DEFAULT 0,
        ao REAL, ac REAL,
        stochK REAL DEFAULT 50,
        stochLabel TEXT DEFAULT 'NEUTRAL',
        mmmDelta REAL DEFAULT 0,
        mmmDir TEXT DEFAULT 'NEUTRAL',
        riskPct INTEGER DEFAULT 0,
        signal TEXT DEFAULT 'WAIT',
        candlesSinceSpike INTEGER DEFAULT 0,
        UNIQUE(asset, timeframe, epoch)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_entries ON entries(asset, timeframe, epoch)');

    // Completed signal sessions (history page)
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        asset TEXT NOT NULL,
        timeframe TEXT NOT NULL,
        signal TEXT NOT NULL,
        openEpoch INTEGER NOT NULL,
        closeEpoch INTEGER NOT NULL,
        entryPrice REAL,
        exitPrice REAL,
        candlesHeld INTEGER DEFAULT 0,
        pointMove REAL DEFAULT 0,
        peakScore INTEGER DEFAULT 0
      )
    ''');

    // App state
    await db.execute('''
      CREATE TABLE state (
        key TEXT PRIMARY KEY,
        view TEXT, activeAsset TEXT, journalAsset TEXT,
        timeframe TEXT DEFAULT '1m',
        soundOn INTEGER DEFAULT 1
      )
    ''');

    // Per-asset candle counter (for sequential numbering)
    await db.execute('''
      CREATE TABLE candle_counters (
        asset TEXT NOT NULL,
        timeframe TEXT NOT NULL,
        counter INTEGER DEFAULT 0,
        PRIMARY KEY(asset, timeframe)
      )
    ''');
  }

  // ── Candle journal ────────────────────────────────────────────────────────

  Future<void> logCandle(JournalEntry e) async {
    final db = await _open();
    await db.insert('entries', e.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> logCandleBatch(List<JournalEntry> entries) async {
    if (entries.isEmpty) return;
    final db = await _open();
    final batch = db.batch();
    for (final e in entries) {
      batch.insert('entries', e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<int?> lastLoggedEpoch(String asset, String tf) async {
    final db = await _open();
    final rows = await db.rawQuery(
        'SELECT MAX(epoch) as e FROM entries WHERE asset=? AND timeframe=?',
        [asset, tf]);
    return rows.first['e'] as int?;
  }

  Future<int> nextCandleNum(String asset, String tf) async {
    final db = await _open();
    await db.execute(
        'INSERT OR IGNORE INTO candle_counters(asset, timeframe, counter) VALUES(?,?,0)',
        [asset, tf]);
    await db.execute(
        'UPDATE candle_counters SET counter=counter+1 WHERE asset=? AND timeframe=?',
        [asset, tf]);
    final rows = await db.rawQuery(
        'SELECT counter FROM candle_counters WHERE asset=? AND timeframe=?',
        [asset, tf]);
    return (rows.first['counter'] as int?) ?? 1;
  }

  Future<List<JournalEntry>> getEntriesForDay(
      String asset, String tf, DateTime day) async {
    final db  = await _open();
    final s   = DateTime.utc(day.year, day.month, day.day)
        .millisecondsSinceEpoch ~/ 1000;
    final e   = s + 86400;
    final rows = await db.query('entries',
        where: 'asset=? AND timeframe=? AND epoch BETWEEN ? AND ?',
        whereArgs: [asset, tf, s, e],
        orderBy: 'epoch ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getEntriesForWeek(
      String asset, String tf, DateTime weekStart) async {
    final db = await _open();
    final s  = DateTime.utc(weekStart.year, weekStart.month, weekStart.day)
        .millisecondsSinceEpoch ~/ 1000;
    final e  = s + 7 * 86400;
    final rows = await db.query('entries',
        where: 'asset=? AND timeframe=? AND epoch BETWEEN ? AND ?',
        whereArgs: [asset, tf, s, e],
        orderBy: 'epoch ASC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  Future<Map<String, DaySummary>> getDaySummaries(
      String asset, String tf, int year, int month) async {
    final db = await _open();
    final s  = DateTime.utc(year, month, 1).millisecondsSinceEpoch ~/ 1000;
    final e  = DateTime.utc(year, month + 1, 0, 23, 59, 59)
        .millisecondsSinceEpoch ~/ 1000;
    final rows = await db.query('entries',
        where: 'asset=? AND timeframe=? AND epoch BETWEEN ? AND ?',
        whereArgs: [asset, tf, s, e]);
    final out      = <String, DaySummary>{};
    final riskSums = <String, int>{};
    final counts   = <String, int>{};
    for (final r in rows) {
      final entry = JournalEntry.fromMap(r);
      final d     = DateTime.fromMillisecondsSinceEpoch(
          entry.epoch * 1000, isUtc: true);
      final key   = '${d.year}-${_p(d.month)}-${_p(d.day)}';
      counts[key]   = (counts[key] ?? 0) + 1;
      riskSums[key] = (riskSums[key] ?? 0) + entry.riskPct;
      final prev  = out[key] ?? const DaySummary(0, 0);
      out[key]    = DaySummary(
          counts[key]!,
          prev.movement + entry.movement,
          avgRisk: riskSums[key]! ~/ counts[key]!);
    }
    return out;
  }

  // ── Signal sessions (History) ─────────────────────────────────────────────

  Future<void> logSession(SignalSession s) async {
    final db = await _open();
    await db.insert('sessions', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SignalSession>> getSessions(
      {String? asset, String? tf, int limit = 100}) async {
    final db    = await _open();
    final where = <String>[];
    final args  = <dynamic>[];
    if (asset != null) { where.add('asset=?'); args.add(asset); }
    if (tf    != null) { where.add('timeframe=?'); args.add(tf); }
    final rows  = await db.query('sessions',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'openEpoch DESC',
        limit: limit);
    return rows.map(SignalSession.fromMap).toList();
  }

  // ── App state ─────────────────────────────────────────────────────────────

  Future<void> saveState({
    required String view,
    required String activeAsset,
    required String journalAsset,
    required String timeframe,
    required bool   soundOn,
  }) async {
    final db = await _open();
    await db.insert('state', {
      'key': 'app',
      'view': view,
      'activeAsset': activeAsset,
      'journalAsset': journalAsset,
      'timeframe': timeframe,
      'soundOn': soundOn ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> loadState() async {
    final db   = await _open();
    final rows = await db.query('state', where: 'key=?', whereArgs: ['app']);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'view':         r['view'] as String? ?? '',
      'activeAsset':  r['activeAsset']  as String? ?? '',
      'journalAsset': r['journalAsset'] as String? ?? '',
      'timeframe':    r['timeframe']    as String? ?? '1m',
      'soundOn':      r['soundOn']      as int?    ?? 1,
    };
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}
