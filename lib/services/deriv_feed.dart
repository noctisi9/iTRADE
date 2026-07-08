import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/candle.dart';
import 'journal_db.dart';

// Supported timeframes in seconds
const Map<String, int> kGranularities = {
  '1m':  60,
  '5m':  300,
  '15m': 900,
};

// In-memory rolling window. Raised from 300 → 5000 so the app holds full
// history in RAM (matches the SQLite cache) instead of only the last hour
// or so. ~5000 candles × 10 assets × 3 timeframes is still only a few MB.
const int _maxCandles = 5000;

/// Key: 'SYMBOL_TF' e.g. 'BOOM1000_1m'
String feedKey(String symbol, String tf) => '${symbol}_$tf';

/// Singleton live feed — manages one WebSocket per timeframe.
/// Gap-fill: on reconnect requests from last known epoch to 'latest'.
class DerivFeed {
  DerivFeed._();
  static final DerivFeed instance = DerivFeed._();

  // State per feedKey
  final Map<String, List<Candle>> _candles     = {};
  final Map<String, StreamController<List<Candle>>> _controllers = {};
  final Map<String, int?> _lastEpoch           = {};

  // Active subscriptions: reqId → feedKey
  final Map<int, String> _reqToKey = {};
  int _nextReqId = 1;

  // Per-timeframe WebSocket
  final Map<String, WebSocketChannel?> _channels   = {};
  final Map<String, StreamSubscription?> _subs      = {};
  final Map<String, bool> _connected                = {};
  final Map<String, Timer?> _reconnectTimers        = {};
  final Map<String, List<Map<String, dynamic>>> _queues = {};
  final Map<String, Set<String>> _requested         = {}; // tf → set of symbols

  // Gap-fill callback — journal missed candles
  void Function(String feedKey, List<Candle> gap)? onGapFilled;

  // ── Public API ────────────────────────────────────────────────────────────

  // Track which keys have already been warm-started, so repeat stream()
  // calls don't reload from disk.
  final Set<String> _warmed = {};

  Stream<List<Candle>> stream(String symbol, String tf) {
    final key  = feedKey(symbol, tf);
    final ctrl = _controllers.putIfAbsent(
        key, () => StreamController<List<Candle>>.broadcast());

    _requested.putIfAbsent(tf, () => {});
    if (!_requested[tf]!.contains(symbol)) {
      _requested[tf]!.add(symbol);
      _warmStartThenSubscribe(symbol, tf, key);
    } else {
      _ensureConnected(tf);
      final c = _candles[key];
      if (c != null) scheduleMicrotask(() => ctrl.add(List.unmodifiable(c)));
    }
    return ctrl.stream;
  }

  /// Loads any cached candles from SQLite first (near-instant, no network
  /// wait), emits them immediately, seeds _lastEpoch so the live subscribe
  /// gap-fills from exactly where we left off, then connects the WebSocket.
  /// If there's no cache at all, requests the full 5000-candle history on
  /// first connect instead of the usual smaller window.
  Future<void> _warmStartThenSubscribe(String symbol, String tf, String key) async {
    if (_warmed.contains(key)) {
      _ensureConnected(tf);
      _subscribe(symbol, tf);
      return;
    }
    _warmed.add(key);

    var isFirstEverFetch = true;
    try {
      final cached = await JournalDb.instance.loadCandles(symbol, tf, limit: _maxCandles);
      if (cached.isNotEmpty) {
        isFirstEverFetch = false;
        _candles[key] = _markSpikes(symbol, cached);
        _lastEpoch[key] = cached.last.epoch;
        _emit(key);
      }
    } catch (_) {
      // SQLite unavailable (e.g. first run before DB init) — fall through
      // to a normal live fetch, no warm start this time.
    }

    _ensureConnected(tf);
    if (isFirstEverFetch) {
      // No cache yet — this will be a full 5000-candle fetch, which is the
      // expensive request. Stagger these so requesting many assets at once
      // (e.g. opening the multi-asset dashboard) doesn't fire them all
      // simultaneously and risk Deriv's rate limit.
      _enqueueColdFetch(() => _subscribe(symbol, tf));
    } else {
      // Cache exists — this is just a small gap-fill delta, safe to fire
      // immediately regardless of how many other symbols are loading.
      _subscribe(symbol, tf);
    }
  }

