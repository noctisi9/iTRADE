import { useEffect, useRef, useState, useMemo, useCallback } from "react";
import { ArrowRight, Menu, X, BookOpen, Clock, Download, ChevronLeft, ChevronRight } from "lucide-react";

import intro1 from "@/assets/intro/intro1.jpg";
import intro2 from "@/assets/intro/intro2.jpg";
import intro3 from "@/assets/intro/intro3.jpg";
import intro4 from "@/assets/intro/intro4.jpg";
import intro5 from "@/assets/intro/intro5.jpg";
import intro6 from "@/assets/intro/intro6.jpg";
import intro7 from "@/assets/intro/intro7.jpg";

import {
  useDerivCandles, calcIndicators, calcAO, calcAC, calcAOV2,
  calcMACDTactic, calcVixAnalysis, smaArr, type Candle,
} from "@/lib/deriv";
import {
  logCandle, saveState, loadState, getDaySummaries,
  getEntriesForDay, getEntriesForWeek, generateDailyCSV,
  generateWeeklyCSV, downloadAsFile, type JournalEntry,
} from "@/lib/journal";

// ─── THEME ───────────────────────────────────────────────────────────────────
const C = {
  bg: "#02060E",
  card: "#0A1020",
  cardHover: "#0F1828",
  border: "#2A1520",
  borderBright: "#4A2030",
  crimson: "#C50337",
  crimsonDim: "#8B0226",
  crimsonGlow: "#FF1050",
  crimsonFaint: "#3A0115",
  white: "#FFFFFF",
  textBright: "#F0E8EA",
  text: "#C8B8BC",
  textDim: "#8A7075",
  textMuted: "#4A3540",
};

const INTRO_IMAGES = [intro1, intro2, intro3, intro4, intro5, intro6, intro7];
const ASSETS = ["BOOM1000", "CRASH1000", "VIX75", "VIX75 1s"] as const;
type Asset = (typeof ASSETS)[number];
type View = "intro" | "signals" | "indicators" | "journal" | "history";
const isVix = (a: string) => a.startsWith("VIX");

// ─── ROOT APP ────────────────────────────────────────────────────────────────
export default function App() {
  const [view, setView] = useState<View>("intro");
  const [activeAsset, setActiveAsset] = useState<Asset>("BOOM1000");
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [journalAsset, setJournalAsset] = useState<Asset>("BOOM1000");
  const [stateLoaded, setStateLoaded] = useState(false);

  // Restore state on mount
  useEffect(() => {
    loadState().then((s) => {
      if (s.view && s.view !== "intro") setView(s.view as View);
      if (s.activeAsset) setActiveAsset(s.activeAsset as Asset);
      if (s.journalAsset) setJournalAsset(s.journalAsset as Asset);
      setStateLoaded(true);
    });
  }, []);

  // Persist state
  useEffect(() => {
    if (!stateLoaded) return;
    saveState({ view, activeAsset, journalAsset });
  }, [view, activeAsset, journalAsset, stateLoaded]);

  // Hardware back button interception
  useEffect(() => {
    const onBack = (e: PopStateEvent) => {
      e.preventDefault();
      if (drawerOpen) { setDrawerOpen(false); return; }
      if (view === "indicators") { setView("signals"); return; }
      if (view === "journal" || view === "history") { setView("signals"); return; }
      if (view === "signals") { setView("intro"); return; }
      // On intro, allow actual exit
    };
    window.history.pushState(null, "", window.location.href);
    window.addEventListener("popstate", onBack);
    return () => window.removeEventListener("popstate", onBack);
  }, [view, drawerOpen]);

  // Re-push state so back button always has something to pop
  useEffect(() => {
    window.history.pushState(null, "", window.location.href);
  }, [view]);

  const navigate = (v: View) => { setView(v); setDrawerOpen(false); };

  return (
    <div className="w-screen h-screen overflow-hidden relative flex flex-col" style={{ background: C.bg }}>
      {/* Drawer overlay */}
      {drawerOpen && (
        <div className="absolute inset-0 z-50 flex" style={{ backdropFilter: "blur(4px)" }}>
          <div className="w-72 h-full flex flex-col shadow-2xl" style={{ background: C.card, borderRight: `1px solid ${C.borderBright}` }}>
            <div className="flex items-center justify-between px-6 pt-10 pb-6">
              <span className="text-2xl font-black tracking-widest" style={{ color: C.crimson }}>NOCTIS</span>
              <button onClick={() => setDrawerOpen(false)} style={{ color: C.textDim }}>
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="h-px mx-6 mb-6" style={{ background: C.border }} />
            <nav className="flex-1 px-4 space-y-2">
              <DrawerItem icon={<BookOpen className="h-4 w-4" />} label="Journal" onClick={() => navigate("journal")} active={view === "journal"} />
              <DrawerItem icon={<Clock className="h-4 w-4" />} label="History" onClick={() => navigate("history")} active={view === "history"} />
            </nav>
            <div className="px-6 pb-10">
              <p className="text-[11px] font-mono" style={{ color: C.textMuted }}>iTRADE · NOCTIS EA · v2.0</p>
            </div>
          </div>
          <div className="flex-1" onClick={() => setDrawerOpen(false)} />
        </div>
      )}

      {/* Header bar (not on intro) */}
      {view !== "intro" && (
        <div className="flex-shrink-0 flex items-center justify-between px-5 pt-safe pt-4 pb-3" style={{ background: C.bg, borderBottom: `1px solid ${C.border}` }}>
          <button onClick={() => setDrawerOpen(true)} className="h-10 w-10 rounded-full grid place-items-center" style={{ background: C.card, border: `1px solid ${C.borderBright}` }}>
            <Menu className="h-5 w-5" style={{ color: C.crimson }} />
          </button>
          <span className="text-base font-black tracking-[0.35em]" style={{ color: C.crimson }}>NOCTIS</span>
          <div className="h-2.5 w-2.5 rounded-full animate-pulse" style={{ background: C.crimson }} />
        </div>
      )}

      {/* Main content — fills remaining height */}
      <div className="flex-1 overflow-hidden">
        {view === "intro" && <IntroPage onNext={() => navigate("signals")} />}
        {view === "signals" && (
          <SignalsScroller
            activeAsset={activeAsset}
            onAssetChange={setActiveAsset}
            onOpenIndicators={(a) => { setActiveAsset(a as Asset); navigate("indicators"); }}
          />
        )}
        {view === "indicators" && (
          <IndicatorsPage asset={activeAsset} onBack={() => navigate("signals")} />
        )}
        {view === "journal" && (
          <div className="h-full overflow-y-auto px-4 py-4" style={{ scrollbarWidth: "none" }}>
            <JournalPage asset={journalAsset} onAssetChange={(a) => setJournalAsset(a as Asset)} />
          </div>
        )}
        {view === "history" && (
          <div className="h-full overflow-y-auto px-4 py-4" style={{ scrollbarWidth: "none" }}>
            <HistoryPage asset={journalAsset} onAssetChange={(a) => setJournalAsset(a as Asset)} />
          </div>
        )}
      </div>
    </div>
  );
}

