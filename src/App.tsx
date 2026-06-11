import { useEffect, useMemo, useRef, useState } from "react";
import { ArrowRight, Activity } from "lucide-react";
import heroTrader from "@/assets/hero-trader.jpg";
import { useDerivCandles, calcIndicators, type Candle } from "@/lib/deriv";

type View = "intro" | "signals" | "indicators";

export default function App() {
  const [view, setView] = useState<View>("intro");
  const [activeAsset, setActiveAsset] = useState<string>("BOOM1000");

  return (
    <div className="min-h-screen w-full bg-neutral-200 text-neutral-100 flex items-center justify-center px-4 py-6">
      <div className="w-full max-w-[420px]">
        {view === "intro" && <IntroPage onNext={() => setView("signals")} />}
        {view === "signals" && (
          <SignalsScroller
            onOpenIndicators={(asset) => {
              setActiveAsset(asset);
              setView("indicators");
            }}
          />
        )}
        {view === "indicators" && (
          <IndicatorsPage asset={activeAsset} onBack={() => setView("signals")} />
        )}
      </div>
    </div>
  );
}

function IntroPage({ onNext }: { onNext: () => void }) {
  return (
    <div className="relative overflow-hidden rounded-[2.5rem] shadow-2xl aspect-[9/19.5] bg-neutral-900">
      <img
        src={heroTrader}
        alt="Trader watching candlestick charts"
        className="absolute inset-0 h-full w-full object-cover"
      />
      <div className="absolute inset-0 bg-gradient-to-b from-black/30 via-black/10 to-black/70" />

      <div className="relative px-7 pt-5 flex gap-1.5">
        {[0, 1].map((i) => (
          <div key={i} className="flex-1 h-[3px] rounded-full bg-white/30 overflow-hidden">
            <div className={`h-full bg-white ${i === 0 ? "w-full" : "w-0"}`} />
          </div>
        ))}
      </div>

      <div className="relative px-7 mt-6 text-white text-2xl font-semibold tracking-tight">
        spike<span className="text-amber-300">.</span>
      </div>

      <div className="absolute inset-x-0 bottom-0 p-7 pb-8">
        <h1 className="text-white text-[56px] font-bold leading-[0.95] tracking-tight">
          Trading
          <br />
          made
          <br />
          simple.
        </h1>
        <p className="mt-4 text-white/85 text-base">
          Signals at your<br />fingertips.
        </p>
        <SlideToContinue onComplete={onNext} />
      </div>
    </div>
  );
}

function SlideToContinue({ onComplete }: { onComplete: () => void }) {
  const trackRef = useRef<HTMLDivElement>(null);
  const [x, setX] = useState(0);
  const [dragging, setDragging] = useState(false);
  const draggingRef = useRef(false);
  const startXRef = useRef(0);
  const maxRef = useRef(0);

  const begin = (clientX: number) => {
    const track = trackRef.current;
    if (!track) return;
    maxRef.current = track.clientWidth - 56 - 8;
    startXRef.current = clientX - x;
    draggingRef.current = true;
    setDragging(true);
  };
  const move = (clientX: number) => {
    if (!draggingRef.current) return;
    setX(Math.max(0, Math.min(maxRef.current, clientX - startXRef.current)));
  };
  const end = () => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    setDragging(false);
    if (x >= maxRef.current - 4) {
      setX(maxRef.current);
      setTimeout(onComplete, 120);
    } else setX(0);
  };

  return (
    <div
      ref={trackRef}
      className="mt-8 relative h-14 rounded-full bg-black/45 backdrop-blur-md p-1 overflow-hidden select-none"
      onMouseMove={(e) => move(e.clientX)}
      onMouseUp={end}
      onMouseLeave={end}
      onTouchMove={(e) => move(e.touches[0].clientX)}
      onTouchEnd={end}
    >
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        <span className="text-white/80 font-medium tracking-wide text-sm flex items-center gap-2">
          Slide to continue <ArrowRight className="h-4 w-4" />
        </span>
      </div>
      <div
        role="slider"
        aria-label="Slide to continue"
        className={`relative h-12 w-14 rounded-full bg-amber-200 text-neutral-900 grid place-items-center shadow-lg touch-none ${
          dragging ? "" : "transition-transform duration-200"
        }`}
        style={{ transform: `translateX(${x}px)` }}
        onMouseDown={(e) => begin(e.clientX)}
        onTouchStart={(e) => begin(e.touches[0].clientX)}
      >
        <ArrowRight className="h-5 w-5" />
      </div>
    </div>
  );
}

