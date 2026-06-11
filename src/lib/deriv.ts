// Live Deriv WebSocket candle feed (public app_id=1089, no auth).
// Shared singleton WS so multiple components reuse one connection.
import { useEffect, useState } from "react";

export type Candle = {
  o: number;
  h: number;
  l: number;
  c: number;
  epoch: number;
  spike?: boolean;
};

// Map our display asset names to Deriv symbol codes.
export const ASSET_SYMBOL: Record<string, string> = {
  BOOM1000: "BOOM1000",
  CRASH1000: "CRASH1000",
  VIX75: "R_75",
  "VIX75 1s": "1HZ75V",
};

type Subscriber = (candles: Candle[]) => void;

const MAX_CANDLES = 60;
const GRANULARITY = 60; // 1-minute candles

class DerivFeed {
  private ws: WebSocket | null = null;
  private connected = false;
  private connecting = false;
  private queue: object[] = [];
  private candles = new Map<string, Candle[]>(); // symbol -> candles
  private subs = new Map<string, Set<Subscriber>>(); // symbol -> subscribers
  private requested = new Set<string>();
  private reqIdToSymbol = new Map<number, string>();
  private nextReqId = 1;

  private connect() {
    if (this.connecting || this.connected) return;
    this.connecting = true;
    const ws = new WebSocket(
      "wss://ws.derivws.com/websockets/v3?app_id=1089"
    );
    this.ws = ws;
    ws.onopen = () => {
      this.connected = true;
      this.connecting = false;
      // flush queued requests
      this.queue.forEach((m) => ws.send(JSON.stringify(m)));
      this.queue = [];
      // re-subscribe any pending symbols
      this.requested.forEach((sym) => this.sendSubscribe(sym));
    };
    ws.onmessage = (ev) => this.handleMessage(ev);
    ws.onclose = () => {
      this.connected = false;
      this.connecting = false;
      this.ws = null;
      // reconnect after a short delay if there are still subscribers
      if (this.subs.size > 0) {
        setTimeout(() => this.connect(), 1500);
      }
    };
    ws.onerror = () => {
      try {
        ws.close();
      } catch {
        // ignore
      }
    };
  }

  private send(msg: object) {
    if (this.connected && this.ws) this.ws.send(JSON.stringify(msg));
    else {
      this.queue.push(msg);
      this.connect();
    }
  }

  private sendSubscribe(symbol: string) {
    const reqId = this.nextReqId++;
    this.reqIdToSymbol.set(reqId, symbol);
    this.send({
      ticks_history: symbol,
      adjust_start_time: 1,
      count: MAX_CANDLES,
      end: "latest",
      style: "candles",
      granularity: GRANULARITY,
      subscribe: 1,
      req_id: reqId,
    });
  }

  private handleMessage(ev: MessageEvent) {
    let data: {
      msg_type?: string;
      req_id?: number;
      candles?: Array<{
        epoch: number;
        open: number | string;
        high: number | string;
        low: number | string;
        close: number | string;
      }>;
      ohlc?: {
        symbol?: string;
        epoch: number | string;
        open_time?: number | string;
        open: number | string;
        high: number | string;
        low: number | string;
        close: number | string;
      };
    };
    try {
      data = JSON.parse(ev.data);
    } catch {
      return;
    }

    if (data.candles) {
      const symbol =
        (data.req_id && this.reqIdToSymbol.get(data.req_id)) || "";
      if (!symbol) return;
      const list: Candle[] = data.candles.map((c) => ({
        epoch: Number(c.epoch),
        o: Number(c.open),
        h: Number(c.high),
        l: Number(c.low),
        c: Number(c.close),
      }));
      this.candles.set(symbol, this.markSpikes(symbol, list));
      this.emit(symbol);
    } else if (data.ohlc) {
      const symbol = data.ohlc.symbol || "";
      if (!symbol || !this.subs.has(symbol)) return;
      const fresh: Candle = {
        epoch: Number(data.ohlc.open_time ?? data.ohlc.epoch),
        o: Number(data.ohlc.open),
        h: Number(data.ohlc.high),
        l: Number(data.ohlc.low),
        c: Number(data.ohlc.close),
      };
      const list = this.candles.get(symbol) ?? [];
      const last = list[list.length - 1];
      if (last && last.epoch === fresh.epoch) {
        list[list.length - 1] = fresh;
      } else {
        list.push(fresh);
        if (list.length > MAX_CANDLES) list.shift();
      }
      this.candles.set(symbol, this.markSpikes(symbol, list));
      this.emit(symbol);
    }
  }

  private markSpikes(symbol: string, list: Candle[]): Candle[] {
    // Use median absolute body of last N candles as baseline.
    const window = list.slice(-30);
    const bodies = window.map((c) => Math.abs(c.c - c.o)).sort((a, b) => a - b);
    const med = bodies[Math.floor(bodies.length / 2)] || 0.0001;
    const isBoomCrash =
      symbol.startsWith("BOOM") || symbol.startsWith("CRASH");
    const mult = isBoomCrash ? 4 : 6;
    return list.map((c) => {
      const body = Math.abs(c.c - c.o);
      const spike = body > med * mult && med > 0;
      return spike ? { ...c, spike: true } : { ...c, spike: false };
    });
  }

