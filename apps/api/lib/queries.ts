// apps/api/lib/queries.ts
// Query bersama yang dipakai halaman server, dashboard client, dan tools AI.
import type { SupabaseClient } from '@supabase/supabase-js';
import { addDays, jakartaDate } from './format';
import type { DailyRevenue } from './predict';
import type { MenuPerformanceRow, RevenueByDayRow } from './types';

export async function fetchRevenueByDay(
  supabase: SupabaseClient,
  start: string,
  end: string,
): Promise<RevenueByDayRow[]> {
  const { data, error } = await supabase.rpc('revenue_by_day', { p_start: start, p_end: end });
  if (error) throw new Error(`Gagal memuat omset harian: ${error.message}`);
  return ((data ?? []) as RevenueByDayRow[]).map((r) => ({
    day: r.day,
    revenue: Number(r.revenue),
    tx_count: Number(r.tx_count),
  }));
}

export async function fetchMenuPerformance(
  supabase: SupabaseClient,
  start: string,
  end: string,
): Promise<MenuPerformanceRow[]> {
  const { data, error } = await supabase.rpc('menu_performance', { p_start: start, p_end: end });
  if (error) throw new Error(`Gagal memuat performa menu: ${error.message}`);
  return ((data ?? []) as MenuPerformanceRow[]).map((r) => ({
    ...r,
    qty_sold: Number(r.qty_sold),
    revenue: Number(r.revenue),
  }));
}

export async function fetchExpensesInRange(
  supabase: SupabaseClient,
  start: string,
  end: string,
): Promise<{ category: string; amount: number; expense_date: string }[]> {
  const { data, error } = await supabase
    .from('expenses')
    .select('category, amount, expense_date')
    .gte('expense_date', start)
    .lte('expense_date', end);
  if (error) throw new Error(`Gagal memuat pengeluaran: ${error.message}`);
  return ((data ?? []) as { category: string; amount: number; expense_date: string }[]).map((e) => ({
    ...e,
    amount: Number(e.amount),
  }));
}

/**
 * Riwayat omset `days` hari yang berakhir KEMARIN (hari ini belum selesai,
 * memasukkannya akan menarik prediksi ke bawah).
 */
export async function fetchPredictionHistory(
  supabase: SupabaseClient,
  days = 60,
): Promise<DailyRevenue[]> {
  const end = addDays(jakartaDate(), -1);
  const start = addDays(end, -(days - 1));
  const rows = await fetchRevenueByDay(supabase, start, end);
  return rows.map((r) => ({ date: r.day, revenue: r.revenue }));
}