function DrawerItem({ icon, label, onClick, active }: { icon: React.ReactNode; label: string; onClick: () => void; active: boolean }) {
  return (
    <button onClick={onClick} className="w-full flex items-center gap-3 px-4 py-3.5 rounded-xl text-left transition"
      style={{ background: active ? C.crimsonFaint : "transparent", color: active ? C.crimson : C.text, border: `1px solid ${active ? C.crimsonDim : "transparent"}` }}>
      {icon}
      <span className="text-sm font-bold tracking-wider">{label}</span>
    </button>
  );
}

// ─── INTRO ────────────────────────────────────────────────────────────────────
function IntroPage({ onNext }: { onNext: () => void }) {
  const [imgIdx, setImgIdx] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setImgIdx((i) => (i + 1) % INTRO_IMAGES.length), 3500);
    return () => clearInterval(id);
  }, []);

  const trackRef = useRef<HTMLDivElement>(null);
  const [x, setX] = useState(0);
  const draggingRef = useRef(false);
  const startXRef = useRef(0);
  const maxRef = useRef(0);

  const begin = (clientX: number) => {
    if (!trackRef.current) return;
    maxRef.current = trackRef.current.clientWidth - 72 - 8;
    startXRef.current = clientX - x;
    draggingRef.current = true;
  };
  const move = (clientX: number) => {
    if (!draggingRef.current) return;
    setX(Math.max(0, Math.min(maxRef.current, clientX - startXRef.current)));
  };
  const end = () => {
    if (!draggingRef.current) return;
    draggingRef.current = false;
    if (x >= maxRef.current - 4) { setX(maxRef.current); setTimeout(onNext, 120); }
    else setX(0);
  };

  return (
    <div className="w-full h-full relative overflow-hidden">
      {INTRO_IMAGES.map((img, i) => (
        <img key={i} src={img} alt="" className="absolute inset-0 h-full w-full object-cover transition-opacity duration-1500"
          style={{ opacity: i === imgIdx ? 1 : 0 }} />
      ))}
      <div className="absolute inset-0" style={{ background: "linear-gradient(to bottom, rgba(2,6,14,0.5) 0%, rgba(2,6,14,0.05) 35%, rgba(2,6,14,0.9) 75%, rgba(2,6,14,1) 100%)" }} />

      {/* Branding top */}
      <div className="relative px-8 pt-14">
        <span className="text-3xl font-black tracking-tight text-white">
          spike<span style={{ color: C.crimson }}>.</span>
        </span>
      </div>

      {/* Bottom content */}
      <div className="absolute inset-x-0 bottom-0 px-8 pb-14">
        <h1 className="text-white font-black leading-[0.92] tracking-tight" style={{ fontSize: "clamp(48px, 13vw, 64px)" }}>
          Trading<br />made<br />simple.
        </h1>
        <p className="mt-4 text-base" style={{ color: C.text }}>Signals at your<br />fingertips.</p>

        {/* Slide track */}
        <div ref={trackRef}
          className="mt-10 relative h-16 rounded-full p-1.5 overflow-hidden select-none"
          style={{ background: "rgba(2,6,14,0.7)", border: `1px solid ${C.crimsonDim}`, backdropFilter: "blur(12px)" }}
          onMouseMove={(e) => move(e.clientX)} onMouseUp={end} onMouseLeave={end}
          onTouchMove={(e) => { e.preventDefault(); move(e.touches[0].clientX); }} onTouchEnd={end}>
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <span className="text-sm font-bold tracking-widest flex items-center gap-2" style={{ color: C.textDim }}>
              Slide to Continue <ArrowRight className="h-4 w-4" />
            </span>
          </div>
          <div role="slider" aria-label="Slide to continue"
            className="relative h-12 w-16 rounded-full grid place-items-center shadow-2xl touch-none"
            style={{ background: C.crimson, transform: `translateX(${x}px)`, transition: draggingRef.current ? "none" : "transform 0.2s" }}
            onMouseDown={(e) => begin(e.clientX)}
            onTouchStart={(e) => begin(e.touches[0].clientX)}>
            <span className="text-[11px] font-black text-white tracking-widest">GO</span>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── SIGNALS SCROLLER ────────────────────────────────────────────────────────
function SignalsScroller({ activeAsset, onAssetChange, onOpenIndicators }: {
  activeAsset: Asset; onAssetChange: (a: Asset) => void; onOpenIndicators: (a: string) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const idx = ASSETS.indexOf(activeAsset);
    const pages = containerRef.current?.querySelectorAll("[data-asset-page]");
    if (pages && pages[idx]) pages[idx].scrollIntoView({ behavior: "auto" });
  }, []);

  return (
    <div ref={containerRef} className="h-full overflow-y-auto snap-y snap-mandatory" style={{ scrollbarWidth: "none" }}>
      {ASSETS.map((a) => (
        <div key={a} data-asset-page className="h-full snap-start flex-shrink-0">
          <SignalPage asset={a} onOpenIndicators={() => onOpenIndicators(a)} onVisible={() => onAssetChange(a)} />
        </div>
      ))}
    </div>
  );
}

