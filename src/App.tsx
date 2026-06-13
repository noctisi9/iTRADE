import { useEffect, useRef, useState, useMemo, useCallback } from "react";
import { ArrowRight, Menu, X, BookOpen, Clock, Download, ChevronLeft, ChevronRight } from "lucide-react";

import intro1 from "@/assets/intro/intro1.jpg";
import intro2 from "@/assets/intro/intro2.jpg";
import intro3 from "@/assets/intro/intro3.jpg";
import intro4 from "@/assets/intro/intro4.jpg";
import intro5 from "@/assets/intro/intro5.jpg";
import intro6 from "@/assets/intro/intro6.jpg";
import intro7 from "@/assets/intro/intro7.jpg";
import heroTrader from "@/assets/hero-trader.jpg";

import {
  useDerivCandles, calcIndicators, calcAO, calcAC, calcAOV2,
  calcMACDTactic, calcVWCBB, calcVixAnalysis, smaArr, type Candle,
} from "@/lib/deriv";
import {
  logCandle, saveState, loadState, getDaySummaries,
  getEntriesForDay, getEntriesForWeek, generateDailyCSV,
  generateWeeklyCSV, downloadAsFile, type JournalEntry,
} from "@/lib/journal";

// ─── THEME ───────────────────────────────────────────────────────────────────
const C = {
  bg: "#02060E",
  card: "#06101A",
  border: "#1a0508",
  crimson: "#C50337",
  crimsonDim: "#8B0226",
  crimsonGlow: "#FF0545",
  text: "#E8D5D8",
  textDim: "#8B6B70",
  textMuted: "#4A3038",
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

  // Persist state on every change
  useEffect(() => {
    if (!stateLoaded) return;
    saveState({ view, activeAsset, drawerOpen: false, journalAsset });
  }, [view, activeAsset, journalAsset, stateLoaded]);

  const navigate = (v: View) => { setView(v); setDrawerOpen(false); };

  return (
    <div className="min-h-screen w-full flex items-center justify-center" style={{ background: C.bg }}>
      <div className="w-full max-w-[430px] relative">
        {/* Drawer overlay */}
        {drawerOpen && (
          <div className="absolute inset-0 z-50 flex">
            <div className="w-72 h-full flex flex-col" style={{ background: C.card, borderRight: `1px solid ${C.border}` }}>
              <div className="flex items-center justify-between px-6 pt-8 pb-6">
                <span className="text-xl font-bold tracking-widest" style={{ color: C.crimson }}>NOCTIS</span>
                <button onClick={() => setDrawerOpen(false)} style={{ color: C.textDim }}>
                  <X className="h-5 w-5" />
                </button>
              </div>
              <div className="h-px mx-6 mb-4" style={{ background: C.border }} />
              <nav className="flex-1 px-4 space-y-1">
                <DrawerItem icon={<BookOpen className="h-4 w-4" />} label="Journal" onClick={() => navigate("journal")} active={view === "journal"} />
                <DrawerItem icon={<Clock className="h-4 w-4" />} label="History" onClick={() => navigate("history")} active={view === "history"} />
              </nav>
              <div className="px-6 pb-8">
                <p className="text-[10px] font-mono" style={{ color: C.textMuted }}>iTRADE · NOCTIS EA</p>
              </div>
            </div>
            <div className="flex-1" onClick={() => setDrawerOpen(false)} />
          </div>
        )}

        {/* Header (not on intro) */}
        {view !== "intro" && (
          <div className="flex items-center justify-between px-5 pt-5 pb-3">
            <button onClick={() => setDrawerOpen(true)} className="h-10 w-10 rounded-full grid place-items-center" style={{ background: C.card, border: `1px solid ${C.border}` }}>
              <Menu className="h-4 w-4" style={{ color: C.crimson }} />
            </button>
            <span className="text-sm font-bold tracking-[0.3em]" style={{ color: C.crimson }}>NOCTIS</span>
            <div className="h-2 w-2 rounded-full animate-pulse" style={{ background: C.crimson }} />
          </div>
        )}

        {/* Views */}
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
          <JournalPage asset={journalAsset} onAssetChange={(a) => setJournalAsset(a as Asset)} />
        )}
        {view === "history" && (
          <HistoryPage asset={journalAsset} onAssetChange={(a) => setJournalAsset(a as Asset)} />
        )}
      </div>
    </div>
  );
}

function DrawerItem({ icon, label, onClick, active }: { icon: React.ReactNode; label: string; onClick: () => void; active: boolean }) {
  return (
    <button onClick={onClick} className="w-full flex items-center gap-3 px-4 py-3 rounded-xl text-left transition"
      style={{ background: active ? `${C.crimson}20` : "transparent", color: active ? C.crimson : C.textDim, border: active ? `1px solid ${C.crimsonDim}` : "1px solid transparent" }}>
      {icon}
      <span className="text-sm font-mono font-bold tracking-wider">{label}</span>
    </button>
  );
}

