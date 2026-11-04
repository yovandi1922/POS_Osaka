// apps/api/lib/predict.ts
// Prediksi omset harian sederhana & transparan:
//   1. Faktor day-of-week  = rata-rata omset per hari (Senin..Minggu) / rata-rata keseluruhan
//   2. Basis               = weighted moving average 7 hari terakhir (bobot linear 1..N, terbaru terberat)
//                            dihitung dari omset yang sudah dinormalisasi faktor hari, agar hari ramai
//                            di jendela WMA tidak terhitung dua kali.
//   3. Prediksi hari H     = basis × faktor(hari H); rentang = 85% .. 115%
// Input: deret harian (boleh berisi 0) dari RPC revenue_by_day, urut atau tidak.

import { addDays, dayOfWeek } from './format';

export interface DailyRevenue {
  /** YYYY-MM-DD (WIB) */
  date: string;
  revenue: number;
}

export interface Prediction {
  date: string;
  predicted: number;
  low: number;
  high: number;
}

export type PredictResult =
  | {
      ok: true;
      predictions: Prediction[];
      meta: {
        days_of_data: number;
        window_days: number;
        base_daily: number;
        average_daily: number;
        dow_factors: Record<string, number>;
        low_accuracy: boolean;
        method: string;
      };
    }
  | { ok: false; error: string; days_of_data: number };

const WMA_WINDOW = 7;
const MIN_DAYS = 3;
const LOW_ACCURACY_DAYS = 7;
const DOW_LABEL = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

export function predictRevenue(history: DailyRevenue[], daysAhead = 7): PredictResult {
  const horizon = Math.min(Math.max(Math.floor(daysAhead) || 7, 1), 60);

  // Urutkan, buang duplikat tanggal (ambil yang terakhir), sanitasi angka.
  const byDate = new Map<string, number>();
  for (const row of history) {
    const value = Number(row.revenue);
    byDate.set(row.date, Number.isFinite(value) && value > 0 ? value : 0);
  }
  const series = Array.from(byDate.entries())
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([date, revenue]) => ({ date, revenue }));

  // Abaikan hari-hari kosong sebelum transaksi pertama (toko belum beroperasi/belum pakai sistem).
  const firstActive = series.findIndex((d) => d.revenue > 0);
  const data = firstActive === -1 ? [] : series.slice(firstActive);
  const daysOfData = data.length;

  if (daysOfData < MIN_DAYS) {
    return {
      ok: false,
      days_of_data: daysOfData,
      error:
        daysOfData === 0
          ? 'Belum ada data penjualan sama sekali, jadi prediksi belum bisa dibuat.'
          : `Data penjualan baru ${daysOfData} hari. Minimal butuh ${MIN_DAYS} hari data untuk membuat prediksi.`,
    };
  }

  // 1) Faktor day-of-week
  const overallAvg = data.reduce((s, d) => s + d.revenue, 0) / daysOfData;
  const sums = new Array<number>(7).fill(0);
  const counts = new Array<number>(7).fill(0);
  for (const d of data) {
    const dow = dayOfWeek(d.date);
    sums[dow] += d.revenue;
    counts[dow] += 1;
  }
  const factors = sums.map((sum, i) => {
    if (counts[i] === 0 || overallAvg <= 0) return 1; // belum ada sampel untuk hari ini → netral
    return sum / counts[i] / overallAvg;
  });

  // 2) WMA atas omset ter-normalisasi faktor hari
  const window = data.slice(-WMA_WINDOW);
  let weightedSum = 0;
  let weightTotal = 0;
  window.forEach((d, idx) => {
    const weight = idx + 1; // 1..N, terbaru paling berat
    const factor = factors[dayOfWeek(d.date)];
    const normalized = factor > 0 ? d.revenue / factor : d.revenue;
    weightedSum += normalized * weight;
    weightTotal += weight;
  });
  const base = weightTotal > 0 ? weightedSum / weightTotal : 0;

  // 3) Proyeksi mulai hari setelah data terakhir
  const lastDate = data[data.length - 1].date;
  const predictions: Prediction[] = [];
  for (let i = 1; i <= horizon; i++) {
    const date = addDays(lastDate, i);
    const predicted = Math.max(0, Math.round(base * factors[dayOfWeek(date)]));
    predictions.push({
      date,
      predicted,
      low: Math.round(predicted * 0.85),
      high: Math.round(predicted * 1.15),
    });
  }

  const dowFactors: Record<string, number> = {};
  factors.forEach((f, i) => {
    dowFactors[DOW_LABEL[i]] = Math.round(f * 100) / 100;
  });

  return {
    ok: true,
    predictions,
    meta: {
      days_of_data: daysOfData,
      window_days: window.length,
      base_daily: Math.round(base),
      average_daily: Math.round(overallAvg),
      dow_factors: dowFactors,
      low_accuracy: daysOfData < LOW_ACCURACY_DAYS,
      method: 'Weighted moving average 7 hari (bobot linear) × faktor hari dalam seminggu',
    },
  };
}