const ASSETS = ["BOOM1000", "CRASH1000", "VIX75", "VIX75 1s"] as const;
type Asset = (typeof ASSETS)[number];

function SignalsScroller({
  onOpenIndicators,
}: {
  onOpenIndicators: (asset: string) => void;
}) {
  return (
    <div className="rounded-[2rem] overflow-hidden shadow-2xl bg-neutral-900 border border-neutral-800">
      <div
        className="h-[760px] overflow-y-auto snap-y snap-mandatory scroll-smooth"
        style={{ scrollbarWidth: "none" }}
      >
        {ASSETS.map((a) => (
          <div key={a} data-asset-page className="snap-start h-[760px]">
            <SignalPage asset={a} onOpenIndicators={() => onOpenIndicators(a)} />
          </div>
        ))}
      </div>
    </div>
  );
}

function SignalPage({
  asset,
  onOpenIndicators,
}: {
  asset: Asset;
  onOpenIndicators: () => void;
}) {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);

  const seconds = 60 - (tick % 60);
  const { candles } = useDerivCandles(asset);
  const hasData = candles.length > 0;

  const lastSpikeIdx = [...candles].map((c) => c.spike).lastIndexOf(true);
  const candlesSinceSpike =
    lastSpikeIdx === -1 ? candles.length : candles.length - 1 - lastSpikeIdx;
  const justSpiked = candles[candles.length - 1]?.spike;
  const summary = !hasData
    ? "Connecting to Deriv…"
    : justSpiked
    ? "A spike just occurred"
    : `${candlesSinceSpike} candle${candlesSinceSpike === 1 ? "" : "s"} created since last spike`;

  return (
    <div className="relative h-full flex flex-col">
      <div className="px-5 pt-5 pb-3 flex items-center justify-between">
        <div className="text-xs uppercase tracking-[0.2em] text-neutral-500">{asset}</div>
        <div className="flex items-center gap-2 text-xs text-neutral-400">
          <span className="h-1.5 w-1.5 rounded-full bg-amber-400 animate-pulse" />
          {String(seconds).padStart(2, "0")}s
        </div>
      </div>

      <div className="relative px-3 flex-1 min-h-0 flex">
        <CandleChart candles={candles} />
        <button
          onClick={onOpenIndicators}
          aria-label={`Open ${asset} indicators`}
          className="absolute top-1/2 -translate-y-1/2 right-5 h-11 w-11 rounded-full bg-amber-300 text-neutral-900 grid place-items-center shadow-xl active:scale-95 transition"
        >
          <Activity className="h-5 w-5" />
        </button>
      </div>

      <div className="px-5 pt-3">
        <div className="text-sm text-neutral-400">{summary}</div>
      </div>

      <div className="px-5 pt-3">
        <button className="w-full h-14 rounded-2xl bg-neutral-50 text-neutral-900 font-bold tracking-[0.25em] text-base shadow-xl active:scale-[0.99] transition">
          SCANNING
        </button>
      </div>

      <div className="px-5 pb-3 flex items-center justify-center gap-2">
        {ASSETS.map((a) => (
          <div
            key={a}
            className={`h-1.5 rounded-full transition-all ${
              a === asset ? "w-6 bg-amber-300" : "w-1.5 bg-neutral-600"
            }`}
          />
        ))}
      </div>

      <button
        onClick={(e) => {
          const page = (e.currentTarget as HTMLElement).closest("[data-asset-page]");
          const next = page?.nextElementSibling as HTMLElement | null;
          if (next) next.scrollIntoView({ behavior: "smooth" });
          else page?.parentElement?.firstElementChild?.scrollIntoView({ behavior: "smooth" });
        }}
        className="mx-auto mb-5 flex flex-col items-center gap-1 text-neutral-500 hover:text-amber-300 transition active:translate-y-0.5"
        aria-label="Swipe to next asset"
      >
        <span className="text-[10px] tracking-[0.3em]">SWIPE</span>
        <span className="text-2xl leading-none animate-bounce">⌄</span>
      </button>
    </div>
  );
}

