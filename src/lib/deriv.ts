import { useEffect, useState } from "react";

export type Candle = {
  o: number; h: number; l: number; c: number;
  epoch: number; spike?: boolean;
};

export const ASSET_SYMBOL: Record<string, string> = {
  BOOM1000: "BOOM1000", CRASH1000: "CRASH1000",
  VIX75: "R_75", "VIX75 1s": "1HZ75V",
};

type Subscriber = (candles: Candle[]) => void;
const MAX_CANDLES = 60;
const GRANULARITY = 60;

class DerivFeed {
  private ws: WebSocket | null = null;
  private connected = false; private connecting = false;
  private queue: object[] = [];
  private candles = new Map<string, Candle[]>();
  private subs = new Map<string, Set<Subscriber>>();
  private requested = new Set<string>();
  private reqIdToSymbol = new Map<number, string>();
  private nextReqId = 1;

  private connect() {
    if (this.connecting || this.connected) return;
    this.connecting = true;
    const ws = new WebSocket("wss://ws.derivws.com/websockets/v3?app_id=1089");
    this.ws = ws;
    ws.onopen = () => {
      this.connected = true; this.connecting = false;
      this.queue.forEach((m) => ws.send(JSON.stringify(m))); this.queue = [];
      this.requested.forEach((sym) => this.sendSubscribe(sym));
    };
    ws.onmessage = (ev) => this.handleMessage(ev);
    ws.onclose = () => {
      this.connected = false; this.connecting = false; this.ws = null;
      if (this.subs.size > 0) setTimeout(() => this.connect(), 1500);
    };
    ws.onerror = () => { try { ws.close(); } catch { /* ignore */ } };
  }

  private send(msg: object) {
    if (this.connected && this.ws) this.ws.send(JSON.stringify(msg));
    else { this.queue.push(msg); this.connect(); }
  }

  private sendSubscribe(symbol: string) {
    const reqId = this.nextReqId++;
    this.reqIdToSymbol.set(reqId, symbol);
    this.send({ ticks_history: symbol, adjust_start_time: 1, count: MAX_CANDLES,
      end: "latest", style: "candles", granularity: GRANULARITY, subscribe: 1, req_id: reqId });
  }

  private handleMessage(ev: MessageEvent) {
    let data: any;
    try { data = JSON.parse(ev.data); } catch { return; }
    if (data.candles) {
      const symbol = (data.req_id && this.reqIdToSymbol.get(data.req_id)) || "";
      if (!symbol) return;
      const list: Candle[] = data.candles.map((c: any) => ({
        epoch: Number(c.epoch), o: Number(c.open), h: Number(c.high), l: Number(c.low), c: Number(c.close),
      }));
      this.candles.set(symbol, this.markSpikes(symbol, list)); this.emit(symbol);
    } else if (data.ohlc) {
      const symbol = data.ohlc.symbol || "";
      if (!symbol || !this.subs.has(symbol)) return;
      const fresh: Candle = {
        epoch: Number(data.ohlc.open_time ?? data.ohlc.epoch),
        o: Number(data.ohlc.open), h: Number(data.ohlc.high),
        l: Number(data.ohlc.low), c: Number(data.ohlc.close),
      };
      const list = this.candles.get(symbol) ?? [];
      const last = list[list.length - 1];
      if (last && last.epoch === fresh.epoch) list[list.length - 1] = fresh;
      else { list.push(fresh); if (list.length > MAX_CANDLES) list.shift(); }
      this.candles.set(symbol, this.markSpikes(symbol, list)); this.emit(symbol);
    }
  }

