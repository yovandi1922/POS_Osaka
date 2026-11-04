// apps/api/lib/ai/tools.ts
// Definisi tools untuk Claude + eksekutornya. Semua angka diambil langsung dari database.
import type Anthropic from '@anthropic-ai/sdk';
import type { SupabaseClient } from '@supabase/supabase-js';
import { addDays, jakartaDate } from '../format';
import { predictRevenue } from '../predict';
import {
  fetchExpensesInRange,
  fetchMenuPerformance,
  fetchPredictionHistory,
  fetchRevenueByDay,
} from '../queries';
import type { Ingredient, UserRole } from '../types';

export const tools: Anthropic.Tool[] = [
  {
    name: 'get_stock',
    description:
      'Ambil stok bahan baku saat ini. Isi ingredient_name untuk mencari bahan tertentu (pencarian sebagian, tidak case-sensitive); kosongkan untuk semua bahan. Mengembalikan nama, stok, satuan, stok minimum, dan status (aman/menipis/habis).',
    input_schema: {
      type: 'object',
      properties: {
        ingredient_name: {
          type: 'string',
          description: 'Nama atau sebagian nama bahan, mis. "susu" atau "kopi".',
        },
      },
      required: [],
    },
  },
  {
    name: 'get_low_stock_items',
    description:
      'Daftar bahan baku yang stoknya sudah di bawah atau sama dengan stok minimum (perlu restock), beserta kekurangannya.',
    input_schema: { type: 'object', properties: {}, required: [] },
  },
  {
    name: 'get_menu_performance',
    description:
      'Performa penjualan menu dalam N hari terakhir (termasuk hari ini): 5 menu terlaris, 5 menu paling jarang laku, dan total item terjual.',
    input_schema: {
      type: 'object',
      properties: {
        days: {
          type: 'integer',
          description: 'Jumlah hari ke belakang termasuk hari ini (1 = hari ini). Default 7, maks 365.',
        },
      },
      required: [],
    },
  },
  {
    name: 'get_revenue',
    description:
      'Ringkasan keuangan N hari terakhir (termasuk hari ini): omset, jumlah transaksi, rata-rata per transaksi, total pengeluaran, dan laba kotor (omset dikurangi pengeluaran). Hanya untuk admin/owner.',
    input_schema: {
      type: 'object',
      properties: {
        days: {
          type: 'integer',
          description: 'Jumlah hari ke belakang termasuk hari ini (1 = hari ini). Default 7, maks 365.',
        },
      },
      required: [],
    },
  },
  {
    name: 'get_expenses',
    description:
      'Pengeluaran N hari terakhir (termasuk hari ini), dikelompokkan per kategori, beserta totalnya. Hanya untuk admin/owner.',
    input_schema: {
      type: 'object',
      properties: {
        days: {
          type: 'integer',
          description: 'Jumlah hari ke belakang termasuk hari ini. Default 30, maks 365.',
        },
      },
      required: [],
    },
  },
  {
    name: 'predict_revenue',
    description:
      'Prediksi omset harian untuk N hari ke depan memakai 60 hari data historis (weighted moving average 7 hari × faktor hari dalam seminggu). Mengembalikan prediksi per hari dengan rentang low (85%) – high (115%), total, dan flag low_accuracy. Hanya untuk admin/owner.',
    input_schema: {
      type: 'object',
      properties: {
        days_ahead: {
          type: 'integer',
          description: 'Jumlah hari ke depan yang diprediksi. Default 7, maks 30.',
        },
      },
      required: [],
    },
  },
];

export interface ToolContext {
  /** Client untuk query data (service role di server, atau client user sebagai fallback). */
  supabase: SupabaseClient;
  role: UserRole;
}

export interface ToolResult {
  content: string;
  isError: boolean;
}

const FINANCE_TOOLS = new Set(['get_revenue', 'get_expenses', 'predict_revenue']);

function intParam(input: Record<string, unknown>, key: string, fallback: number, max: number): number {
  const raw = input[key];
  const n = typeof raw === 'number' ? raw : typeof raw === 'string' ? Number(raw) : NaN;
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(Math.floor(n), 1), max);
}

function periodOf(days: number) {
  const end = jakartaDate();
  const start = addDays(end, -(days - 1));
  return { start, end, label: days === 1 ? 'hari ini' : `${days} hari terakhir` };
}

function stockStatus(stock: number, min: number): 'habis' | 'menipis' | 'aman' {
  if (stock <= 0) return 'habis';
  if (stock <= min) return 'menipis';
  return 'aman';
}

async function loadIngredients(supabase: SupabaseClient, nameFilter?: string): Promise<Ingredient[]> {
  let query = supabase
    .from('ingredients')
    .select('id, name, unit, current_stock, min_stock, cost_per_unit')
    .order('name');
  if (nameFilter) {
    // Escape karakter wildcard agar input user tidak mengubah pola LIKE.
    const safe = nameFilter.replace(/[%_\\]/g, (c) => `\\${c}`);
    query = query.ilike('name', `%${safe}%`);
  }
  const { data, error } = await query;
  if (error) throw new Error(`Gagal memuat stok: ${error.message}`);
  return ((data ?? []) as Ingredient[]).map((i) => ({
    ...i,
    current_stock: Number(i.current_stock),
    min_stock: Number(i.min_stock),
    cost_per_unit: Number(i.cost_per_unit),
  }));
}