// ─── INTRO ────────────────────────────────────────────────────────────────────
function IntroPage({ onNext }: { onNext: () => void }) {
  const [imgIdx, setImgIdx] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setImgIdx((i) => (i + 1) % INTRO_IMAGES.length), 3000);
    return () => clearInterval(id);
  }, []);

  const trackRef = useRef<HTMLDivElement>(null);
  const [x, setX] = useState(0);
  const draggingRef = useRef(false);
  const startXRef = useRef(0);
  const maxRef = useRef(0);

  const begin = (clientX: number) => {
    if (!trackRef.current) return;
    maxRef.current = trackRef.current.clientWidth - 56 - 8;
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
    <div className="relative overflow-hidden rounded-[2.5rem] shadow-2xl aspect-[9/19.5]">
      {/* Cycling backgrounds */}
      {INTRO_IMAGES.map((img, i) => (
        <img key={i} src={img} alt="" className="absolute inset-0 h-full w-full object-cover transition-opacity duration-1000"
          style={{ opacity: i === imgIdx ? 1 : 0 }} />
      ))}
      <div className="absolute inset-0" style={{ background: "linear-gradient(to bottom, rgba(2,6,14,0.4) 0%, rgba(2,6,14,0.1) 40%, rgba(2,6,14,0.85) 100%)" }} />

      <div className="relative px-7 mt-6">
        <span className="text-2xl font-semibold tracking-tight text-white">
          spike<span style={{ color: C.crimson }}>.</span>
        </span>
      </div>

      <div className="absolute inset-x-0 bottom-0 p-7 pb-8">
        <h1 className="text-white text-[56px] font-bold leading-[0.95] tracking-tight">
          Trading<br />made<br />simple.
        </h1>
        <p className="mt-4 text-white/85 text-base">Signals at your<br />fingertips.</p>

        {/* Slide to continue */}
        <div ref={trackRef}
          className="mt-8 relative h-14 rounded-full p-1 overflow-hidden select-none"
          style={{ background: "rgba(2,6,14,0.6)", backdropFilter: "blur(12px)", border: `1px solid ${C.crimsonDim}` }}
          onMouseMove={(e) => move(e.clientX)} onMouseUp={end} onMouseLeave={end}
          onTouchMove={(e) => move(e.touches[0].clientX)} onTouchEnd={end}>
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
            <span className="text-white/80 font-medium tracking-wide text-sm flex items-center gap-2">
              Slide to continue <ArrowRight className="h-4 w-4" />
            </span>
          </div>
          <div role="slider"
            className="relative h-12 w-14 rounded-full grid place-items-center shadow-lg touch-none transition-transform duration-200"
            style={{ background: C.crimson, transform: `translateX(${x}px)` }}
            onMouseDown={(e) => begin(e.clientX)}
            onTouchStart={(e) => begin(e.touches[0].clientX)}>
            <span className="text-[10px] font-bold text-white tracking-tight">GO</span>
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
    <div className="rounded-[2rem] overflow-hidden shadow-2xl" style={{ border: `1px solid ${C.border}`, background: C.card }}>
      <div ref={containerRef} className="h-[680px] overflow-y-auto snap-y snap-mandatory scroll-smooth" style={{ scrollbarWidth: "none" }}>
        {ASSETS.map((a) => (
          <div key={a} data-asset-page className="snap-start h-[680px]">
            <SignalPage asset={a} onOpenIndicators={() => onOpenIndicators(a)} onVisible={() => onAssetChange(a)} />
          </div>
        ))}
      </div>
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

  // Log candles to journal
  useEffect(() => {
    if (!candles.length) return;
    const last = candles[candles.length - 1];
    const ind = calcIndicators(candles);
    if (!ind) return;
    const lastSpikeIdx = [...candles].map((c) => c.spike).lastIndexOf(true);
    const candlesSinceSpike = lastSpikeIdx === -1 ? candles.length : candles.length - 1 - lastSpikeIdx;
    const vixData = vix ? calcVixAnalysis(candles) : null;
    const structureTag = vixData?.events[vixData.events.length - 1]?.type ?? 
      vixData?.structure[vixData.structure.length - 1]?.type;
    logCandle({
      asset, epoch: last.epoch, open: last.o, high: last.h, low: last.l, close: last.c,
      movement: Math.abs(last.o - last.c),
      spike: !!last.spike, candlesSinceSpike,
      ao: ind.ao, ac: ind.ac,
      structureTag,
    }).catch(() => {});
  }, [candles.length, asset]);

  // Intersection observer for active asset tracking
  useEffect(() => {
    if (!ref.current) return;
    const obs = new IntersectionObserver(([e]) => { if (e.isIntersecting) onVisible(); }, { threshold: 0.6 });
    obs.observe(ref.current);
    return () => obs.disconnect();
  }, []);

  const lastSpikeIdx = !vix ? [...candles].map((c) => c.spike).lastIndexOf(true) : -1;
  const candlesSinceSpike = lastSpikeIdx === -1 ? candles.length : candles.length - 1 - lastSpikeIdx;
  const justSpiked = !vix && candles[candles.length - 1]?.spike;
  let summary = "";
  if (!candles.length) summary = "Connecting to Deriv…";
  else if (vix) {
    const vd = calcVixAnalysis(candles);
    summary = vd ? (vd.trend === "bullish" ? "Bullish structure forming" : vd.trend === "bearish" ? "Bearish structure dominant" : "Ranging — no clear direction") : "Gathering data…";
  } else {
    summary = justSpiked ? "A spike just occurred" : `${candlesSinceSpike} candle${candlesSinceSpike === 1 ? "" : "s"} since last spike`;
  }

  return (
    <div ref={ref} className="relative h-full flex flex-col">
      <div className="px-5 pt-4 pb-2 flex items-center justify-between">
        <div className="text-xs uppercase tracking-[0.2em]" style={{ color: C.textDim }}>{asset}</div>
        <div className="flex items-center gap-2 text-xs" style={{ color: C.textDim }}>
          <span className="h-1.5 w-1.5 rounded-full animate-pulse" style={{ background: C.crimson }} />
          {String(seconds).padStart(2, "0")}s
        </div>
      </div>
      <div className="relative px-3 flex-1 min-h-0 flex">
        <CandleChart candles={candles} vix={vix} />
        <button onClick={onOpenIndicators}
          className="absolute top-1/2 -translate-y-1/2 right-5 h-11 w-11 rounded-full grid place-items-center shadow-xl active:scale-95 transition"
          style={{ background: C.crimson }}>
          <span className="text-white text-lg">⚡</span>
        </button>
      </div>
      <div className="px-5 pt-2">
        <div className="text-xs font-mono" style={{ color: C.textDim }}>{summary}</div>
      </div>
      <div className="px-5 pt-2 pb-2">
        <button className="w-full h-12 rounded-2xl font-bold tracking-[0.25em] text-sm"
          style={{ background: C.card, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
          SCANNING
        </button>
      </div>
      <div className="px-5 pb-2 flex items-center justify-center gap-2">
        {ASSETS.map((a) => (
          <div key={a} className="h-1 rounded-full transition-all"
            style={{ width: a === asset ? 24 : 6, background: a === asset ? C.crimson : C.textMuted }} />
        ))}
      </div>
      <button onClick={(e) => {
        const page = (e.currentTarget as HTMLElement).closest("[data-asset-page]");
        const next = page?.nextElementSibling as HTMLElement | null;
        if (next) next.scrollIntoView({ behavior: "smooth" });
        else page?.parentElement?.firstElementChild?.scrollIntoView({ behavior: "smooth" });
      }} className="mx-auto mb-3 flex flex-col items-center gap-0.5" style={{ color: C.textMuted }}>
        <span className="text-[9px] tracking-[0.3em]">SWIPE</span>
        <span className="text-xl leading-none animate-bounce">⌄</span>
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
    <div className="rounded-[2rem] overflow-hidden shadow-2xl" style={{ background: C.card, border: `1px solid ${C.border}` }}>
      <div className="px-5 pt-4 pb-2 flex items-center justify-between">
        <button onClick={onBack} className="h-9 w-9 rounded-full grid place-items-center" style={{ background: `${C.crimson}20`, color: C.crimson }}>←</button>
        <div className="text-center">
          <div className="text-xs uppercase tracking-[0.2em]" style={{ color: C.textDim }}>{asset}</div>
          <div className="text-[9px] uppercase tracking-[0.3em] font-bold mt-0.5" style={{ color: C.crimson }}>GARDEN OF SWORDS</div>
        </div>
        <div className="text-xs font-mono" style={{ color: C.textDim }}>{String(seconds).padStart(2, "0")}s</div>
      </div>
      <div className="px-4 pb-4 space-y-3 max-h-[560px] overflow-y-auto" style={{ scrollbarWidth: "none" }}>
        {vix ? <VixIndicators candles={candles} asset={asset} tick={tick} /> : <SpikeIndicators candles={candles} asset={asset} tick={tick} />}
      </div>
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

  useEffect(() => {
    getDaySummaries(asset, year, month).then(setSummaries);
  }, [asset, year, month]);

  useEffect(() => {
    if (!selectedDay) return;
    getEntriesForDay(asset, selectedDay).then(setDayEntries);
  }, [asset, selectedDay]);

  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const firstDow = new Date(year, month, 1).getDay();
  const monthName = new Date(year, month).toLocaleString("default", { month: "long" });

  const handleDownloadDaily = () => {
    if (!selectedDay || !dayEntries.length) return;
    const csv = generateDailyCSV(dayEntries, asset, selectedDay);
    downloadAsFile(csv, `itrade_${asset}_${selectedDay}.txt`);
  };

  const handleDownloadWeekly = async () => {
    const weekStart = selectedDay || now.toISOString().slice(0, 10);
    const entries = await getEntriesForWeek(asset, weekStart);
    if (!entries.length) return;
    const csv = generateWeeklyCSV(entries, asset, weekStart);
    downloadAsFile(csv, `itrade_${asset}_week_${weekStart}.txt`);
  };

  return (
    <div className="rounded-[2rem] overflow-hidden shadow-2xl" style={{ background: C.card, border: `1px solid ${C.border}` }}>
      {/* Asset tabs */}
      <div className="px-4 pt-4 pb-2">
        <div className="flex gap-1 p-1 rounded-xl" style={{ background: C.bg }}>
          {ASSETS.map((a) => (
            <button key={a} onClick={() => onAssetChange(a)}
              className="flex-1 py-1.5 rounded-lg text-[9px] font-mono font-bold tracking-wider transition"
              style={{ background: a === asset ? C.crimson : "transparent", color: a === asset ? "white" : C.textDim }}>
              {a.replace("VIX75 1s", "VIX1s").replace("1000", "")}
            </button>
          ))}
        </div>
      </div>

      {/* Calendar header */}
      <div className="px-5 py-2 flex items-center justify-between">
        <button onClick={() => { if (month === 0) { setMonth(11); setYear(y => y - 1); } else setMonth(m => m - 1); }}
          style={{ color: C.crimson }}><ChevronLeft className="h-4 w-4" /></button>
        <span className="text-sm font-bold font-mono" style={{ color: C.crimson }}>{monthName} {year}</span>
        <button onClick={() => { if (month === 11) { setMonth(0); setYear(y => y + 1); } else setMonth(m => m + 1); }}
          style={{ color: C.crimson }}><ChevronRight className="h-4 w-4" /></button>
      </div>

      {/* Day headers */}
      <div className="grid grid-cols-7 px-3 pb-1">
        {["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].map((d) => (
          <div key={d} className="text-center text-[9px] font-mono" style={{ color: C.textMuted }}>{d}</div>
        ))}
      </div>

      {/* Calendar grid */}
      <div className="grid grid-cols-7 gap-0.5 px-3 pb-3">
        {Array.from({ length: firstDow }).map((_, i) => <div key={`empty-${i}`} />)}
        {Array.from({ length: daysInMonth }).map((_, i) => {
          const day = i + 1;
          const dateStr = `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
          const s = summaries[dateStr];
          const isSelected = selectedDay === dateStr;
          const isToday = dateStr === now.toISOString().slice(0, 10);
          return (
            <button key={day} onClick={() => setSelectedDay(dateStr)}
              className="aspect-square rounded-lg flex flex-col items-center justify-center transition"
              style={{
                background: isSelected ? C.crimson : s ? `${C.crimson}15` : C.bg,
                border: isToday ? `1px solid ${C.crimson}` : `1px solid ${isSelected ? C.crimson : C.border}`,
              }}>
              <span className="text-[10px] font-mono" style={{ color: isSelected ? "white" : s ? C.text : C.textMuted }}>{day}</span>
              {s && <span className="text-[8px] font-mono" style={{ color: isSelected ? "white" : C.crimson }}>+{s.total.toFixed(1)}</span>}
            </button>
          );
        })}
      </div>

      {/* Selected day details */}
      {selectedDay && (
        <div className="mx-4 mb-3 rounded-xl p-3" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
          <div className="flex items-center justify-between mb-2">
            <div>
              <p className="text-xs font-mono font-bold" style={{ color: C.text }}>
                {new Date(selectedDay + "T12:00:00").toLocaleDateString("en-US", { weekday: "long", month: "short", day: "numeric" })}
              </p>
              <p className="text-[10px] font-mono" style={{ color: C.textDim }}>{dayEntries.length} events logged</p>
            </div>
            {dayEntries.length > 0 && (
              <span className="text-sm font-bold font-mono" style={{ color: C.crimson }}>
                +{dayEntries.reduce((a, b) => a + b.movement, 0).toFixed(3)} pts
              </span>
            )}
          </div>

          {/* Download buttons */}
          <div className="flex gap-2 mb-2">
            <button onClick={handleDownloadDaily} disabled={!dayEntries.length}
              className="flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-[10px] font-mono font-bold"
              style={{ background: dayEntries.length ? `${C.crimson}20` : C.bg, color: dayEntries.length ? C.crimson : C.textMuted, border: `1px solid ${dayEntries.length ? C.crimsonDim : C.border}` }}>
              <Download className="h-3 w-3" /> Daily
            </button>
            <button onClick={handleDownloadWeekly}
              className="flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-[10px] font-mono font-bold"
              style={{ background: `${C.crimson}20`, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
              <Download className="h-3 w-3" /> Weekly
            </button>
          </div>

          {/* Event list */}
          <div className="space-y-1 max-h-48 overflow-y-auto" style={{ scrollbarWidth: "none" }}>
            {dayEntries.length === 0 && <p className="text-[10px] font-mono text-center py-2" style={{ color: C.textMuted }}>No events logged for this day</p>}
            {dayEntries.slice(-20).reverse().map((e, i) => (
              <div key={i} className="flex items-center justify-between px-2 py-1 rounded-lg" style={{ background: `${C.card}` }}>
                <div className="flex items-center gap-2">
                  {e.spike && <span className="text-[8px] font-bold px-1 rounded" style={{ background: C.crimson, color: "white" }}>SPIKE</span>}
                  {e.structureTag && <span className="text-[8px] font-bold px-1 rounded" style={{ background: `${C.crimson}30`, color: C.crimson }}>{e.structureTag}</span>}
                  <span className="text-[9px] font-mono" style={{ color: C.textDim }}>
                    {new Date(e.epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                  </span>
                  <span className="text-[9px] font-mono" style={{ color: C.text }}>{e.open} → {e.close}</span>
                </div>
                <span className="text-[9px] font-mono font-bold" style={{ color: C.crimson }}>+{e.movement.toFixed(3)}</span>
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

  // Stats
  const totalMovement = Object.values(summaries).reduce((a, b) => a + b.total, 0);
  const activeDays = Object.keys(summaries).length;
  const totalEvents = Object.values(summaries).reduce((a, b) => a + b.count, 0);

  return (
    <div className="rounded-[2rem] overflow-hidden shadow-2xl" style={{ background: C.card, border: `1px solid ${C.border}` }}>
      {/* Asset tabs */}
      <div className="px-4 pt-4 pb-2">
        <div className="flex gap-1 p-1 rounded-xl" style={{ background: C.bg }}>
          {ASSETS.map((a) => (
            <button key={a} onClick={() => onAssetChange(a)}
              className="flex-1 py-1.5 rounded-lg text-[9px] font-mono font-bold tracking-wider transition"
              style={{ background: a === asset ? C.crimson : "transparent", color: a === asset ? "white" : C.textDim }}>
              {a.replace("VIX75 1s", "VIX1s").replace("1000", "")}
            </button>
          ))}
        </div>
      </div>

      {/* Stats bar */}
      <div className="grid grid-cols-3 gap-2 px-4 pb-3">
        {[
          { label: "EVENTS", value: totalEvents.toString() },
          { label: "ACTIVE DAYS", value: activeDays.toString() },
          { label: "TOTAL PTS", value: `+${totalMovement.toFixed(1)}` },
        ].map((s) => (
          <div key={s.label} className="rounded-xl p-2 text-center" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
            <p className="text-xs font-bold font-mono" style={{ color: C.crimson }}>{s.value}</p>
            <p className="text-[8px] font-mono" style={{ color: C.textMuted }}>{s.label}</p>
          </div>
        ))}
      </div>

      {/* Calendar */}
      <div className="px-5 py-1 flex items-center justify-between">
        <button onClick={() => { if (month === 0) { setMonth(11); setYear(y => y-1); } else setMonth(m => m-1); }} style={{ color: C.crimson }}><ChevronLeft className="h-4 w-4" /></button>
        <span className="text-sm font-bold font-mono" style={{ color: C.crimson }}>{monthName} {year}</span>
        <button onClick={() => { if (month === 11) { setMonth(0); setYear(y => y+1); } else setMonth(m => m+1); }} style={{ color: C.crimson }}><ChevronRight className="h-4 w-4" /></button>
      </div>

      <div className="grid grid-cols-7 px-3 pb-1">
        {["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].map((d) => (
          <div key={d} className="text-center text-[9px] font-mono" style={{ color: C.textMuted }}>{d}</div>
        ))}
      </div>

      <div className="grid grid-cols-7 gap-0.5 px-3 pb-3">
        {Array.from({ length: firstDow }).map((_, i) => <div key={`e-${i}`} />)}
        {Array.from({ length: daysInMonth }).map((_, i) => {
          const day = i + 1;
          const dateStr = `${year}-${String(month+1).padStart(2,"0")}-${String(day).padStart(2,"0")}`;
          const s = summaries[dateStr];
          const isSel = selectedDay === dateStr;
          const isToday = dateStr === now.toISOString().slice(0,10);
          return (
            <button key={day} onClick={() => setSelectedDay(isSel ? null : dateStr)}
              className="aspect-square rounded-lg flex flex-col items-center justify-center"
              style={{ background: isSel ? C.crimson : s ? `${C.crimson}15` : C.bg, border: isToday ? `1px solid ${C.crimson}` : `1px solid ${C.border}` }}>
              <span className="text-[10px] font-mono" style={{ color: isSel ? "white" : s ? C.text : C.textMuted }}>{day}</span>
              {s && <span className="text-[7px] font-mono" style={{ color: isSel ? "white" : C.crimson }}>{s.count}t</span>}
              {s && <span className="text-[7px] font-mono" style={{ color: isSel ? "white" : C.crimsonGlow }}>+{s.total.toFixed(1)}</span>}
            </button>
          );
        })}
      </div>

      {/* Day detail */}
      {selectedDay && (
        <div className="mx-4 mb-4 rounded-xl overflow-hidden" style={{ border: `1px solid ${C.border}` }}>
          <div className="px-3 py-2 flex items-center justify-between" style={{ background: C.bg }}>
            <div>
              <p className="text-xs font-mono font-bold" style={{ color: C.text }}>
                {new Date(selectedDay + "T12:00:00").toLocaleDateString("en-US", { weekday: "long", day: "numeric", month: "short" })}
              </p>
              <p className="text-[9px] font-mono" style={{ color: C.textDim }}>{dayEntries.length} signals</p>
            </div>
            <span className="font-bold font-mono" style={{ color: C.crimson }}>
              +{dayEntries.reduce((a, b) => a + b.movement, 0).toFixed(3)} pts
            </span>
          </div>
          <div className="max-h-56 overflow-y-auto" style={{ scrollbarWidth: "none" }}>
            {dayEntries.slice().reverse().map((e, i) => (
              <div key={i} className="px-3 py-2 flex items-start justify-between" style={{ borderTop: `1px solid ${C.border}` }}>
                <div>
                  <div className="flex items-center gap-1.5 mb-0.5">
                    {e.spike && <span className="text-[7px] font-bold px-1 rounded" style={{ background: C.crimson, color: "white" }}>SPIKE</span>}
                    {e.structureTag && <span className="text-[7px] font-bold px-1 rounded" style={{ background: `${C.crimson}25`, color: C.crimson }}>{e.structureTag}</span>}
                    <span className="text-[9px] font-mono" style={{ color: C.textDim }}>
                      {new Date(e.epoch * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}
                    </span>
                  </div>
                  <p className="text-[10px] font-mono" style={{ color: C.text }}>
                    {e.open.toFixed(2)} <span style={{ color: C.textMuted }}>→</span> {e.close.toFixed(2)}
                  </p>
                  <p className="text-[9px] font-mono" style={{ color: C.textMuted }}>
                    AO {e.ao > 0 ? "+" : ""}{e.ao} · AC {e.ac > 0 ? "+" : ""}{e.ac}
                    {!isVix(asset) && ` · ${e.candlesSinceSpike}c since spike`}
                  </p>
                </div>
                <span className="text-sm font-bold font-mono" style={{ color: C.crimson }}>+{e.movement.toFixed(3)}</span>
              </div>
            ))}
          </div>
          <div className="px-3 py-2 flex gap-2" style={{ background: C.bg }}>
            <button onClick={() => { const csv = generateDailyCSV(dayEntries, asset, selectedDay); downloadAsFile(csv, `itrade_${asset}_${selectedDay}.txt`); }}
              className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-[10px] font-mono font-bold"
              style={{ background: `${C.crimson}20`, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
              <Download className="h-3 w-3" /> Daily Report
            </button>
            <button onClick={async () => { const e = await getEntriesForWeek(asset, selectedDay); const csv = generateWeeklyCSV(e, asset, selectedDay); downloadAsFile(csv, `itrade_${asset}_week_${selectedDay}.txt`); }}
              className="flex-1 flex items-center justify-center gap-1.5 py-2 rounded-xl text-[10px] font-mono font-bold"
              style={{ background: `${C.crimson}20`, color: C.crimson, border: `1px solid ${C.crimsonDim}` }}>
              <Download className="h-3 w-3" /> Weekly Report
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── CANDLE CHART ─────────────────────────────────────────────────────────────
function CandleChart({ candles, vix }: { candles: Candle[]; vix: boolean }) {
  if (!candles.length) return (
    <div className="flex-1 rounded-2xl grid place-items-center text-xs font-mono" style={{ background: "rgba(2,6,14,0.8)", border: `1px solid ${C.border}`, color: C.textMuted }}>
      connecting…
    </div>
  );
  const w = 360; const h = 200; const pad = 8;
  const min = Math.min(...candles.map((c) => c.l));
  const max = Math.max(...candles.map((c) => c.h));
  const range = max - min || 1;
  const cw = (w - pad * 2) / candles.length;
  const y = (v: number) => pad + (1 - (v - min) / range) * (h - pad * 2);
  return (
    <div className="flex-1 rounded-2xl p-2" style={{ background: "rgba(2,6,14,0.8)", border: `1px solid ${C.border}` }}>
      <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full h-full block">
        <line x1={pad} x2={w-pad} y1={h/2} y2={h/2} stroke={C.border} strokeDasharray="3 4" />
        {candles.map((c, i) => {
          const x = pad + i * cw + cw / 2;
          const color = c.spike ? C.crimsonGlow : vix ? "#2dd4bf" : C.crimson;
          return (
            <g key={i}>
              <line x1={x} x2={x} y1={y(c.h)} y2={y(c.l)} stroke={color} strokeWidth={1} />
              <rect x={x - cw * 0.32} y={y(Math.max(c.o, c.c))} width={Math.max(1.5, cw * 0.64)}
                height={Math.max(1.5, Math.abs(y(c.o) - y(c.c)))} fill={color} opacity={0.9} />
            </g>
          );
        })}
      </svg>
    </div>
  );
}

// ─── INDICATOR COMPONENTS (carried over, Crimson themed) ─────────────────────
function IndicatorCard({ index, title, subtitle, badge, children }: {
  index: number; title: string; subtitle: string;
  badge?: { label: string; active?: boolean };
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-xl p-3" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
      <div className="flex items-start justify-between mb-2">
        <div className="min-w-0">
          <h3 className="text-[11px] font-bold uppercase tracking-wider font-mono truncate" style={{ color: C.crimson }}>
            {index}. {title}
          </h3>
          <p className="text-[10px] font-mono truncate" style={{ color: C.textMuted }}>{subtitle}</p>
        </div>
        {badge && (
          <span className="text-[9px] px-1.5 py-0.5 rounded font-mono font-bold border ml-2 flex-shrink-0"
            style={{ background: badge.active ? `${C.crimson}20` : C.card, color: badge.active ? C.crimson : C.textMuted, borderColor: badge.active ? C.crimsonDim : C.border }}>
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
  if (!valid.length) return <div style={{ height }} className="rounded" />;
  const w = 320; const h = height;
  const max = Math.max(...valid.map(Math.abs), 0.001);
  const bw = w / series.length; const mid = h / 2;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full block rounded">
      <line x1={0} x2={w} y1={mid} y2={mid} stroke={C.border} strokeDasharray="2 3" />
      {series.map((v, i) => {
        if (!isFinite(v)) return null;
        const prev = series[i-1]; const up = isFinite(prev) ? v >= prev : v >= 0;
        const bh = Math.max(1.5, (Math.abs(v)/max)*(mid-3));
        return <rect key={i} x={i*bw+0.5} y={v>=0?mid-bh:mid} width={Math.max(1,bw-1)} height={bh} fill={up?"#009688":"#f44336"} opacity={0.9} />;
      })}
    </svg>
  );
}

function ACHistogram({ series, height }: { series: number[]; height: number }) {
  const valid = series.filter((v) => isFinite(v));
  if (!valid.length) return <div style={{ height }} className="rounded" />;
  const w = 320; const h = height;
  const max = Math.max(...valid.map(Math.abs), 0.001);
  const bw = w / series.length; const mid = h / 2;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="w-full block rounded">
      <line x1={0} x2={w} y1={mid} y2={mid} stroke={C.border} strokeDasharray="2 3" />
      {series.map((v, i) => {
        if (!isFinite(v)) return null;
        const prev = series[i-1]; const up = isFinite(prev) ? v >= prev : v >= 0;
        const bh = Math.max(1.5, (Math.abs(v)/max)*(mid-3));
        return <rect key={i} x={i*bw+0.5} y={v>=0?mid-bh:mid} width={Math.max(1,bw-1)} height={bh} fill={up?"#2196f3":"#f44336"} opacity={0.9} />;
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
  const votes = { AO: ao < -2 ? 1 : ao > 2 ? -1 : 0, AC: ac < -1 ? 1 : ac > 1 ? -1 : 0 };
  const total = Object.values(votes).reduce((a, b) => a + b, 0);
  const totalAbs = Object.values(votes).reduce((a, b) => a + Math.abs(b), 0);
  const aligned = !!ind && totalAbs >= 2 && Math.abs(total) === totalAbs;
  return (
    <>
      <IndicatorCard index={1} title="Awesome Oscillator" subtitle="SMA(HL2,5) − SMA(HL2,34) · MT5">
        <AOHistogram series={aoSeries} height={56} />
        <div className="flex justify-between text-[10px] font-mono mt-1">
          <span style={{ color: C.textMuted }}>AO</span>
          <span style={{ color: ao >= 0 ? "#009688" : "#f44336" }}>{ao > 0 ? "+" : ""}{ao.toFixed(3)}</span>
        </div>
      </IndicatorCard>
      <IndicatorCard index={2} title="Accelerator Oscillator" subtitle="AO − SMA(AO,5) · MT5">
        <ACHistogram series={acSeries} height={56} />
        <div className="flex justify-between text-[10px] font-mono mt-1">
          <span style={{ color: C.textMuted }}>AC</span>
          <span style={{ color: ac >= 0 ? "#2196f3" : "#f44336" }}>{ac > 0 ? "+" : ""}{ac.toFixed(3)}</span>
        </div>
      </IndicatorCard>
      <IndicatorCard index={3} title="AO V2 (Kivanç)" subtitle="Signal-line variant · SIG 7">
        <svg viewBox="0 0 320 56" preserveAspectRatio="none" className="w-full block rounded">
          {(() => {
            const { ao: a, signal: s } = aoV2; const w=320; const h=56;
            const all=[...a,...s].filter(v=>isFinite(v)); if(!all.length) return null;
            const max=Math.max(...all.map(Math.abs),0.001); const bw=w/a.length; const mid=h/2;
            const toY=(v:number)=>mid-(v/max)*(mid-4);
            return <>
              <line x1={0} x2={w} y1={mid} y2={mid} stroke={C.border} strokeDasharray="2 3"/>
              <polyline fill="none" stroke="#f44336" strokeWidth="1.5" points={a.map((v,i)=>`${i*bw+bw/2},${toY(v)}`).join(" ")}/>
              <polyline fill="none" stroke="#2196f3" strokeWidth="1.2" strokeDasharray="3 2" points={s.map((v,i)=>`${i*bw+bw/2},${toY(v)}`).join(" ")}/>
            </>;
          })()}
        </svg>
      </IndicatorCard>
      <IndicatorCard index={4} title="AO & MACD Tactic" subtitle="Tea-saucer detection" badge={{ label: macdT.saucerBull ? "SAUCER ▲" : macdT.saucerBear ? "SAUCER ▼" : "NO SAUCER", active: macdT.saucerBull || macdT.saucerBear }}>
        <AOHistogram series={macdT.ao} height={56} />
      </IndicatorCard>
      <IndicatorCard index={5} title="Classic AO (Orekhov)" subtitle="Standard 5/34 momentum">
        <AOHistogram series={aoSeries} height={56} />
      </IndicatorCard>
      <div className="text-xs font-mono text-center py-1" style={{ color: C.textDim }}>
        {aligned ? `Indicators aligned (${Math.abs(total)}/${totalAbs})` : `Scanning… (${total>=0?"+":""}${total})`}
      </div>
      <button className="w-full h-13 rounded-2xl font-bold tracking-[0.25em] text-base py-3"
        style={{ background: aligned ? C.crimson : C.bg, color: aligned ? "white" : C.textMuted, border: `1px solid ${aligned ? C.crimson : C.border}` }}>
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
  if (!vixData) return <div className="text-center py-8 text-xs font-mono" style={{ color: C.textMuted }}>Gathering data…</div>;
  const trendColor = vixData.trend === "bullish" ? "#009688" : vixData.trend === "bearish" ? "#f44336" : C.crimson;
  return (
    <>
      <div className="rounded-xl p-3" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
        <div className="flex items-center justify-between mb-2">
          <span className="text-[10px] font-mono font-bold uppercase tracking-wider" style={{ color: C.crimson }}>Trend Structure</span>
          <span className="text-[10px] font-bold font-mono" style={{ color: trendColor }}>{vixData.trend.toUpperCase()}</span>
        </div>
        {vixData.narratives.map((n, i) => (
          <p key={i} className="text-[10px] font-mono leading-relaxed" style={{ color: C.text }}>
            <span style={{ color: C.crimson }}>› </span>{n}
          </p>
        ))}
      </div>
      <div className="rounded-xl p-3" style={{ background: C.bg, border: `1px solid ${C.border}` }}>
        <div className="text-[10px] font-mono font-bold uppercase tracking-wider mb-2" style={{ color: C.crimson }}>Market Structure</div>
        <div className="flex flex-wrap gap-1">
          {vixData.structure.slice(-8).map((s, i) => (
            <span key={i} className="text-[9px] font-mono font-bold px-1.5 py-0.5 rounded border"
              style={{ background: (s.type==="HH"||s.type==="HL") ? `${C.crimson}15` : `${C.textMuted}15`, color: (s.type==="HH"||s.type==="HL") ? C.crimson : C.textDim, borderColor: C.border }}>
              {s.type} {s.price.toFixed(2)}
            </span>
          ))}
        </div>
      </div>
      <IndicatorCard index={1} title="Moving Averages" subtitle="SMA20 (amber) · SMA50 (purple)">
        <svg viewBox="0 0 320 64" preserveAspectRatio="none" className="w-full block rounded">
          {(() => {
            const w=320; const h=64; const cls=closes;
            const all=[...cls,...ma20,...ma50].filter(v=>isFinite(v)); if(!all.length) return null;
            const minV=Math.min(...all); const maxV=Math.max(...all); const range=maxV-minV||1;
            const bw=w/cls.length; const toY=(v:number)=>4+(1-(v-minV)/range)*(h-8);
            return <>
              <polyline fill="none" stroke={C.border} strokeWidth="0.8" points={cls.map((v,i)=>`${i*bw+bw/2},${toY(v)}`).join(" ")}/>
              <polyline fill="none" stroke="#f59e0b" strokeWidth="1.5" points={ma20.map((v,i)=>isFinite(v)?`${i*bw+bw/2},${toY(v)}`:null).filter(Boolean).join(" ")}/>
              <polyline fill="none" stroke="#a855f7" strokeWidth="1.5" points={ma50.map((v,i)=>isFinite(v)?`${i*bw+bw/2},${toY(v)}`:null).filter(Boolean).join(" ")}/>
            </>;
          })()}
        </svg>
        <div className="flex justify-between text-[9px] font-mono mt-1">
          <span style={{ color: "#f59e0b" }}>MA20 {vixData.ma20.toFixed(3)}</span>
          <span style={{ color: "#a855f7" }}>MA50 {vixData.ma50.toFixed(3)}</span>
        </div>
      </IndicatorCard>
      <IndicatorCard index={2} title="Awesome Oscillator" subtitle="SMA(HL2,5) − SMA(HL2,34) · MT5">
        <AOHistogram series={aoSeries} height={56} />
      </IndicatorCard>
      <IndicatorCard index={3} title="Accelerator Oscillator" subtitle="AO − SMA(AO,5) · MT5">
        <ACHistogram series={acSeries} height={56} />
      </IndicatorCard>
    </>
  );
}
