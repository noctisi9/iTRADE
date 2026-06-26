import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/candle.dart';

const int _maxCandles = 200; // store more to power the Garden engines
const int _granularity = 60;

/// Singleton live feed from Deriv's public WebSocket API.
/// v2: gap-fill on reconnect — fetches all candles from last known epoch
/// to now so no data is lost while offline.
class DerivFeed {
  DerivFeed._internal();
  static final DerivFeed instance = DerivFeed._internal();

  WebSocketChannel? _channel;
  bool _connected = false;
  bool _connecting = false;
  final List<Map<String, dynamic>> _queue = [];
  final Map<String, List<Candle>> _candles = {};
  final Map<String, StreamController<List<Candle>>> _controllers = {};
  final Set<String> _requested = {};
  final Map<int, String> _reqIdToSymbol = {};
  int _nextReqId = 1;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  // Gap-fill callback — set by signals page so missing candles get journalled
  void Function(String symbol, List<Candle> gapCandles)? onGapFilled;

  StreamController<List<Candle>> _controllerFor(String symbol) {
    return _controllers.putIfAbsent(
        symbol, () => StreamController<List<Candle>>.broadcast());
  }

  Stream<List<Candle>> stream(String symbol) {
    final ctrl = _controllerFor(symbol);
    if (!_requested.contains(symbol)) {
      _requested.add(symbol);
      _sendSubscribe(symbol);
    } else {
      _connect();
      final cached = _candles[symbol];
      if (cached != null) {
        scheduleMicrotask(() => ctrl.add(List.unmodifiable(cached)));
      }
    }
    return ctrl.stream;
  }

  void _connect() {
    if (_connecting || _connected) return;
    _connecting = true;
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('wss://ws.derivws.com/websockets/v3?app_id=1089'),
      );
      _channel = channel;
      _sub = channel.stream.listen(
        _handleMessage,
        onDone: _handleClose,
        onError: (_) => _handleClose(),
        cancelOnError: true,
      );
      _connected = true;
      _connecting = false;
      for (final m in _queue) {
        _channel!.sink.add(jsonEncode(m));
      }
      _queue.clear();
      for (final sym in _requested) {
        _sendSubscribe(sym);
      }
    } catch (_) {
      _connecting = false;
      _scheduleReconnect();
    }
  }

  void _handleClose() {
    _connected = false;
    _connecting = false;
    _channel = null;
    _sub?.cancel();
    if (_requested.isNotEmpty) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 1500), _connect);
  }

  void _send(Map<String, dynamic> msg) {
    if (_connected && _channel != null) {
      _channel!.sink.add(jsonEncode(msg));
    } else {
      _queue.add(msg);
      _connect();
    }
  }

  /// Subscribe, requesting from the last candle we have (gap-fill) or the
  /// most recent _maxCandles if we have nothing.
  void _sendSubscribe(String symbol) {
    final reqId = _nextReqId++;
    _reqIdToSymbol[reqId] = symbol;

    final existing = _candles[symbol];
    final lastEpoch = existing?.isNotEmpty == true ? existing!.last.epoch : null;

    final Map<String, dynamic> req = {
      'ticks_history': symbol,
      'adjust_start_time': 1,
      'end': 'latest',
      'style': 'candles',
      'granularity': _granularity,
      'subscribe': 1,
      'req_id': reqId,
    };

    if (lastEpoch != null) {
      // Gap-fill: request from the last candle we have
      req['start'] = lastEpoch;
      req['count'] = _maxCandles;
    } else {
      req['count'] = _maxCandles;
    }

    _send(req);
  }

  void _handleMessage(dynamic raw) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (data['msg_type'] == 'candles' && data['candles'] != null) {
      final reqId = data['req_id'];
      final symbol = reqId != null ? _reqIdToSymbol[reqId] : null;
      if (symbol == null) return;

      final incoming = (data['candles'] as List)
          .map((c) => Candle(
                epoch: (c['epoch'] as num).toInt(),
                o: double.parse(c['open'].toString()),
                h: double.parse(c['high'].toString()),
                l: double.parse(c['low'].toString()),
                c: double.parse(c['close'].toString()),
              ))
          .toList();

      final existing = List<Candle>.from(_candles[symbol] ?? []);

      // Gap-fill merge: add any incoming candles not already in memory
      List<Candle> gapCandles = [];
      if (existing.isNotEmpty) {
        final existingEpochs = existing.map((c) => c.epoch).toSet();
        gapCandles = incoming.where((c) => !existingEpochs.contains(c.epoch)).toList();
        for (final c in gapCandles) {
          existing.add(c);
        }
        existing.sort((a, b) => a.epoch.compareTo(b.epoch));
      } else {
        existing.addAll(incoming);
      }

      // Trim to max window
      while (existing.length > _maxCandles) {
        existing.removeAt(0);
      }

      _candles[symbol] = _markSpikes(symbol, existing);
      _emit(symbol);

      // Notify caller of gap candles so they can be journalled
      if (gapCandles.isNotEmpty) {
        onGapFilled?.call(symbol, gapCandles);
      }
    } else if (data['msg_type'] == 'ohlc' && data['ohlc'] != null) {
      final ohlc = data['ohlc'] as Map<String, dynamic>;
      final symbol = ohlc['symbol'] as String?;
      if (symbol == null || !_requested.contains(symbol)) return;
      final epochRaw = ohlc['open_time'] ?? ohlc['epoch'];
      final fresh = Candle(
        epoch: (epochRaw as num).toInt(),
        o: double.parse(ohlc['open'].toString()),
        h: double.parse(ohlc['high'].toString()),
        l: double.parse(ohlc['low'].toString()),
        c: double.parse(ohlc['close'].toString()),
      );
      final list = List<Candle>.from(_candles[symbol] ?? []);
      if (list.isNotEmpty && list.last.epoch == fresh.epoch) {
        list[list.length - 1] = fresh;
      } else {
        list.add(fresh);
        if (list.length > _maxCandles) list.removeAt(0);
      }
      _candles[symbol] = _markSpikes(symbol, list);
      _emit(symbol);
    }
  }

  List<Candle> _markSpikes(String symbol, List<Candle> list) {
    final window = list.length > 30 ? list.sublist(list.length - 30) : list;
    final bodies = window.map((c) => (c.c - c.o).abs()).toList()..sort();
    final med = bodies.isNotEmpty ? bodies[bodies.length ~/ 2] : 0.0001;
    final isBoomCrash = symbol.startsWith('BOOM') || symbol.startsWith('CRASH');
    final mult = isBoomCrash ? 4 : 6;
    return list.map((c) {
      final body = (c.c - c.o).abs();
      return c.copyWith(spike: med > 0 && body > med * mult);
    }).toList();
  }

  void _emit(String symbol) {
    final list = _candles[symbol];
    if (list == null) return;
    _controllers[symbol]?.add(List.unmodifiable(list));
  }

  List<Candle> currentCandles(String symbol) =>
      List.unmodifiable(_candles[symbol] ?? const []);
}