function SignalPage({ asset, onOpenIndicators, onVisible }: { asset: Asset; onOpenIndicators: () => void; onVisible: () => void }) {
  const [tick, setTick] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => { const id = setInterval(() => setTick((t) => t + 1), 1000); return () => clearInterval(id); }, []);
  const seconds = 60 - (tick % 60);
  const { candles } = useDerivCandles(asset);
  const vix = isVix(asset);

  // Log candles
  useEffect(() => {
    if (!candles.length) return;
    const last = candles[candles.length - 1];
    const ind = calcIndicators(candles);
    if (!ind) return;
    const lastSpikeIdx = [...candles].map((c) => c.spike).lastIndexOf(true);
    const candlesSinceSpike = lastSpikeIdx === -1 ? candles.length : candles.length - 1 - lastSpikeIdx;
    const vixData = vix ? calcVixAnalysis(candles) : null;
    const structureTag = vixData?.events[vixData.events.length - 1]?.type ?? vixData?.structure[vixData.structure.length - 1]?.type;
    logCandle({ asset, epoch: last.epoch, open: last.o, high: last.h, low: last.l, close: last.c,
      movement: Math.abs(last.o - last.c), spike: !!last.spike, candlesSinceSpike,
      ao: ind.ao, ac: ind.ac, structureTag }).catch(() => {});
  }, [candles.length, asset]);

  // Intersection observer
  useEffect(() => {
    if (!ref.current) return;
    const obs = new IntersectionObserver(([e]) => { if (e.isIntersecting) onVisible(); }, { threshold: 0.6 });
    obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);

  const lastSpikeIdx = !vix ? [...candles].map((c) => c.spike).lastIndexOf(true) : -1;
  const candlesSinceSpike = lastSpikeIdx === -1 ? candles.length : candles.length - 1 - lastSpikeIdx;
  const justSpiked = !vix && candles[candles.length - 1]?.spike;
  let summary = !candles.length ? "Connecting to Deriv…"
    : vix ? (calcVixAnalysis(candles)?.trend === "bullish" ? "Bullish structure forming"
      : calcVixAnalysis(candles)?.trend === "bearish" ? "Bearish structure dominant" : "Ranging")
    : justSpiked ? "⚡ Spike just occurred"
    : `${candlesSinceSpike} candle${candlesSinceSpike === 1 ? "" : "s"} since last spike`;

  const currentPrice = candles[candles.length - 1]?.c;

  return (
    <div ref={ref} className="h-full flex flex-col px-4 py-3">
      {/* Asset + timer */}
      <div className="flex items-center justify-between mb-2">
        <div>
          <span className="text-xs font-black tracking-[0.25em]" style={{ color: C.white }}>{asset}</span>
          {currentPrice && <span className="ml-3 text-xs font-mono" style={{ color: C.textDim }}>{currentPrice.toFixed(3)}</span>}
        </div>
        <div className="flex items-center gap-2">
          <span className="h-2 w-2 rounded-full animate-pulse" style={{ background: C.crimson }} />
          <span className="text-xs font-mono font-bold" style={{ color: C.crimson }}>{String(seconds).padStart(2, "0")}s</span>
        </div>
      </div>

      {/* Chart — takes available space */}
      <div className="relative flex-1 min-h-0">
        <CandleChart candles={candles} vix={vix} />
        <button onClick={onOpenIndicators}
          className="absolute top-1/2 -translate-y-1/2 right-3 h-12 w-12 rounded-full grid place-items-center shadow-2xl active:scale-95 transition-transform"
          style={{ background: C.crimson, boxShadow: `0 0 20px ${C.crimson}60` }}>
          <span className="text-white text-xl">⚡</span>
        </button>
      </div>

      {/* Summary */}
      <div className="mt-2 mb-2">
        <span className="text-sm font-mono" style={{ color: C.text }}>{summary}</span>
      </div>

      {/* Scan button */}
      <button className="w-full h-12 rounded-2xl font-black tracking-[0.3em] text-sm mb-2"
        style={{ background: C.crimsonFaint, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
        SCANNING
      </button>

      {/* Dots + swipe */}
      <div className="flex items-center justify-center gap-2 mb-1">
        {ASSETS.map((a) => (
          <div key={a} className="h-1.5 rounded-full transition-all duration-300"
            style={{ width: a === asset ? 28 : 6, background: a === asset ? C.crimson : C.textMuted }} />
        ))}
      </div>
      <button onClick={(e) => {
        const page = (e.currentTarget as HTMLElement).closest("[data-asset-page]");
        const next = page?.nextElementSibling as HTMLElement | null;
        if (next) next.scrollIntoView({ behavior: "smooth" });
        else page?.parentElement?.firstElementChild?.scrollIntoView({ behavior: "smooth" });
      }} className="flex flex-col items-center gap-0 pb-1" style={{ color: C.textMuted }}>
        <span className="text-[9px] tracking-[0.35em]">SWIPE</span>
        <span className="text-lg animate-bounce leading-none">⌄</span>
      </button>
    </div>
  );
}

// ─── INDICATORS PAGE ──────────────────────────────────────────────────────────
function IndicatorsPage({ asset, onBack }: { asset: string; onBack: () => void }) {
  const [tick, setTick] = useState(0);
  useEffect(() => { const id = setInterval(() => setTick((t) => t + 1), 1000); return () => clearInterval(id); }, []);
  const seconds = 60 - (tick % 60);
  const vix = isVix(asset);
  const { candles } = useDerivCandles(asset);

  return (
    <div className="h-full flex flex-col">
      <div className="flex-shrink-0 px-4 py-3 flex items-center justify-between" style={{ borderBottom: `1px solid ${C.border}` }}>
        <div>
          <p className="text-sm font-black tracking-wider" style={{ color: C.white }}>{asset}</p>
          <p className="text-[10px] font-black tracking-[0.3em]" style={{ color: C.crimson }}>GARDEN OF SWORDS</p>
        </div>
        <div className="flex items-center gap-3">
          <span className="text-xs font-mono font-bold" style={{ color: C.crimson }}>{String(seconds).padStart(2, "0")}s</span>
        </div>
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-3" style={{ scrollbarWidth: "none" }}>
        {vix ? <VixIndicators candles={candles} asset={asset} tick={tick} /> : <SpikeIndicators candles={candles} asset={asset} tick={tick} />}
      </div>
    </div>
  );
}

// ─── CANDLE CHART ─────────────────────────────────────────────────────────────
function CandleChart({ candles, vix }: { candles: Candle[]; vix: boolean }) {
  if (!candles.length) return (
    <div className="w-full h-full rounded-2xl grid place-items-center text-sm font-mono"
      style={{ background: C.card, border: `1px solid ${C.border}`, color: C.textMuted }}>
      Connecting to Deriv…
    </div>
  );
  const w = 400; const h = 300; const pad = 10;
  const min = Math.min(...candles.map((c) => c.l));
  const max = Math.max(...candles.map((c) => c.h));
  const range = max - min || 1;
  const cw = (w - pad * 2) / candles.length;
  const toY = (v: number) => pad + (1 - (v - min) / range) * (h - pad * 2);

  return (
    <div className="w-full h-full rounded-2xl overflow-hidden" style={{ background: C.card, border: `1px solid ${C.border}` }}>
      <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full h-full block">
        {/* Grid lines */}
        {[0.25, 0.5, 0.75].map((t) => (
          <line key={t} x1={pad} x2={w - pad} y1={pad + t * (h - pad * 2)} y2={pad + t * (h - pad * 2)}
            stroke={C.border} strokeDasharray="4 6" strokeWidth="1" />
        ))}
        {candles.map((c, i) => {
          const x = pad + i * cw + cw / 2;
          const bodyTop = toY(Math.max(c.o, c.c));
          const bodyBot = toY(Math.min(c.o, c.c));
          const bodyH = Math.max(2, bodyBot - bodyTop);
          const up = c.c >= c.o;
          const color = c.spike ? C.crimsonGlow : vix ? "#22D3EE" : (up ? "#22C55E" : "#EF4444");
          const wickColor = c.spike ? C.crimsonGlow : vix ? "#0EA5E9" : (up ? "#16A34A" : "#DC2626");
          return (
            <g key={i}>
              {/* Wick */}
              <line x1={x} x2={x} y1={toY(c.h)} y2={toY(c.l)}
                stroke={wickColor} strokeWidth={Math.max(1, cw * 0.15)} />
              {/* Body */}
              <rect x={x - cw * 0.38} y={bodyTop} width={Math.max(2, cw * 0.76)} height={bodyH}
                fill={color} opacity={0.95} rx="1" />
              {/* Spike glow */}
              {c.spike && (
                <rect x={x - cw * 0.5} y={bodyTop - 2} width={cw} height={bodyH + 4}
                  fill={C.crimsonGlow} opacity={0.25} rx="2" />
              )}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

// ─── JOURNAL PAGE ─────────────────────────────────────────────────────────────
function JournalPage({ asset, onAssetChange }: { asset: Asset; onAssetChange: (a: string) => void }) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth());
  const [selectedDay, setSelectedDay] = useState<string | null>(now.toISOString().slice(0, 10));
  const [summaries, setSummaries] = useState<Record<string, { count: number; total: number }>>({});
  const [dayEntries, setDayEntries] = useState<JournalEntry[]>([]);

  useEffect(() => { getDaySummaries(asset, year, month).then(setSummaries); }, [asset, year, month]);
  useEffect(() => { if (selectedDay) getEntriesForDay(asset, selectedDay).then(setDayEntries); }, [asset, selectedDay]);

  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const firstDow = new Date(year, month, 1).getDay();
  const monthName = new Date(year, month).toLocaleString("default", { month: "long" });

  return (
    <div className="space-y-4">
      {/* Asset tabs */}
      <div className="flex gap-1 p-1 rounded-2xl" style={{ background: C.card, border: `1px solid ${C.border}` }}>
        {ASSETS.map((a) => (
          <button key={a} onClick={() => onAssetChange(a)}
            className="flex-1 py-2 rounded-xl text-[10px] font-black tracking-wider transition-all"
            style={{ background: a === asset ? C.crimson : "transparent", color: a === asset ? C.white : C.textDim }}>
            {a.replace("VIX75 1s", "VIX1s").replace("1000", "")}
          </button>
        ))}
      </div>

      {/* Calendar */}
      <div className="rounded-2xl overflow-hidden" style={{ background: C.card, border: `1px solid ${C.border}` }}>
        <div className="px-4 py-3 flex items-center justify-between" style={{ borderBottom: `1px solid ${C.border}` }}>
          <button onClick={() => { if (month === 0) { setMonth(11); setYear(y => y - 1); } else setMonth(m => m - 1); }} style={{ color: C.crimson }}>
            <ChevronLeft className="h-5 w-5" />
          </button>
          <span className="text-base font-black tracking-wider" style={{ color: C.white }}>{monthName} {year}</span>
          <button onClick={() => { if (month === 11) { setMonth(0); setYear(y => y + 1); } else setMonth(m => m + 1); }} style={{ color: C.crimson }}>
            <ChevronRight className="h-5 w-5" />
          </button>
        </div>
        <div className="grid grid-cols-7 px-2 pt-2 pb-1">
          {["S","M","T","W","T","F","S"].map((d, i) => (
            <div key={i} className="text-center text-[10px] font-black" style={{ color: C.textDim }}>{d}</div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1 px-2 pb-2">
          {Array.from({ length: firstDow }).map((_, i) => <div key={`e-${i}`} />)}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const day = i + 1;
            const ds = `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
            const s = summaries[ds];
            const isSel = selectedDay === ds;
            const isToday = ds === now.toISOString().slice(0, 10);
            return (
              <button key={day} onClick={() => setSelectedDay(ds)}
                className="aspect-square rounded-xl flex flex-col items-center justify-center transition-all"
                style={{ background: isSel ? C.crimson : s ? C.crimsonFaint : "transparent", border: `1px solid ${isToday ? C.crimson : s ? C.crimsonDim : C.border}` }}>
                <span className="text-xs font-bold" style={{ color: isSel ? C.white : s ? C.textBright : C.textDim }}>{day}</span>
                {s && <span className="text-[7px] font-bold" style={{ color: isSel ? "rgba(255,255,255,0.8)" : C.crimson }}>+{s.total.toFixed(1)}</span>}
              </button>
            );
          })}
        </div>
      </div>

      {/* Day detail */}
      {selectedDay && (
        <div className="rounded-2xl overflow-hidden" style={{ background: C.card, border: `1px solid ${C.border}` }}>
          <div className="px-4 py-3 flex items-center justify-between" style={{ borderBottom: `1px solid ${C.border}` }}>
            <div>
              <p className="text-sm font-black" style={{ color: C.white }}>
                {new Date(selectedDay + "T12:00:00").toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" })}
              </p>
              <p className="text-xs font-mono" style={{ color: C.textDim }}>{dayEntries.length} events logged</p>
            </div>
            <span className="text-lg font-black" style={{ color: C.crimson }}>
              +{dayEntries.reduce((a, b) => a + b.movement, 0).toFixed(3)}
            </span>
          </div>
          <div className="px-4 py-3 flex gap-3" style={{ borderBottom: `1px solid ${C.border}` }}>
            <button onClick={() => { const csv = generateDailyCSV(dayEntries, asset, selectedDay); downloadAsFile(csv, `itrade_${asset}_${selectedDay}.txt`); }}
              disabled={!dayEntries.length}
              className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-xs font-black tracking-wider"
              style={{ background: dayEntries.length ? C.crimsonFaint : "transparent", color: dayEntries.length ? C.crimson : C.textMuted, border: `1px solid ${dayEntries.length ? C.crimsonDim : C.border}` }}>
              <Download className="h-3.5 w-3.5" /> Daily
            </button>
            <button onClick={async () => { const e = await getEntriesForWeek(asset, selectedDay); downloadAsFile(generateWeeklyCSV(e, asset, selectedDay), `itrade_week_${selectedDay}.txt`); }}
              className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-xs font-black tracking-wider"
              style={{ background: C.crimsonFaint, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
              <Download className="h-3.5 w-3.5" /> Weekly
            </button>
          </div>
          <div className="divide-y" style={{ borderColor: C.border }}>
            {dayEntries.length === 0 && (
              <p className="text-sm font-mono text-center py-6" style={{ color: C.textMuted }}>No events logged</p>
            )}
            {dayEntries.slice(-30).reverse().map((e, i) => (
              <div key={i} className="px-4 py-3 flex items-center justify-between">
                <div>
                  <div className="flex items-center gap-2 mb-0.5">
                    {e.spike && <span className="text-[9px] font-black px-1.5 py-0.5 rounded" style={{ background: C.crimson, color: C.white }}>SPIKE</span>}
                    {e.structureTag && <span className="text-[9px] font-black px-1.5 py-0.5 rounded" style={{ background: C.crimsonFaint, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>{e.structureTag}</span>}
                    <span className="text-xs font-mono" style={{ color: C.textDim }}>
                      {new Date(e.epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                    </span>
                  </div>
                  <p className="text-sm font-mono font-bold" style={{ color: C.textBright }}>
                    {e.open.toFixed(3)} <span style={{ color: C.textMuted }}>→</span> {e.close.toFixed(3)}
                  </p>
                  <p className="text-[10px] font-mono" style={{ color: C.textDim }}>
                    AO {e.ao > 0 ? "+" : ""}{e.ao} · AC {e.ac > 0 ? "+" : ""}{e.ac}
                    {!isVix(asset) && ` · ${e.candlesSinceSpike}c`}
                  </p>
                </div>
                <span className="text-base font-black" style={{ color: C.crimson }}>+{e.movement.toFixed(3)}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── HISTORY PAGE ─────────────────────────────────────────────────────────────
function HistoryPage({ asset, onAssetChange }: { asset: Asset; onAssetChange: (a: string) => void }) {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth());
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [summaries, setSummaries] = useState<Record<string, { count: number; total: number }>>({});
  const [dayEntries, setDayEntries] = useState<JournalEntry[]>([]);

  useEffect(() => { getDaySummaries(asset, year, month).then(setSummaries); }, [asset, year, month]);
  useEffect(() => { if (selectedDay) getEntriesForDay(asset, selectedDay).then(setDayEntries); }, [asset, selectedDay]);

  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const firstDow = new Date(year, month, 1).getDay();
  const monthName = new Date(year, month).toLocaleString("default", { month: "long" });
  const totalMovement = Object.values(summaries).reduce((a, b) => a + b.total, 0);
  const activeDays = Object.keys(summaries).length;
  const totalEvents = Object.values(summaries).reduce((a, b) => a + b.count, 0);

  return (
    <div className="space-y-4">
      {/* Asset tabs */}
      <div className="flex gap-1 p-1 rounded-2xl" style={{ background: C.card, border: `1px solid ${C.border}` }}>
        {ASSETS.map((a) => (
          <button key={a} onClick={() => onAssetChange(a)}
            className="flex-1 py-2 rounded-xl text-[10px] font-black tracking-wider transition-all"
            style={{ background: a === asset ? C.crimson : "transparent", color: a === asset ? C.white : C.textDim }}>
            {a.replace("VIX75 1s", "VIX1s").replace("1000", "")}
          </button>
        ))}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-3">
        {[{ l: "EVENTS", v: totalEvents.toString() }, { l: "ACTIVE DAYS", v: activeDays.toString() }, { l: "TOTAL PTS", v: `+${totalMovement.toFixed(1)}` }].map((s) => (
          <div key={s.l} className="rounded-2xl p-3 text-center" style={{ background: C.card, border: `1px solid ${C.border}` }}>
            <p className="text-base font-black" style={{ color: C.crimson }}>{s.v}</p>
            <p className="text-[9px] font-bold tracking-wider mt-0.5" style={{ color: C.textDim }}>{s.l}</p>
          </div>
        ))}
      </div>

      {/* Calendar */}
      <div className="rounded-2xl overflow-hidden" style={{ background: C.card, border: `1px solid ${C.border}` }}>
        <div className="px-4 py-3 flex items-center justify-between" style={{ borderBottom: `1px solid ${C.border}` }}>
          <button onClick={() => { if (month === 0) { setMonth(11); setYear(y => y - 1); } else setMonth(m => m - 1); }} style={{ color: C.crimson }}><ChevronLeft className="h-5 w-5" /></button>
          <span className="text-base font-black tracking-wider" style={{ color: C.white }}>{monthName} {year}</span>
          <button onClick={() => { if (month === 11) { setMonth(0); setYear(y => y + 1); } else setMonth(m => m + 1); }} style={{ color: C.crimson }}><ChevronRight className="h-5 w-5" /></button>
        </div>
        <div className="grid grid-cols-7 px-2 pt-2 pb-1">
          {["S","M","T","W","T","F","S"].map((d, i) => (
            <div key={i} className="text-center text-[10px] font-black" style={{ color: C.textDim }}>{d}</div>
          ))}
        </div>
        <div className="grid grid-cols-7 gap-1 px-2 pb-2">
          {Array.from({ length: firstDow }).map((_, i) => <div key={`e-${i}`} />)}
          {Array.from({ length: daysInMonth }).map((_, i) => {
            const day = i + 1;
            const ds = `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
            const s = summaries[ds];
            const isSel = selectedDay === ds;
            const isToday = ds === now.toISOString().slice(0, 10);
            return (
              <button key={day} onClick={() => setSelectedDay(isSel ? null : ds)}
                className="aspect-square rounded-xl flex flex-col items-center justify-center transition-all"
                style={{ background: isSel ? C.crimson : s ? C.crimsonFaint : "transparent", border: `1px solid ${isToday ? C.crimson : s ? C.crimsonDim : C.border}` }}>
                <span className="text-xs font-bold" style={{ color: isSel ? C.white : s ? C.textBright : C.textDim }}>{day}</span>
                {s && <span className="text-[7px] font-bold" style={{ color: isSel ? "rgba(255,255,255,0.8)" : C.crimson }}>{s.count}t</span>}
                {s && <span className="text-[7px] font-bold" style={{ color: isSel ? "rgba(255,255,255,0.7)" : C.crimsonGlow }}>+{s.total.toFixed(1)}</span>}
              </button>
            );
          })}
        </div>
      </div>

      {/* Day detail */}
      {selectedDay && dayEntries.length > 0 && (
        <div className="rounded-2xl overflow-hidden" style={{ background: C.card, border: `1px solid ${C.border}` }}>
          <div className="px-4 py-3 flex items-center justify-between" style={{ borderBottom: `1px solid ${C.border}` }}>
            <div>
              <p className="text-sm font-black" style={{ color: C.white }}>
                {new Date(selectedDay + "T12:00:00").toLocaleDateString("en-US", { weekday: "long", day: "numeric", month: "short" })}
              </p>
              <p className="text-xs font-mono" style={{ color: C.textDim }}>{dayEntries.length} signals</p>
            </div>
            <span className="text-lg font-black" style={{ color: C.crimson }}>+{dayEntries.reduce((a, b) => a + b.movement, 0).toFixed(3)}</span>
          </div>
          <div className="divide-y" style={{ borderColor: C.border }}>
            {dayEntries.slice().reverse().map((e, i) => (
              <div key={i} className="px-4 py-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    {e.spike && <span className="text-[9px] font-black px-1.5 py-0.5 rounded" style={{ background: C.crimson, color: C.white }}>SPIKE</span>}
                    {e.structureTag && <span className="text-[9px] font-black px-1.5 py-0.5 rounded" style={{ background: C.crimsonFaint, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>{e.structureTag}</span>}
                    <span className="text-xs font-mono" style={{ color: C.textDim }}>
                      {new Date(e.epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                    </span>
                  </div>
                  <span className="text-base font-black" style={{ color: C.crimson }}>+{e.movement.toFixed(3)}</span>
                </div>
                <p className="text-sm font-mono font-bold mt-0.5" style={{ color: C.textBright }}>
                  {e.open.toFixed(3)} <span style={{ color: C.textMuted }}>→</span> {e.close.toFixed(3)}
                </p>
                <p className="text-[10px] font-mono" style={{ color: C.textDim }}>
                  AO {e.ao > 0 ? "+" : ""}{e.ao} · AC {e.ac > 0 ? "+" : ""}{e.ac}
                  {!isVix(asset) && ` · ${e.candlesSinceSpike} candles since spike`}
                </p>
              </div>
            ))}
          </div>
          <div className="px-4 py-3 flex gap-3" style={{ borderTop: `1px solid ${C.border}` }}>
            <button onClick={() => { const csv = generateDailyCSV(dayEntries, asset, selectedDay); downloadAsFile(csv, `itrade_${asset}_${selectedDay}.txt`); }}
              className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-xs font-black tracking-wider"
              style={{ background: C.crimsonFaint, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
              <Download className="h-3.5 w-3.5" /> Daily Report
            </button>
            <button onClick={async () => { const e = await getEntriesForWeek(asset, selectedDay); downloadAsFile(generateWeeklyCSV(e, asset, selectedDay), `itrade_week_${selectedDay}.txt`); }}
              className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-xs font-black tracking-wider"
              style={{ background: C.crimsonFaint, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
              <Download className="h-3.5 w-3.5" /> Weekly Report
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── INDICATOR CARD ───────────────────────────────────────────────────────────
function IndicatorCard({ index, title, subtitle, badge, children }: {
  index: number; title: string; subtitle: string;
  badge?: { label: string; active?: boolean };
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl p-3" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
      <div className="flex items-start justify-between mb-2">
        <div className="min-w-0 flex-1">
          <h3 className="text-xs font-black uppercase tracking-wider font-mono truncate" style={{ color: C.crimson }}>
            {index}. {title}
          </h3>
          <p className="text-[10px] font-mono truncate" style={{ color: C.textDim }}>{subtitle}</p>
        </div>
        {badge && (
          <span className="text-[9px] px-1.5 py-0.5 rounded font-mono font-black border ml-2 flex-shrink-0"
            style={{ background: badge.active ? C.crimsonFaint : C.card, color: badge.active ? C.crimson : C.textDim, borderColor: badge.active ? C.crimsonDim : C.border }}>
            {badge.label}
          </span>
        )}
      </div>
      {children}
    </div>
  );
}

function AOHistogram({ series, height }: { series: number[]; height: number }) {
  const valid = series.filter((v) => isFinite(v));
  if (!valid.length) return <div style={{ height }} />;
  const w = 400; const h = height;
  const max = Math.max(...valid.map(Math.abs), 0.001);
  const bw = w / series.length; const mid = h / 2;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full block rounded">
      <line x1={0} x2={w} y1={mid} y2={mid} stroke={C.border} strokeDasharray="2 4" />
      {series.map((v, i) => {
        if (!isFinite(v)) return null;
        const prev = series[i - 1]; const up = isFinite(prev) ? v >= prev : v >= 0;
        const bh = Math.max(2, (Math.abs(v) / max) * (mid - 4));
        return <rect key={i} x={i * bw + 0.5} y={v >= 0 ? mid - bh : mid} width={Math.max(1.5, bw - 1)} height={bh} fill={up ? "#009688" : "#f44336"} opacity={0.95} rx="0.5" />;
      })}
    </svg>
  );
}

function ACHistogram({ series, height }: { series: number[]; height: number }) {
  const valid = series.filter((v) => isFinite(v));
  if (!valid.length) return <div style={{ height }} />;
  const w = 400; const h = height;
  const max = Math.max(...valid.map(Math.abs), 0.001);
  const bw = w / series.length; const mid = h / 2;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full block rounded">
      <line x1={0} x2={w} y1={mid} y2={mid} stroke={C.border} strokeDasharray="2 4" />
      {series.map((v, i) => {
        if (!isFinite(v)) return null;
        const prev = series[i - 1]; const up = isFinite(prev) ? v >= prev : v >= 0;
        const bh = Math.max(2, (Math.abs(v) / max) * (mid - 4));
        return <rect key={i} x={i * bw + 0.5} y={v >= 0 ? mid - bh : mid} width={Math.max(1.5, bw - 1)} height={bh} fill={up ? "#2196f3" : "#f44336"} opacity={0.95} rx="0.5" />;
      })}
    </svg>
  );
}

function SpikeIndicators({ candles, asset, tick }: { candles: Candle[]; asset: string; tick: number }) {
  const isBoom = asset.startsWith("BOOM");
  const ind = useMemo(() => calcIndicators(candles), [candles]);
  const aoSeries = useMemo(() => calcAO(candles), [candles]);
  const acSeries = useMemo(() => calcAC(aoSeries), [aoSeries]);
  const aoV2 = useMemo(() => calcAOV2(candles), [candles]);
  const macdT = useMemo(() => calcMACDTactic(candles), [candles]);
  const ao = ind?.ao ?? 0; const ac = ind?.ac ?? 0;
  const total = (ao < -2 ? 1 : ao > 2 ? -1 : 0) + (ac < -1 ? 1 : ac > 1 ? -1 : 0);
  const totalAbs = Math.abs(ao < -2 ? 1 : ao > 2 ? -1 : 0) + Math.abs(ac < -1 ? 1 : ac > 1 ? -1 : 0);
  const aligned = !!ind && totalAbs >= 2 && Math.abs(total) === totalAbs;

  return (
    <>
      <IndicatorCard index={1} title="Awesome Oscillator" subtitle="SMA(HL2,5) − SMA(HL2,34) · MT5 exact">
        <AOHistogram series={aoSeries} height={64} />
        <div className="flex justify-between text-xs font-mono mt-1.5">
          <span style={{ color: C.textDim }}>AO</span>
          <span style={{ color: ao >= 0 ? "#009688" : "#f44336" }}>{ao > 0 ? "+" : ""}{ao.toFixed(4)}</span>
        </div>
      </IndicatorCard>
      <IndicatorCard index={2} title="Accelerator Oscillator" subtitle="AO − SMA(AO,5) · MT5 exact">
        <ACHistogram series={acSeries} height={64} />
        <div className="flex justify-between text-xs font-mono mt-1.5">
          <span style={{ color: C.textDim }}>AC</span>
          <span style={{ color: ac >= 0 ? "#2196f3" : "#f44336" }}>{ac > 0 ? "+" : ""}{ac.toFixed(4)}</span>
        </div>
      </IndicatorCard>
      <IndicatorCard index={3} title="AO V2 (Kivanç)" subtitle="Signal-line variant · SIG 7">
        <svg viewBox="0 0 400 64" preserveAspectRatio="none" className="w-full block rounded">
          {(() => {
            const { ao: a, signal: s } = aoV2; const w = 400; const h = 64;
            const all = [...a, ...s].filter(v => isFinite(v)); if (!all.length) return null;
            const max = Math.max(...all.map(Math.abs), 0.001); const bw = w / a.length; const mid = h / 2;
            const toY = (v: number) => mid - (v / max) * (mid - 5);
            return <>
              <line x1={0} x2={w} y1={mid} y2={mid} stroke={C.border} strokeDasharray="2 4" />
              <polyline fill="none" stroke="#f44336" strokeWidth="2" points={a.map((v, i) => `${i * bw + bw / 2},${toY(v)}`).join(" ")} />
              <polyline fill="none" stroke="#2196f3" strokeWidth="1.5" strokeDasharray="4 2" points={s.map((v, i) => `${i * bw + bw / 2},${toY(v)}`).join(" ")} />
            </>;
          })()}
        </svg>
      </IndicatorCard>
      <IndicatorCard index={4} title="AO & MACD Tactic" subtitle="Tea-saucer detection"
        badge={{ label: macdT.saucerBull ? "SAUCER ▲" : macdT.saucerBear ? "SAUCER ▼" : "NO SAUCER", active: macdT.saucerBull || macdT.saucerBear }}>
        <ACHistogram series={macdT.ao} height={64} />
      </IndicatorCard>
      <IndicatorCard index={5} title="Classic AO (Orekhov)" subtitle="Standard 5/34 block scale">
        <AOHistogram series={aoSeries} height={64} />
      </IndicatorCard>
      <div className="text-center py-1">
        <p className="text-xs font-mono" style={{ color: C.textDim }}>
          {aligned ? `${Math.abs(total)}/${totalAbs} indicators aligned` : `Scanning for alignment…`}
        </p>
      </div>
      <button className="w-full h-14 rounded-2xl font-black tracking-[0.3em] text-base"
        style={{ background: aligned ? C.crimson : C.card, color: aligned ? C.white : C.textDim, border: `1px solid ${aligned ? C.crimson : C.border}`, boxShadow: aligned ? `0 0 24px ${C.crimson}50` : "none" }}>
        {aligned ? `${isBoom ? "SELL" : "BUY"} · SIGNAL` : "SCANNING…"}
      </button>
    </>
  );
}

function VixIndicators({ candles, asset, tick }: { candles: Candle[]; asset: string; tick: number }) {
  const vixData = useMemo(() => calcVixAnalysis(candles), [candles]);
  const aoSeries = useMemo(() => calcAO(candles), [candles]);
  const acSeries = useMemo(() => calcAC(aoSeries), [aoSeries]);
  const closes = candles.map((c) => c.c);
  const ma20 = useMemo(() => smaArr(closes, 20), [candles]);
  const ma50 = useMemo(() => smaArr(closes, 50), [candles]);

  if (!vixData) return <div className="text-center py-12 text-sm font-mono" style={{ color: C.textMuted }}>Gathering data…</div>;
  const trendColor = vixData.trend === "bullish" ? "#22C55E" : vixData.trend === "bearish" ? "#EF4444" : C.crimson;

  return (
    <>
      <div className="rounded-xl p-4" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
        <div className="flex items-center justify-between mb-3">
          <span className="text-xs font-black uppercase tracking-wider" style={{ color: C.crimson }}>Trend Structure</span>
          <span className="text-xs font-black" style={{ color: trendColor }}>{vixData.trend.toUpperCase()}</span>
        </div>
        {vixData.narratives.map((n, i) => (
          <p key={i} className="text-xs font-mono leading-relaxed mb-1" style={{ color: C.text }}>
            <span style={{ color: C.crimson }}>› </span>{n}
          </p>
        ))}
      </div>
      <div className="rounded-xl p-3" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
        <p className="text-[10px] font-black uppercase tracking-wider mb-2" style={{ color: C.crimson }}>Market Structure</p>
        <div className="flex flex-wrap gap-1.5">
          {vixData.structure.slice(-8).map((s, i) => (
            <span key={i} className="text-[10px] font-black px-2 py-0.5 rounded border"
              style={{ background: (s.type === "HH" || s.type === "HL") ? C.crimsonFaint : C.card, color: (s.type === "HH" || s.type === "HL") ? C.crimson : C.textDim, borderColor: (s.type === "HH" || s.type === "HL") ? C.crimsonDim : C.border }}>
              {s.type} {s.price.toFixed(2)}
            </span>
          ))}
        </div>
      </div>
      <IndicatorCard index={1} title="Moving Averages" subtitle="SMA20 (amber) · SMA50 (purple)">
        <svg viewBox="0 0 400 72" preserveAspectRatio="none" className="w-full block rounded">
          {(() => {
            const w = 400; const h = 72;
            const all = [...closes, ...ma20, ...ma50].filter(v => isFinite(v)); if (!all.length) return null;
            const minV = Math.min(...all); const maxV = Math.max(...all); const range = maxV - minV || 1;
            const bw = w / closes.length; const toY = (v: number) => 5 + (1 - (v - minV) / range) * (h - 10);
            return <>
              <polyline fill="none" stroke={C.border} strokeWidth="1" points={closes.map((v, i) => `${i * bw + bw / 2},${toY(v)}`).join(" ")} />
              <polyline fill="none" stroke="#f59e0b" strokeWidth="2" points={ma20.map((v, i) => isFinite(v) ? `${i * bw + bw / 2},${toY(v)}` : null).filter(Boolean).join(" ")} />
              <polyline fill="none" stroke="#a855f7" strokeWidth="2" points={ma50.map((v, i) => isFinite(v) ? `${i * bw + bw / 2},${toY(v)}` : null).filter(Boolean).join(" ")} />
            </>;
          })()}
        </svg>
        <div className="flex justify-between text-[10px] font-mono mt-1.5">
          <span style={{ color: "#f59e0b" }}>MA20 {vixData.ma20.toFixed(3)}</span>
          <span style={{ color: "#a855f7" }}>MA50 {vixData.ma50.toFixed(3)}</span>
        </div>
      </IndicatorCard>
      <IndicatorCard index={2} title="Awesome Oscillator" subtitle="SMA(HL2,5) − SMA(HL2,34) · MT5">
        <AOHistogram series={aoSeries} height={64} />
      </IndicatorCard>
      <IndicatorCard index={3} title="Accelerator Oscillator" subtitle="AO − SMA(AO,5) · MT5">
        <ACHistogram series={acSeries} height={64} />
      </IndicatorCard>
    </>
  );
}