  private emit(symbol: string) {
    const list = this.candles.get(symbol);
    if (!list) return;
    this.subs.get(symbol)?.forEach((fn) => fn(list));
  }

  subscribe(symbol: string, fn: Subscriber): () => void {
    if (!this.subs.has(symbol)) this.subs.set(symbol, new Set());
    this.subs.get(symbol)!.add(fn);
    // Emit cached snapshot immediately
    const cached = this.candles.get(symbol);
    if (cached) fn(cached);
    // Ensure WS + subscription
    if (!this.requested.has(symbol)) {
      this.requested.add(symbol);
      this.sendSubscribe(symbol);
    } else {
      this.connect();
    }
    return () => {
      const set = this.subs.get(symbol);
      if (!set) return;
      set.delete(fn);
      // Keep subscription open even if temporarily empty — cheaper than re-subscribing.
    };
  }
}

const feed = new DerivFeed();

export function useDerivCandles(asset: string): {
  candles: Candle[];
  symbol: string;
} {
  const symbol = ASSET_SYMBOL[asset] ?? asset;
  const [candles, setCandles] = useState<Candle[]>([]);
  useEffect(() => {
    setCandles([]);
    const unsub = feed.subscribe(symbol, setCandles);
    return unsub;
  }, [symbol]);
  return { candles, symbol };
}

// ---- Indicator math (kept here so chart + indicators share the same source) ----

function sma(values: number[], period: number): number[] {
  const out: number[] = [];
  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    out.push(i >= period - 1 ? sum / period : NaN);
  }
  return out;
}

function ema(values: number[], period: number): number[] {
  const out: number[] = [];
  const k = 2 / (period + 1);
  let prev = values[0] ?? 0;
  values.forEach((v, i) => {
    prev = i === 0 ? v : v * k + prev * (1 - k);
    out.push(prev);
  });
  return out;
}

export function calcIndicators(candles: Candle[]) {
  if (candles.length < 35) return null;
  const hl2 = candles.map((c) => (c.h + c.l) / 2);
  const closes = candles.map((c) => c.c);

  const ao = sma(hl2, 5).map((v, i) => v - sma(hl2, 34)[i]);
  const aoLast = ao[ao.length - 1] ?? 0;

  // AC = AO - SMA(AO, 5)
  const aoValid = ao.map((v) => (isFinite(v) ? v : 0));
  const ac = aoValid.map((v, i) => v - sma(aoValid, 5)[i]);
  const acLast = ac[ac.length - 1] ?? 0;

  // RSI 14
  let gains = 0;
  let losses = 0;
  const period = 14;
  for (let i = 1; i <= period && i < closes.length; i++) {
    const d = closes[i] - closes[i - 1];
    if (d >= 0) gains += d;
    else losses -= d;
  }
  let avgG = gains / period;
  let avgL = losses / period;
  for (let i = period + 1; i < closes.length; i++) {
    const d = closes[i] - closes[i - 1];
    avgG = (avgG * (period - 1) + Math.max(0, d)) / period;
    avgL = (avgL * (period - 1) + Math.max(0, -d)) / period;
  }
  const rs = avgL === 0 ? 100 : avgG / avgL;
  const rsi = 100 - 100 / (1 + rs);

  // MACD (12,26,9) histogram
  const ema12 = ema(closes, 12);
  const ema26 = ema(closes, 26);
  const macdLine = ema12.map((v, i) => v - ema26[i]);
  const signal = ema(macdLine, 9);
  const macdHist = macdLine[macdLine.length - 1] - signal[signal.length - 1];

  // Stochastic %K (14)
  const stochWin = candles.slice(-14);
  const hh = Math.max(...stochWin.map((c) => c.h));
  const ll = Math.min(...stochWin.map((c) => c.l));
  const stoch =
    hh === ll ? 50 : ((closes[closes.length - 1] - ll) / (hh - ll)) * 100;

  // Bollinger distance of close from SMA20 in std-devs
  const last20 = closes.slice(-20);
  const mean20 = last20.reduce((a, b) => a + b, 0) / last20.length;
  const variance =
    last20.reduce((a, b) => a + (b - mean20) ** 2, 0) / last20.length;
  const sd = Math.sqrt(variance) || 1;
  const vwcBB = (closes[closes.length - 1] - mean20) / sd;

  // AO breakout: new high/low vs last 20 AO values
  const aoTail = ao.slice(-21, -1);
  const aoMax = Math.max(...aoTail.filter((v) => isFinite(v)));
  const aoMin = Math.min(...aoTail.filter((v) => isFinite(v)));
  const aoBreakout: "max" | "min" | "none" =
    aoLast > aoMax ? "max" : aoLast < aoMin ? "min" : "none";

  return {
    ao: +aoLast.toFixed(4),
    ac: +acLast.toFixed(4),
    rsi: +rsi.toFixed(1),
    macd: +macdHist.toFixed(4),
    stoch: +stoch.toFixed(1),
    vwcBB: +vwcBB.toFixed(2),
    aoBreakout,
    aoSeries: ao,
  };
}
