// Journal engine — IndexedDB persistence, candle logging, state restoration

export type JournalEntry = {
  id?: number;
  asset: string;
  epoch: number;           // candle open time (unix seconds)
  open: number;
  high: number;
  low: number;
  close: number;
  movement: number;        // |open - close|
  spike: boolean;
  candlesSinceSpike: number;
  ao: number;
  ac: number;
  structureTag?: string;   // HH/HL/LH/LL/BOS/ChoCH for VIX
  note?: string;
};

export type AppState = {
  view: string;
  activeAsset: string;
  drawerOpen: boolean;
  journalAsset: string;
  journalDate: string;     // ISO date string
};

const DB_NAME = "itrade_journal";
const DB_VERSION = 1;

let db: IDBDatabase | null = null;

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (db) { resolve(db); return; }
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (e) => {
      const d = (e.target as IDBOpenDBRequest).result;
      if (!d.objectStoreNames.contains("entries")) {
        const store = d.createObjectStore("entries", { keyPath: "id", autoIncrement: true });
        store.createIndex("asset_epoch", ["asset", "epoch"], { unique: true });
        store.createIndex("asset", "asset", { unique: false });
        store.createIndex("epoch", "epoch", { unique: false });
      }
      if (!d.objectStoreNames.contains("state")) {
        d.createObjectStore("state", { keyPath: "key" });
      }
    };
    req.onsuccess = (e) => { db = (e.target as IDBOpenDBRequest).result; resolve(db!); };
    req.onerror = () => reject(req.error);
  });
}

export async function logCandle(entry: JournalEntry): Promise<void> {
  const d = await openDB();
  return new Promise((resolve, reject) => {
    const tx = d.transaction("entries", "readwrite");
    const store = tx.objectStore("entries");
    // Use put with index check to avoid dupes
    const idx = store.index("asset_epoch");
    const getReq = idx.get([entry.asset, entry.epoch]);
    getReq.onsuccess = () => {
      if (getReq.result) {
        // Update existing
        const existing = getReq.result;
        store.put({ ...entry, id: existing.id });
      } else {
        store.add(entry);
      }
      resolve();
    };
    getReq.onerror = () => reject(getReq.error);
  });
}

export async function getEntriesForDay(asset: string, dateStr: string): Promise<JournalEntry[]> {
  const d = await openDB();
  const start = new Date(dateStr).setHours(0,0,0,0) / 1000;
  const end = new Date(dateStr).setHours(23,59,59,999) / 1000;
  return new Promise((resolve, reject) => {
    const tx = d.transaction("entries", "readonly");
    const store = tx.objectStore("entries");
    const idx = store.index("asset_epoch");
    const range = IDBKeyRange.bound([asset, start], [asset, end]);
    const req = idx.getAll(range);
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => reject(req.error);
  });
}

export async function getEntriesForWeek(asset: string, weekStart: string): Promise<JournalEntry[]> {
  const d = await openDB();
  const start = new Date(weekStart).setHours(0,0,0,0) / 1000;
  const end = start + 7 * 24 * 3600;
  return new Promise((resolve, reject) => {
    const tx = d.transaction("entries", "readonly");
    const store = tx.objectStore("entries");
    const idx = store.index("asset_epoch");
    const range = IDBKeyRange.bound([asset, start], [asset, end]);
    const req = idx.getAll(range);
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => reject(req.error);
  });
}

export async function getDaySummaries(asset: string, year: number, month: number): Promise<Record<string, { count: number; total: number }>> {
  const d = await openDB();
  const start = new Date(year, month, 1).getTime() / 1000;
  const end = new Date(year, month + 1, 0, 23, 59, 59).getTime() / 1000;
  return new Promise((resolve, reject) => {
    const tx = d.transaction("entries", "readonly");
    const store = tx.objectStore("entries");
    const idx = store.index("asset_epoch");
    const range = IDBKeyRange.bound([asset, start], [asset, end]);
    const req = idx.getAll(range);
    req.onsuccess = () => {
      const entries: JournalEntry[] = req.result || [];
      const summaries: Record<string, { count: number; total: number }> = {};
      entries.forEach((e) => {
        const day = new Date(e.epoch * 1000).toISOString().slice(0, 10);
        if (!summaries[day]) summaries[day] = { count: 0, total: 0 };
        summaries[day].count++;
        summaries[day].total += e.movement;
      });
      resolve(summaries);
    };
    req.onerror = () => reject(req.error);
  });
}

// App state persistence
export async function saveState(state: Partial<AppState>): Promise<void> {
  const d = await openDB();
  return new Promise((resolve) => {
    const tx = d.transaction("state", "readwrite");
    const store = tx.objectStore("state");
    store.put({ key: "appState", ...state });
    tx.oncomplete = () => resolve();
  });
}

export async function loadState(): Promise<Partial<AppState>> {
  const d = await openDB();
  return new Promise((resolve) => {
    const tx = d.transaction("state", "readonly");
    const store = tx.objectStore("state");
    const req = store.get("appState");
    req.onsuccess = () => resolve(req.result || {});
    req.onerror = () => resolve({});
  });
}

// PDF generation (daily/weekly)
export function generateDailyCSV(entries: JournalEntry[], asset: string, date: string): string {
  const lines = [
    `iTRADE Journal — ${asset} — ${date}`,
    `Total Events: ${entries.length}`,
    `Total Movement: ${entries.reduce((a, b) => a + b.movement, 0).toFixed(4)} pts`,
    `Spikes: ${entries.filter((e) => e.spike).length}`,
    ``,
    `Time,Open,High,Low,Close,Movement,Spike,Candles Since Spike,AO,AC,Structure`,
    ...entries.map((e) => {
      const t = new Date(e.epoch * 1000).toLocaleTimeString();
      return `${t},${e.open},${e.high},${e.low},${e.close},${e.movement.toFixed(4)},${e.spike ? "YES" : ""},${e.candlesSinceSpike},${e.ao},${e.ac},${e.structureTag || ""}`;
    })
  ];
  return lines.join("\n");
}

export function generateWeeklyCSV(entries: JournalEntry[], asset: string, weekStart: string): string {
  // Group by day
  const byDay: Record<string, JournalEntry[]> = {};
  entries.forEach((e) => {
    const day = new Date(e.epoch * 1000).toISOString().slice(0, 10);
    if (!byDay[day]) byDay[day] = [];
    byDay[day].push(e);
  });

  const lines = [
    `iTRADE Weekly Report — ${asset} — Week of ${weekStart}`,
    `Total Events: ${entries.length}`,
    `Total Movement: ${entries.reduce((a, b) => a + b.movement, 0).toFixed(4)} pts`,
    `Total Spikes: ${entries.filter((e) => e.spike).length}`,
    ``,
  ];

  Object.entries(byDay).sort().forEach(([day, dayEntries]) => {
    const total = dayEntries.reduce((a, b) => a + b.movement, 0);
    lines.push(`--- ${day} | ${dayEntries.length} events | ${total.toFixed(4)} pts ---`);
    dayEntries.forEach((e) => {
      const t = new Date(e.epoch * 1000).toLocaleTimeString();
      lines.push(`  ${t} | O:${e.open} C:${e.close} | Δ${e.movement.toFixed(4)} | ${e.spike ? "SPIKE" : ""} ${e.structureTag || ""}`);
    });
    lines.push("");
  });

  return lines.join("\n");
}

export function downloadAsFile(content: string, filename: string): void {
  const blob = new Blob([content], { type: "text/plain" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