  // ── Cold-fetch stagger queue ─────────────────────────────────────────────
  final List<void Function()> _coldFetchQueue = [];
  bool _coldFetchRunning = false;

  void _enqueueColdFetch(void Function() job) {
    _coldFetchQueue.add(job);
    _drainColdQueue();
  }

  void _drainColdQueue() {
    if (_coldFetchRunning || _coldFetchQueue.isEmpty) return;
    _coldFetchRunning = true;
    final job = _coldFetchQueue.removeAt(0);
    job();
    Timer(const Duration(milliseconds: 400), () {
      _coldFetchRunning = false;
      _drainColdQueue();
    });
  }

  List<Candle> current(String symbol, String tf) =>
      List.unmodifiable(_candles[feedKey(symbol, tf)] ?? const []);

  // ── Connection management ─────────────────────────────────────────────────

  void _ensureConnected(String tf) {
    if (_connected[tf] == true) return;
    _doConnect(tf);
  }

  void _doConnect(String tf) {
    _subs[tf]?.cancel();
    _channels[tf]?.sink.close();
    _connected[tf] = false;

    try {
      final ch = WebSocketChannel.connect(
          Uri.parse('wss://ws.derivws.com/websockets/v3?app_id=1089'));
      _channels[tf] = ch;
      _subs[tf] = ch.stream.listen(
        (raw) => _onMessage(tf, raw),
        onDone: () => _onClose(tf),
        onError: (_) => _onClose(tf),
        cancelOnError: true,
      );
      _connected[tf] = true;

      // Flush queued messages
      for (final m in (_queues[tf] ?? [])) {
        ch.sink.add(jsonEncode(m));
      }
      _queues[tf]?.clear();

      // Re-subscribe all symbols for this timeframe
      for (final sym in (_requested[tf] ?? <String>{})) {
        _subscribe(sym, tf);
      }
    } catch (_) {
      _scheduleReconnect(tf);
    }
  }

  void _onClose(String tf) {
    _connected[tf] = false;
    _subs[tf]?.cancel();
    _channels[tf] = null;
    if ((_requested[tf] ?? {}).isNotEmpty) _scheduleReconnect(tf);
  }

  void _scheduleReconnect(String tf) {
    _reconnectTimers[tf]?.cancel();
    _reconnectTimers[tf] =
        Timer(const Duration(milliseconds: 2000), () => _doConnect(tf));
  }

  void _send(String tf, Map<String, dynamic> msg) {
    if (_connected[tf] == true && _channels[tf] != null) {
      _channels[tf]!.sink.add(jsonEncode(msg));
    } else {
      _queues.putIfAbsent(tf, () => []).add(msg);
      _ensureConnected(tf);
    }
  }

  // ── Subscription (gap-aware) ──────────────────────────────────────────────

  void _subscribe(String symbol, String tf) {
    final key       = feedKey(symbol, tf);
    final gran      = kGranularities[tf]!;
    final reqId     = _nextReqId++;
    _reqToKey[reqId] = key;

    final lastEp = _lastEpoch[key];
    final req = <String, dynamic>{
      'ticks_history': symbol,
      'adjust_start_time': 1,
      'end':         'latest',
      'style':       'candles',
      'granularity': gran,
      'count':       _maxCandles,
      'subscribe':   1,
      'req_id':      reqId,
    };
    if (lastEp != null) {
      // Gap-fill: request from last known candle forward
      req['start'] = lastEp;
    }
    _send(tf, req);
  }

  // ── Message handling ──────────────────────────────────────────────────────