  private markSpikes(symbol: string, list: Candle[]): Candle[] {
    const window = list.slice(-30);
    const bodies = window.map((c) => Math.abs(c.c - c.o)).sort((a, b) => a - b);
    const med = bodies[Math.floor(bodies.length / 2)] || 0.0001;
    const isBoomCrash = symbol.startsWith("BOOM") || symbol.startsWith("CRASH");
    const mult = isBoomCrash ? 4 : 6;
    return list.map((c) => {
      const body = Math.abs(c.c - c.o);
      return { ...c, spike: body > med * mult && med > 0 };
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
    const cached = this.candles.get(symbol);
    if (cached) fn(cached);
    if (!this.requested.has(symbol)) { this.requested.add(symbol); this.sendSubscribe(symbol); }
    else this.connect();
    return () => { this.subs.get(symbol)?.delete(fn); };
  }
}

const feed = new DerivFeed();

export function useDerivCandles(asset: string): { candles: Candle[]; symbol: string } {
  const symbol = ASSET_SYMBOL[asset] ?? asset;
  const [candles, setCandles] = useState<Candle[]>([]);
  useEffect(() => { setCandles([]); return feed.subscribe(symbol, setCandles); }, [symbol]);
  return { candles, symbol };
}

// ─── Indicator math ───────────────────────────────────────────────────────────

export function smaArr(values: number[], period: number): number[] {
  const out: number[] = [];
  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    out.push(i >= period - 1 ? sum / period : NaN);
  }
  return out;
}

export function emaArr(values: number[], period: number): number[] {
  const out: number[] = [];
  const k = 2 / (period + 1);
  let prev = NaN;
  for (let i = 0; i < values.length; i++) {
    if (isNaN(prev)) prev = values[i];
    else prev = values[i] * k + prev * (1 - k);
    out.push(prev);
  }
  return out;
}

// AO: sma(hl2,5) - sma(hl2,34)  — exact MT5 algorithm
export function calcAO(candles: Candle[]): number[] {
  const hl2 = candles.map((c) => (c.h + c.l) / 2);
  const fast = smaArr(hl2, 5);
  const slow = smaArr(hl2, 34);
  return fast.map((v, i) => (isFinite(v) && isFinite(slow[i]) ? v - slow[i] : NaN));
}

// AC: AO - sma(AO, 5)  — exact MT5 algorithm
export function calcAC(aoSeries: number[]): number[] {
  const valid = aoSeries.map((v) => (isFinite(v) ? v : 0));
  const sig = smaArr(valid, 5);
  return valid.map((v, i) => (isFinite(sig[i]) ? v - sig[i] : NaN));
}

// AO V2 Kivanç: AO line + signal SMA(AO,7)
export function calcAOV2(candles: Candle[]): { ao: number[]; signal: number[] } {
  const ao = calcAO(candles);
  const valid = ao.map((v) => (isFinite(v) ? v : 0));
  return { ao: valid, signal: smaArr(valid, 7) };
}

// MACD for AO & MACD Tactic — tea-saucer detection on AO
export function calcMACDTactic(candles: Candle[]): {
  ao: number[]; macdLine: number[]; signal: number[];
  saucerBull: boolean; saucerBear: boolean;
} {
  const closes = candles.map((c) => c.c);
  const ao = calcAO(candles);
  const ema12 = emaArr(closes, 12);
  const ema26 = emaArr(closes, 26);
  const macdLine = ema12.map((v, i) => v - ema26[i]);
  const signal = emaArr(macdLine, 9);
  const n = ao.length;
  // Tea-saucer: 3 consecutive AO values that dip then rise (bowl shape) all on same side of zero
  const saucerBull = n >= 3 &&
    isFinite(ao[n-3]) && isFinite(ao[n-2]) && isFinite(ao[n-1]) &&
    ao[n-1] > 0 && ao[n-2] > 0 && ao[n-3] > 0 &&
    ao[n-2] < ao[n-3] && ao[n-1] > ao[n-2];
  const saucerBear = n >= 3 &&
    isFinite(ao[n-3]) && isFinite(ao[n-2]) && isFinite(ao[n-1]) &&
    ao[n-1] < 0 && ao[n-2] < 0 && ao[n-3] < 0 &&
    ao[n-2] > ao[n-3] && ao[n-1] < ao[n-2];
  return { ao, macdLine, signal, saucerBull, saucerBear };
}

// Vol-Weighted Change BB  (Bollinger deviation of close from SMA20)
export function calcVWCBB(candles: Candle[]): { value: number; upper: number; lower: number } {
  const closes = candles.map((c) => c.c);
  const last20 = closes.slice(-20);
  const mean = last20.reduce((a, b) => a + b, 0) / last20.length;
  const sd = Math.sqrt(last20.reduce((a, b) => a + (b - mean) ** 2, 0) / last20.length) || 1;
  const last = closes[closes.length - 1];
  return { value: (last - mean) / sd, upper: 2, lower: -2 };
}

// ─── VIX Trend Analysis ───────────────────────────────────────────────────────

export type SwingPoint = { price: number; index: number; type: "HH" | "HL" | "LH" | "LL" };
export type TrendEvent = {
  type: "BOS" | "ChoCH";
  direction: "bull" | "bear";
  price: number;
  index: number;
  description: string;
};

export type VixAnalysis = {
  trend: "bullish" | "bearish" | "ranging";
  structure: SwingPoint[];
  events: TrendEvent[];
  ma20: number;
  ma50: number;
  maCrossed: boolean;
  maCrossDirection: "bull" | "bear" | null;
  maCrossPrice: number | null;
  narratives: string[];
  currentPrice: number;
};

function detectSwings(candles: Candle[], lookback = 3): { highs: number[]; lows: number[] } {
  const highs: number[] = [];
  const lows: number[] = [];
  for (let i = lookback; i < candles.length - lookback; i++) {
    const isHigh = candles.slice(i - lookback, i).every((c) => c.h <= candles[i].h) &&
      candles.slice(i + 1, i + lookback + 1).every((c) => c.h <= candles[i].h);
    const isLow = candles.slice(i - lookback, i).every((c) => c.l >= candles[i].l) &&
      candles.slice(i + 1, i + lookback + 1).every((c) => c.l >= candles[i].l);
    if (isHigh) highs.push(i);
    if (isLow) lows.push(i);
  }
  return { highs, lows };
}

function fmt(n: number): string {
  if (n >= 1000) return n.toFixed(2);
  if (n >= 10) return n.toFixed(3);
  return n.toFixed(4);
}

export function calcVixAnalysis(candles: Candle[]): VixAnalysis | null {
  if (candles.length < 55) return null;
  const closes = candles.map((c) => c.c);
  const ma20Arr = smaArr(closes, 20);
  const ma50Arr = smaArr(closes, 50);
  const ma20 = ma20Arr[ma20Arr.length - 1];
  const ma50 = ma50Arr[ma50Arr.length - 1];
  const currentPrice = closes[closes.length - 1];

  // MA Cross detection (last 5 bars)
  let maCrossed = false;
  let maCrossDirection: "bull" | "bear" | null = null;
  let maCrossPrice: number | null = null;
  for (let i = closes.length - 5; i < closes.length - 1; i++) {
    const prevAbove = ma20Arr[i - 1] > ma50Arr[i - 1];
    const currAbove = ma20Arr[i] > ma50Arr[i];
    if (!prevAbove && currAbove) {
      maCrossed = true; maCrossDirection = "bull"; maCrossPrice = closes[i];
    } else if (prevAbove && !currAbove) {
      maCrossed = true; maCrossDirection = "bear"; maCrossPrice = closes[i];
    }
  }

  // Swing point detection
  const { highs, lows } = detectSwings(candles, 3);
  const structure: SwingPoint[] = [];
  const events: TrendEvent[] = [];

  // Label HH/HL/LH/LL
  let lastHigh = NaN; let lastLow = NaN;
  const recentHighs = highs.slice(-6);
  const recentLows = lows.slice(-6);

  recentHighs.forEach((idx) => {
    const price = candles[idx].h;
    if (isNaN(lastHigh)) { lastHigh = price; structure.push({ price, index: idx, type: "HH" }); }
    else if (price > lastHigh) { structure.push({ price, index: idx, type: "HH" }); lastHigh = price; }
    else { structure.push({ price, index: idx, type: "LH" }); }
  });

  recentLows.forEach((idx) => {
    const price = candles[idx].l;
    if (isNaN(lastLow)) { lastLow = price; structure.push({ price, index: idx, type: "LL" }); }
    else if (price < lastLow) { structure.push({ price, index: idx, type: "LL" }); lastLow = price; }
    else { structure.push({ price, index: idx, type: "HL" }); }
  });

  structure.sort((a, b) => a.index - b.index);

  // BOS / ChoCH detection
  const recentStructure = structure.slice(-8);
  for (let i = 2; i < recentStructure.length; i++) {
    const prev = recentStructure[i - 2];
    const curr = recentStructure[i];
    if (prev.type === "LH" && curr.type === "HH") {
      events.push({ type: "BOS", direction: "bull", price: curr.price, index: curr.index,
        description: `Break of Structure (BOS) at ${fmt(curr.price)} — price broke above the previous lower high, signalling a potential bullish shift` });
    }
    if (prev.type === "HL" && curr.type === "LL") {
      events.push({ type: "BOS", direction: "bear", price: curr.price, index: curr.index,
        description: `Break of Structure (BOS) at ${fmt(curr.price)} — price broke below the previous higher low, signalling a potential bearish shift` });
    }
    if (prev.type === "HH" && curr.type === "LH") {
      events.push({ type: "ChoCH", direction: "bear", price: curr.price, index: curr.index,
        description: `Change of Character (ChoCH) at ${fmt(curr.price)} — market failed to make a new higher high, first sign of bearish character change` });
    }
    if (prev.type === "LL" && curr.type === "HL") {
      events.push({ type: "ChoCH", direction: "bull", price: curr.price, index: curr.index,
        description: `Change of Character (ChoCH) at ${fmt(curr.price)} — market stopped making lower lows, first sign of bullish character change` });
    }
  }

  // Determine trend from recent structure
  const recentHHs = recentStructure.filter((s) => s.type === "HH").length;
  const recentHLs = recentStructure.filter((s) => s.type === "HL").length;
  const recentLLs = recentStructure.filter((s) => s.type === "LL").length;
  const recentLHs = recentStructure.filter((s) => s.type === "LH").length;
  let trend: "bullish" | "bearish" | "ranging" = "ranging";
  if (recentHHs >= 2 && recentHLs >= 1) trend = "bullish";
  else if (recentLLs >= 2 && recentLHs >= 1) trend = "bearish";

  // Build narratives
  const narratives: string[] = [];

  // Trend narrative
  const lastHHPoint = [...recentStructure].reverse().find((s) => s.type === "HH");
  const lastLLPoint = [...recentStructure].reverse().find((s) => s.type === "LL");
  const lastHLPoint = [...recentStructure].reverse().find((s) => s.type === "HL");
  const lastLHPoint = [...recentStructure].reverse().find((s) => s.type === "LH");

  if (trend === "bullish") {
    if (lastHHPoint && lastHLPoint) {
      narratives.push(
        `Market is creating higher highs after HH at ${fmt(lastHHPoint.price)}, supported by a higher low at ${fmt(lastHLPoint.price)} — bullish structure intact`
      );
    }
  } else if (trend === "bearish") {
    if (lastLLPoint && lastLHPoint) {
      narratives.push(
        `Market is printing lower lows after LL at ${fmt(lastLLPoint.price)}, capped by a lower high at ${fmt(lastLHPoint.price)} — bearish structure dominant`
      );
    }
  } else {
    narratives.push(`Market is ranging — no clear sequence of HH/HL or LH/LL established yet`);
  }

  // MA narrative
  const maRelation = ma20 > ma50 ? "above" : "below";
  narratives.push(
    `MA20 (${fmt(ma20)}) is ${maRelation} MA50 (${fmt(ma50)}) — ${ma20 > ma50 ? "bullish" : "bearish"} momentum bias on this timeframe`
  );

  if (maCrossed && maCrossPrice) {
    narratives.push(
      `MA20 crossed ${maCrossDirection === "bull" ? "above" : "below"} MA50 at price ${fmt(maCrossPrice)}, indicating a ${maCrossDirection === "bull" ? "bullish" : "bearish"} momentum shift`
    );
  }

  // Recent event narrative
  const lastEvent = events[events.length - 1];
  if (lastEvent) narratives.push(lastEvent.description);

  // Price vs MA narrative
  if (currentPrice > ma20 && currentPrice > ma50) {
    narratives.push(`Price (${fmt(currentPrice)}) is trading above both moving averages — continuation bias`);
  } else if (currentPrice < ma20 && currentPrice < ma50) {
    narratives.push(`Price (${fmt(currentPrice)}) is trading below both moving averages — downside pressure`);
  } else {
    narratives.push(`Price (${fmt(currentPrice)}) is between the MAs — watch for a decisive break`);
  }

  return { trend, structure: recentStructure, events, ma20, ma50, maCrossed, maCrossDirection, maCrossPrice, narratives, currentPrice };
}

export function calcIndicators(candles: Candle[]) {
  if (candles.length < 35) return null;
  const ao = calcAO(candles);
  const aoLast = ao[ao.length - 1] ?? 0;
  const ac = calcAC(ao);
  const acLast = ac[ac.length - 1] ?? 0;
  const aoTail = ao.slice(-21, -1);
  const aoMax = Math.max(...aoTail.filter((v) => isFinite(v)));
  const aoMin = Math.min(...aoTail.filter((v) => isFinite(v)));
  const aoBreakout: "max" | "min" | "none" =
    aoLast > aoMax ? "max" : aoLast < aoMin ? "min" : "none";
  return { ao: +aoLast.toFixed(4), ac: +acLast.toFixed(4), aoBreakout, aoSeries: ao, acSeries: ac };
}