async function run(name: string, input: Record<string, unknown>, ctx: ToolContext): Promise<unknown> {
  const { supabase } = ctx;

  switch (name) {
    case 'get_stock': {
      const filter =
        typeof input.ingredient_name === 'string' && input.ingredient_name.trim()
          ? input.ingredient_name.trim().slice(0, 60)
          : undefined;
      const items = await loadIngredients(supabase, filter);
      return {
        filter: filter ?? null,
        count: items.length,
        items: items.map((i) => ({
          name: i.name,
          stock: i.current_stock,
          unit: i.unit,
          min: i.min_stock,
          status: stockStatus(i.current_stock, i.min_stock),
        })),
      };
    }

    case 'get_low_stock_items': {
      const items = (await loadIngredients(supabase)).filter((i) => i.current_stock <= i.min_stock);
      return {
        count: items.length,
        items: items.map((i) => ({
          name: i.name,
          stock: i.current_stock,
          unit: i.unit,
          min: i.min_stock,
          shortage: Math.max(0, Math.round((i.min_stock - i.current_stock) * 1000) / 1000),
          status: stockStatus(i.current_stock, i.min_stock),
        })),
      };
    }

    case 'get_menu_performance': {
      const days = intParam(input, 'days', 7, 365);
      const p = periodOf(days);
      const rows = await fetchMenuPerformance(supabase, p.start, p.end);
      const sold = rows.filter((r) => r.qty_sold > 0);
      const top = [...sold].sort((a, b) => b.qty_sold - a.qty_sold).slice(0, 5);
      const bottom = rows
        .filter((r) => r.is_active)
        .sort((a, b) => a.qty_sold - b.qty_sold || a.revenue - b.revenue)
        .slice(0, 5);
      const shape = (r: (typeof rows)[number]) => ({
        name: r.name,
        category: r.category,
        qty_sold: r.qty_sold,
        revenue: r.revenue,
      });
      return {
        period: { ...p },
        total_sold: rows.reduce((s, r) => s + r.qty_sold, 0),
        total_revenue: rows.reduce((s, r) => s + r.revenue, 0),
        top: top.map(shape),
        bottom: bottom.map(shape),
      };
    }

    case 'get_revenue': {
      const days = intParam(input, 'days', 7, 365);
      const p = periodOf(days);
      const [daily, expenses] = await Promise.all([
        fetchRevenueByDay(supabase, p.start, p.end),
        fetchExpensesInRange(supabase, p.start, p.end),
      ]);
      const revenue = daily.reduce((s, d) => s + d.revenue, 0);
      const transactions = daily.reduce((s, d) => s + d.tx_count, 0);
      const totalExpenses = expenses.reduce((s, e) => s + e.amount, 0);
      return {
        period: { ...p },
        revenue,
        transactions,
        avg_per_transaction: transactions > 0 ? Math.round(revenue / transactions) : 0,
        expenses: totalExpenses,
        gross_profit: revenue - totalExpenses,
        note: 'gross_profit = omset - pengeluaran tercatat pada periode yang sama.',
        daily: days <= 14 ? daily.map((d) => ({ date: d.day, revenue: d.revenue, tx: d.tx_count })) : undefined,
      };
    }

    case 'get_expenses': {
      const days = intParam(input, 'days', 30, 365);
      const p = periodOf(days);
      const expenses = await fetchExpensesInRange(supabase, p.start, p.end);
      const byCategory = new Map<string, number>();
      for (const e of expenses) byCategory.set(e.category, (byCategory.get(e.category) ?? 0) + e.amount);
      return {
        period: { ...p },
        total: expenses.reduce((s, e) => s + e.amount, 0),
        count: expenses.length,
        by_category: Array.from(byCategory.entries())
          .map(([category, total]) => ({ category, total }))
          .sort((a, b) => b.total - a.total),
      };
    }

    case 'predict_revenue': {
      const daysAhead = intParam(input, 'days_ahead', 7, 30);
      const history = await fetchPredictionHistory(supabase, 60);
      const result = predictRevenue(history, daysAhead);
      if (!result.ok) {
        return { ok: false, error: result.error, days_of_data: result.days_of_data };
      }
      const total = result.predictions.reduce((s, p) => s + p.predicted, 0);
      return {
        ok: true,
        days_ahead: daysAhead,
        predictions: result.predictions,
        total_predicted: total,
        total_low: Math.round(total * 0.85),
        total_high: Math.round(total * 1.15),
        ...result.meta,
        disclaimer:
          'Estimasi statistik dari data historis, bukan jaminan. Dapat meleset karena cuaca, event, promo, atau hari libur.',
      };
    }

    default:
      throw new Error(`Tool tidak dikenal: ${name}`);
  }
}

export async function executeTool(name: string, rawInput: unknown, ctx: ToolContext): Promise<ToolResult> {
  if (FINANCE_TOOLS.has(name) && ctx.role !== 'admin' && ctx.role !== 'owner') {
    return {
      content: JSON.stringify({
        error: 'Akses ditolak: data keuangan (omset total, pengeluaran, prediksi) hanya untuk admin/owner.',
      }),
      isError: true,
    };
  }
  const input =
    rawInput && typeof rawInput === 'object' && !Array.isArray(rawInput)
      ? (rawInput as Record<string, unknown>)
      : {};
  try {
    const result = await run(name, input, ctx);
    return { content: JSON.stringify(result), isError: false };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Terjadi kesalahan saat mengambil data.';
    return { content: JSON.stringify({ error: message }), isError: true };
  }
}