  void _onMessage(String tf, dynamic raw) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (data['msg_type'] == 'candles') {
      final reqId = data['req_id'] as int?;
      final key   = reqId != null ? _reqToKey[reqId] : null;
      if (key == null) return;

      final incoming = _parseCandles(data['candles'] as List);
      _mergeCandles(key, incoming, tf);

    } else if (data['msg_type'] == 'ohlc') {
      final ohlc   = data['ohlc'] as Map<String, dynamic>;
      final symbol = ohlc['symbol'] as String?;
      if (symbol == null) return;

      // Find which tf this subscription belongs to — match granularity
      final gran      = (ohlc['granularity'] as num?)?.toInt();
      final matchedTf = kGranularities.entries
          .where((e) => e.value == gran)
          .map((e) => e.key)
          .firstOrNull;
      final key = matchedTf != null ? feedKey(symbol, matchedTf) : null;
      if (key == null) return;

      final epochRaw = ohlc['open_time'] ?? ohlc['epoch'];
      final fresh = Candle(
        epoch: (epochRaw as num).toInt(),
        o: _d(ohlc['open']),
        h: _d(ohlc['high']),
        l: _d(ohlc['low']),
        c: _d(ohlc['close']),
      );

      final list = List<Candle>.from(_candles[key] ?? []);
      if (list.isNotEmpty && list.last.epoch == fresh.epoch) {
        list[list.length - 1] = fresh;
      } else {
        list.add(fresh);
        if (list.length > _maxCandles) list.removeAt(0);
      }
      _candles[key] = _markSpikes(symbol, list);
      _lastEpoch[key] = list.last.epoch;
      _emit(key);
      unawaited(JournalDb.instance.saveCandles(symbol, matchedTf!, [fresh]));
    }
  }

  // ── Merge with gap-fill ───────────────────────────────────────────────────

  void _mergeCandles(String key, List<Candle> incoming, String tf) {
    final existing = List<Candle>.from(_candles[key] ?? []);
    final List<Candle> gapCandles;

    if (existing.isNotEmpty) {
      final existingEpochs = existing.map((c) => c.epoch).toSet();
      gapCandles = incoming.where((c) => !existingEpochs.contains(c.epoch)).toList();
      existing.addAll(gapCandles);
      existing.sort((a, b) => a.epoch.compareTo(b.epoch));
    } else {
      gapCandles = [];
      existing.addAll(incoming);
    }

    while (existing.length > _maxCandles) {
      existing.removeAt(0);
    }

    // Extract symbol from key (format: SYMBOL_TF)
    final symbol = key.substring(0, key.lastIndexOf('_'));
    _candles[key] = _markSpikes(symbol, existing);
    if (existing.isNotEmpty) _lastEpoch[key] = existing.last.epoch;
    _emit(key);

    // Persist to SQLite — fire and forget, doesn't block the live feed.
    // Only the newly-arrived candles need writing; existing ones are
    // already stored (INSERT OR REPLACE handles any overlap safely).
    unawaited(JournalDb.instance.saveCandles(symbol, tf, incoming));

    if (gapCandles.isNotEmpty) {
      onGapFilled?.call(key, gapCandles);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Candle> _parseCandles(List<dynamic> raw) {
    return raw.map((c) => Candle(
          epoch: (c['epoch'] as num).toInt(),
          o: _d(c['open']),
          h: _d(c['high']),
          l: _d(c['low']),
          c: _d(c['close']),
        )).toList();
  }

  double _d(dynamic v) => double.parse(v.toString());

  List<Candle> _markSpikes(String symbol, List<Candle> list) {
    final window = list.length > 30 ? list.sublist(list.length - 30) : list;
    final bodies = window.map((c) => (c.c - c.o).abs()).toList()..sort();
    final med    = bodies.isNotEmpty ? bodies[bodies.length ~/ 2] : 0.0001;
    const mult   = 4; // BOOM/CRASH spike multiplier
    return list.map((c) {
      final body = (c.c - c.o).abs();
      return c.copyWith(spike: med > 0 && body > med * mult);
    }).toList();
  }

  void _emit(String key) {
    final list = _candles[key];
    if (list == null) return;
    _controllers[key]?.add(List.unmodifiable(list));
  }
}
