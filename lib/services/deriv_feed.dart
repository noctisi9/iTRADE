import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/candle.dart';

const int _maxCandles = 60;
const int _granularity = 60; // 1 minute candles

/// Singleton live feed from Deriv's public WebSocket API.
/// One physical connection, fan-out to per-symbol broadcast streams.
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

  StreamController<List<Candle>> _controllerFor(String symbol) {
    return _controllers.putIfAbsent(symbol, () {
      final c = StreamController<List<Candle>>.broadcast();
      return c;
    });
  }

  /// Subscribe to live 1-minute candles for [symbol] (the Deriv symbol code,
  /// e.g. 'R_75', not the display asset name).
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

  void _sendSubscribe(String symbol) {
    final reqId = _nextReqId++;
    _reqIdToSymbol[reqId] = symbol;
    _send({
      'ticks_history': symbol,
      'adjust_start_time': 1,
      'count': _maxCandles,
      'end': 'latest',
      'style': 'candles',
      'granularity': _granularity,
      'subscribe': 1,
      'req_id': reqId,
    });
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
      final list = (data['candles'] as List)
          .map((c) => Candle(
                epoch: (c['epoch'] as num).toInt(),
                o: double.parse(c['open'].toString()),
                h: double.parse(c['high'].toString()),
                l: double.parse(c['low'].toString()),
                c: double.parse(c['close'].toString()),
              ))
          .toList();
      _candles[symbol] = _markSpikes(symbol, list);
      _emit(symbol);
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

  /// Flags abnormally large-bodied candles as "spikes" — the same heuristic
  /// as the web app: body > median(body)*mult over the trailing window.
  List<Candle> _markSpikes(String symbol, List<Candle> list) {
    final window = list.length > 30 ? list.sublist(list.length - 30) : list;
    final bodies = window.map((c) => (c.c - c.o).abs()).toList()..sort();
    final med = bodies.isNotEmpty ? bodies[bodies.length ~/ 2] : 0.0001;
    final isBoomCrash = symbol.startsWith('BOOM') || symbol.startsWith('CRASH');
    final mult = isBoomCrash ? 4 : 6;
    return list.map((c) {
      final body = (c.c - c.o).abs();
      final spike = med > 0 && body > med * mult;
      return c.copyWith(spike: spike);
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