function IndicatorsPage({ asset, onBack }: { asset: string; onBack: () => void }) {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);
  const seconds = 60 - (tick % 60);

  const isBoom = asset.startsWith("BOOM");
  const isCrash = asset.startsWith("CRASH");

  const { candles } = useDerivCandles(asset);
  const ind = useMemo(() => calcIndicators(candles), [candles]);
  const hasInd = !!ind;

  const ao = ind?.ao ?? 0;
  const ac = ind?.ac ?? 0;

  const votes = {
    AO: ao < -2 ? 1 : ao > 2 ? -1 : 0,
    AC: ac < -1 ? 1 : ac > 1 ? -1 : 0,
  };
  const total = Object.values(votes).reduce((a, b) => a + b, 0);
  const totalAbs = Object.values(votes).reduce((a, b) => a + Math.abs(b), 0);
  const majority = hasInd && totalAbs >= 2 && Math.abs(total) === totalAbs;
  const biasDirection = total > 0 ? "BUY" : total < 0 ? "SELL" : null;
  const direction = isBoom ? "SELL" : isCrash ? "BUY" : biasDirection ?? "BUY";
  const aligned = majority;

  return (
    <div className="rounded-[2rem] bg-neutral-900 border border-neutral-800 shadow-2xl overflow-hidden">
      <div className="px-5 pt-5 pb-3 flex items-center justify-between">
        <button
          onClick={onBack}
          className="h-9 w-9 rounded-full bg-neutral-800 grid place-items-center text-neutral-300 active:scale-95"
          aria-label="Back"
        >
          ←
        </button>
        <div className="text-xs uppercase tracking-[0.2em] text-neutral-500">
          {asset} · Indicators
        </div>
        <div className="text-xs text-neutral-400">{String(seconds).padStart(2, "0")}s</div>
      </div>

      <div
        className="px-5 py-4 space-y-3 max-h-[460px] overflow-y-auto"
        style={{ scrollbarWidth: "none" }}
      >
        <OscillatorBar label="Awesome Oscillator" value={ao} max={20} />
        <OscillatorBar label="Accelerator Oscillator" value={ac} max={8} />

        <div className="pt-2 pb-1 flex items-center gap-2">
          <div className="h-px flex-1 bg-neutral-800" />
          <span className="text-[10px] tracking-[0.25em] text-teal-400/80 font-mono">
            GARDEN OF SWORDS
          </span>
          <div className="h-px flex-1 bg-neutral-800" />
        </div>

        <GardenCard index={1} title="AO V2 (Kıvanç)" subtitle="Signal-line variant tracker" paramLabel="SIG" paramValue="7" tick={tick} seed={11} palette="ao" />
        <GardenCard index={2} title="AO & MACD Tactic" subtitle="Tea-saucer & dynamic cross signals" badge={Math.sin(tick / 5) > 0.7 ? "SAUCER" : "NO SAUCER"} tick={tick} seed={23} palette="signal" />
        <GardenCard index={3} title="Classic AO (Orekhov)" subtitle="Standard 5/34 block momentum scale" tick={tick} seed={37} palette="ao" />
        <GardenCard index={4} title="Awesome Oscillator Plus" subtitle="Advanced MA variations" paramLabel="MA" paramValue="2PSS" tick={tick} seed={53} palette="ao" />
        <GardenCard index={5} title="Multi-Method AO" subtitle="Breakout monitoring framework" paramLabel="EMA" paramValue="50" tick={tick} seed={71} palette="ao" />
        <GardenCard index={6} title="Vol-Weighted Change BB" subtitle="Cumulative deviation envelopes" paramLabel="BB" paramValue="20" tick={tick} seed={89} palette="ao" />
      </div>

      <div className="px-5 py-3 text-sm text-neutral-400">
        {aligned
          ? `Majority of indicators aligned (${Math.abs(total)}/${totalAbs})`
          : `Waiting for majority alignment… (${total >= 0 ? "+" : ""}${total}/${totalAbs})`}
      </div>

      <div className="p-5">
        <button
          className={`w-full h-16 rounded-2xl font-bold tracking-[0.25em] text-lg shadow-xl transition ${
            aligned ? "bg-neutral-50" : "bg-neutral-800 text-neutral-500"
          }`}
        >
          {aligned ? (
            <>
              <span className={direction === "SELL" ? "text-rose-500" : "text-emerald-500"}>
                {direction}
              </span>
              <span className="text-neutral-500"> · SIGNAL</span>
            </>
          ) : (
            "SCANNING…"
          )}
        </button>
      </div>
    </div>
  );
}

