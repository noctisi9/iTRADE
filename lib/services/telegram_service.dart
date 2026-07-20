import 'dart:convert';
import 'dart:io';

// ─────────────────────────────────────────────────────────────────────────────
// TelegramService v2
//
// CONFIGURE THESE BEFORE FIRST USE:
//   1. @BotFather → /newbot → copy token
//   2. Add bot to your channel as admin
//   3. Send any message in channel
//   4. Visit: https://api.telegram.org/bot{TOKEN}/getUpdates
//   5. Copy the "id" value from "chat" object (negative number for channels)
// ─────────────────────────────────────────────────────────────────────────────

const String _botToken = 'YOUR_BOT_TOKEN_HERE';
const String _chatId   = 'YOUR_CHAT_ID_HERE';

class TelegramService {
  TelegramService._();
  static final TelegramService instance = TelegramService._();

  bool _enabled = true;
  void setEnabled(bool v) => _enabled = v;
  bool get enabled => _enabled;

  // ── SIGNAL OPEN ─────────────────────────────────────────────────────────
  Future<void> sendSignalOpen({
    required String asset,
    required String direction,
    required String timeframe,
    required String riskLabel,    // 'HIGH 🔥' | 'LOW ❄'
    required int    candlesSinceSpike,
    required double entryPrice,
  }) async {
    final assetEmoji = asset.startsWith('BOOM') ? '💥' : '📊';
    final dirEmoji   = direction == 'SELL' ? '📉' : '📈';

    final msg = '*_$dirEmoji ${_esc(asset)} \\[$timeframe\\] $direction: NOW_*\n'
        '*_📈 Targets:_*\n'
        '    🎯TP¹: 5 Candles\n'
        '*_❌ Stop Loss: NONE_*\n'
        '*_🔘 MANAGE YOUR OWN RISK_*\n'
        '*_⚡ Risk: ${_esc(riskLabel)}_*\n'
        '*_$assetEmoji ${_esc(candlesSinceSpike.toString())}c since spike_*\n'
        '*_💰 Entry: ${_esc(entryPrice.toStringAsFixed(3))}_*\n'
        '🟢 *TRADE OPEN*\n'
        '*NOX❄*';
    await _send(msg);
  }

  // ── 5-CANDLE TARGET REACHED ──────────────────────────────────────────────
  Future<void> sendTargetReached({
    required String asset,
    required String direction,
    required String timeframe,
    required double entryPrice,
    required double exitPrice,
    required double pointMove,
  }) async {
    final pnl      = (pointMove * 0.5 * 0.20).toStringAsFixed(2);
    final assetEmoji = asset.startsWith('BOOM') ? '💥' : '📊';
    final won      = (direction == 'SELL' && exitPrice < entryPrice) ||
                     (direction == 'BUY'  && exitPrice > entryPrice);

    final msg = '*_$assetEmoji ${_esc(asset)} \\[$timeframe\\] \\| TP HIT ✅\\|_*\n'
        '🎯 *5 CANDLES COMPLETE*\n'
        '*_Entry:_* ${_esc(entryPrice.toStringAsFixed(3))}\n'
        '*_Exit:_*  ${_esc(exitPrice.toStringAsFixed(3))}\n'
        '*_Move:_*  ${_esc(pointMove.toStringAsFixed(3))} pts\n'
        '*_Est P/L \\(0\\.20 lot\\):_* \\$${_esc(pnl)}\n'
        '${won ? '✅' : '❌'} *${won ? 'IN PROFIT' : 'IN LOSS'}*\n'
        '\n'
        '_You can still hold — signal remains active until misalignment_\n'
        '*NOX❄*';
    await _send(msg);
  }

  // ── SIGNAL CLOSED — MISALIGNMENT (CLOSE ALL TRADES) ─────────────────────
  Future<void> sendCloseAll({
    required String asset,
    required String direction,
    required String timeframe,
    required int    candlesHeld,
  }) async {
    final assetEmoji = asset.startsWith('BOOM') ? '💥' : '📊';

    final msg = '🚨 *${_esc(asset)} \\[$timeframe\\] \\| CLOSE ALL TRADES \\|*\n'
        '*SIGNAL INVALIDATED — MISALIGNMENT DETECTED*\n'
        '_${_esc(direction)} signal held for ${_esc(candlesHeld.toString())} candles_\n'
        '\n'
        '*❗ EXIT ALL ${_esc(direction)} POSITIONS NOW*\n'
        '*NOX❄*';
    await _send(msg);
  }

  // ── INTERNAL SEND ────────────────────────────────────────────────────────
  Future<void> _send(String text) async {
    if (!_enabled) return;
    if (_botToken == 'YOUR_BOT_TOKEN_HERE' || _chatId == 'YOUR_CHAT_ID_HERE') {
      return; // not configured
    }
    try {
      final client  = HttpClient();
      final uri     = Uri.parse(
          'https://api.telegram.org/bot$_botToken/sendMessage');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'chat_id':    _chatId,
        'text':       text,
        'parse_mode': 'MarkdownV2',
      }));
      final response = await request.close();
      await response.drain<void>();
      client.close();
    } catch (_) {
      // Never crash the app over Telegram
    }
  }

  // Escape MarkdownV2 special chars
  String _esc(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('.', r'\.')
      .replaceAll('-', r'\-')
      .replaceAll('!', r'\!')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll('+', r'\+')
      .replaceAll('=', r'\=');
}
