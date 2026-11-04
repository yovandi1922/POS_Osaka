// apps/api/lib/format.ts
// Utilitas format uang & tanggal. Tanggal bisnis memakai WIB (UTC+7, tanpa DST).

const JKT_OFFSET_MS = 7 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** 15000 → "Rp 15.000" ; -2500 → "-Rp 2.500" */
export function formatRupiah(value: number | string | null | undefined): string {
  const n = Math.round(Number(value ?? 0));
  const sign = n < 0 ? '-' : '';
  const digits = Math.abs(n)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${sign}Rp ${digits}`;
}

/** 1234.5 → "1.234,5" */
export function formatNumber(value: number | string | null | undefined, maxFractionDigits = 2): string {
  const n = Number(value ?? 0);
  const raw = n.toFixed(maxFractionDigits);
  const fixed = raw.includes('.') ? raw.replace(/\.?0+$/, '') : raw;
  const [int, frac] = fixed.split('.');
  const intPart = int.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return frac ? `${intPart},${frac}` : intPart;
}

/** Input uang bebas format ("Rp 22.000", "22000") → 22000; kosong/invalid → NaN */
export function parseMoney(value: string): number {
  const digits = value.replace(/[^\d]/g, '');
  return digits ? Number(digits) : NaN;
}

/** Input desimal ("0,5" atau "0.5") → 0.5; kosong/invalid → NaN */
export function parseDecimal(value: string): number {
  const cleaned = value.trim().replace(/\s/g, '').replace(',', '.');
  if (!cleaned) return NaN;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : NaN;
}

/** Tanggal lokal WIB dalam format YYYY-MM-DD */
export function jakartaDate(d: Date = new Date()): string {
  return new Date(d.getTime() + JKT_OFFSET_MS).toISOString().slice(0, 10);
}

/** Tambah n hari pada string YYYY-MM-DD */
export function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  return new Date(d.getTime() + n * DAY_MS).toISOString().slice(0, 10);
}

/** YYYY-MM-01 dari tanggal YYYY-MM-DD */
export function startOfMonth(date: string): string {
  return `${date.slice(0, 8)}01`;
}

/** Selisih hari (b - a) untuk string YYYY-MM-DD */
export function diffDays(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / DAY_MS);
}

/** Awal hari WIB → ISO UTC (untuk filter created_at timestamptz) */
export function jakartaDayStartISO(date: string): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) - JKT_OFFSET_MS).toISOString();
}

const DAY_NAMES = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/** Indeks hari (0=Minggu) dari YYYY-MM-DD */
export function dayOfWeek(date: string): number {
  return new Date(`${date}T00:00:00Z`).getUTCDay();
}

export function dayName(date: string): string {
  return DAY_NAMES[dayOfWeek(date)];
}

/** "2026-10-22" → "22 Okt" */
export function shortDate(date: string): string {
  const [, m, d] = date.split('-');
  return `${Number(d)} ${MONTH_SHORT[Number(m) - 1]}`;
}

/** "2026-10-22" → "22 Okt 2026" */
export function longDate(date: string): string {
  const [y] = date.split('-');
  return `${shortDate(date)} ${y}`;
}

/** ISO timestamp → "22 Okt 2026, 14:05" (WIB) */
export function formatDateTime(iso: string): string {
  const local = new Date(new Date(iso).getTime() + JKT_OFFSET_MS);
  const date = local.toISOString().slice(0, 10);
  const time = local.toISOString().slice(11, 16);
  return `${longDate(date)}, ${time}`;
}

export const PAYMENT_LABEL: Record<string, string> = {
  cash: 'Tunai',
  qris: 'QRIS',
  debit: 'Debit',
};

export const ROLE_LABEL: Record<string, string> = {
  kasir: 'Kasir',
  admin: 'Admin',
  owner: 'Owner',
};