function OscillatorBar({ label, value, max }: { label: string; value: number; max: number }) {
  const pct = Math.max(-1, Math.min(1, value / max));
  const positive = pct >= 0;
  return (
    <div className="rounded-xl bg-neutral-800/60 border border-neutral-800 p-3">
      <div className="flex justify-between text-xs">
        <span className="text-neutral-400">{label}</span>
        <span className={`font-mono ${positive ? "text-emerald-400" : "text-rose-400"}`}>
          {value > 0 ? "+" : ""}
          {value.toFixed(2)}
        </span>
      </div>
      <div className="mt-2 relative h-2 rounded-full bg-neutral-900 overflow-hidden">
        <div className="absolute left-1/2 top-0 bottom-0 w-px bg-neutral-700" />
        <div
          className={`absolute top-0 bottom-0 ${positive ? "bg-emerald-500" : "bg-rose-500"}`}
          style={{
            left: positive ? "50%" : `${50 + pct * 50}%`,
            width: `${Math.abs(pct) * 50}%`,
          }}
        />
      </div>
    </div>
  );
}

function GardenCard({
  index,
  title,
  subtitle,
  paramLabel,
  paramValue,
  badge,
  tick,
  seed,
  mode = "histogram",
  palette = "ao",
}: {
  index: number;
  title: string;
  subtitle: string;
  paramLabel?: string;
  paramValue?: string;
  badge?: string;
  tick: number;
  seed: number;
  mode?: "histogram" | "bands";
  palette?: "ao" | "signal";
}) {
  const bars = useMemo(() => {
    const arr: number[] = [];
    for (let i = 0; i < 48; i++) {
      const v =
        Math.sin((tick + i) / 6 + seed * 0.13) * 0.7 +
        Math.cos((tick + i) / 11 + seed * 0.07) * 0.4 +
        Math.sin((tick + i) / 3 + seed) * 0.25;
      arr.push(v);
    }
    return arr;
  }, [tick, seed]);

  const w = 320;
  const h = 64;
  const max = Math.max(1, ...bars.map((b) => Math.abs(b)));
  const bw = w / bars.length;
  const mid = h / 2;

  return (
    <div className="rounded-xl bg-neutral-900/70 border border-white/5 p-3 shadow-lg backdrop-blur-sm">
      <div className="flex items-start justify-between mb-2">
        <div className="min-w-0">
          <h3 className="text-[11px] font-bold uppercase tracking-wider text-teal-400 font-mono truncate">
            {index}. {title}
          </h3>
          <p className="text-[10px] text-neutral-500 font-mono truncate">{subtitle}</p>
        </div>
        {badge ? (
          <span
            className={`text-[9px] px-1.5 py-0.5 rounded font-mono font-bold border ${
              badge === "SAUCER"
                ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/30"
                : "bg-neutral-800 text-neutral-500 border-neutral-700"
            }`}
          >
            {badge}
          </span>
        ) : paramLabel ? (
          <div className="flex items-center gap-1 text-[10px] font-mono">
            <span className="text-neutral-500">{paramLabel}</span>
            <span className="px-1.5 py-0.5 rounded bg-neutral-950 border border-neutral-800 text-neutral-300 min-w-[28px] text-center">
              {paramValue}
            </span>
          </div>
        ) : null}
      </div>
      <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full h-14 block">
        <line x1={0} x2={w} y1={mid} y2={mid} stroke="rgb(38 38 38)" strokeDasharray="2 3" />
        {mode === "bands" && (
          <>
            <line x1={0} x2={w} y1={mid - 18} y2={mid - 18} stroke="rgb(20 184 166 / 0.25)" />
            <line x1={0} x2={w} y1={mid + 18} y2={mid + 18} stroke="rgb(20 184 166 / 0.25)" />
            <polyline
              fill="none"
              stroke="rgb(94 234 212)"
              strokeWidth="1.4"
              points={bars
                .map((v, i) => `${i * bw + bw / 2},${mid - (v / max) * (mid - 4)}`)
                .join(" ")}
            />
          </>
        )}
        {mode === "histogram" &&
          bars.map((v, i) => {
            const up = v >= 0;
            const bh = Math.max(1.5, (Math.abs(v) / max) * (mid - 3));
            return (
              <rect
                key={i}
                x={i * bw + 1}
                y={up ? mid - bh : mid}
                width={Math.max(1, bw - 2)}
                height={bh}
                fill={palette === "ao" ? (up ? "#f59e0b" : "#3f3f46") : up ? "#14b8a6" : "#f43f5e"}
                opacity={0.85}
              />
            );
          })}
      </svg>
    </div>
  );
}

