import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/candle.dart';

// Supported timeframes in seconds
const Map<String, int> kGranularities = {
  '1m':  60,
  '5m':  300,
  '15m': 900,
};

const int _maxCandles = 300;

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

  Stream<List<Candle>> stream(String symbol, String tf) {
    final key  = feedKey(symbol, tf);
    final ctrl = _controllers.putIfAbsent(
        key, () => StreamController<List<Candle>>.broadcast());

    _requested.putIfAbsent(tf, () => {});
    if (!_requested[tf]!.contains(symbol)) {
      _requested[tf]!.add(symbol);
      _ensureConnected(tf);
      _subscribe(symbol, tf);
    } else {
      _ensureConnected(tf);
      final c = _candles[key];
      if (c != null) scheduleMicrotask(() => ctrl.add(List.unmodifiable(c)));
    }
    return ctrl.stream;
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
    final isBoomCrash = symbol.startsWith('BOOM') || symbol.startsWith('CRASH');
    final mult   = isBoomCrash ? 4 : 6;
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