function CandleChart({ candles }: { candles: Candle[] }) {
  const w = 360;
  const h = 200;
  const pad = 8;
  if (candles.length === 0) {
    return (
      <div className="flex-1 rounded-2xl bg-black/60 border border-neutral-800 p-2 grid place-items-center text-neutral-600 text-xs font-mono">
        connecting to deriv…
      </div>
    );
  }
  const min = Math.min(...candles.map((c) => c.l));
  const max = Math.max(...candles.map((c) => c.h));
  const range = max - min || 1;
  const cw = (w - pad * 2) / candles.length;
  const y = (v: number) => pad + (1 - (v - min) / range) * (h - pad * 2);

  return (
    <div className="flex-1 rounded-2xl bg-black/60 border border-neutral-800 p-2">
      <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full h-full block">
        <line
          x1={pad}
          x2={w - pad}
          y1={h / 2}
          y2={h / 2}
          stroke="rgb(64 64 64)"
          strokeDasharray="3 4"
        />
        {candles.map((c, i) => {
          const x = pad + i * cw + cw / 2;
          const up = c.c >= c.o;
          const color = c.spike ? "#f59e0b" : up ? "#60a5fa" : "#60a5fa";
          return (
            <g key={i}>
              <line x1={x} x2={x} y1={y(c.h)} y2={y(c.l)} stroke={color} strokeWidth={1.2} />
              <rect
                x={x - cw * 0.32}
                y={y(Math.max(c.o, c.c))}
                width={cw * 0.64}
                height={Math.max(1.5, Math.abs(y(c.o) - y(c.c)))}
                fill={color}
                opacity={c.spike ? 1 : 0.9}
              />
            </g>
          );
        })}
      </svg>
    </div>
  );
}
