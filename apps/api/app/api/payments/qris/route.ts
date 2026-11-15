// apps/api/app/api/payments/qris/route.ts
// QRIS dinamis Midtrans untuk aplikasi kasir.
//   POST   { items:[{menu_item_id, qty, notes?}] } → buat QR (harga dihitung di server dari menu_items)
//   GET    ?order_id=…  → cek status ke Midtrans; bila lunas, catat transaksi (create_transaction) sekali saja
//   DELETE ?order_id=…  → batalkan QR (bila ternyata sudah dibayar, transaksi tetap dicatat)
// Hanya kasir pembuat QR yang boleh mengakses order-nya. Tabel qris_payments ditulis via service role.
import type { SupabaseClient } from '@supabase/supabase-js';
import { authenticateRequest, type AuthedRequest } from '@/lib/auth';
import { json, preflight } from '@/lib/http';
import {
  cancelCharge,
  chargeQris,
  getStatus,
  midtransConfigured,
  midtransIsProduction,
  outcomeOf,
} from '@/lib/midtrans';
import { createAdminClient } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const EXPIRY_MINUTES = 15;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface PaymentRow {
  order_id: string;
  cashier_id: string;
  items: { menu_item_id: string; qty: number; notes: string | null }[];
  gross_amount: number | string;
  status: 'pending' | 'processing' | 'paid' | 'expired' | 'cancelled' | 'failed';
  qr_string: string | null;
  qr_url: string | null;
  expires_at: string | null;
  transaction_id: string | null;
  error: string | null;
}

interface Ctx {
  auth: AuthedRequest;
  admin: SupabaseClient;
}

export function OPTIONS(request: Request) {
  return preflight(request);
}

async function context(request: Request): Promise<Ctx | { error: Response }> {
  const auth = await authenticateRequest(request);
  if (!auth) return { error: json(request, { error: 'Unauthorized' }, 401) };
  if (!midtransConfigured()) {
    return { error: json(request, { error: 'QRIS belum dikonfigurasi: isi MIDTRANS_SERVER_KEY di server.' }, 503) };
  }
  const admin = createAdminClient();
  if (!admin) {
    return { error: json(request, { error: 'SUPABASE_SERVICE_ROLE_KEY belum dikonfigurasi di server.' }, 500) };
  }
  return { auth, admin };
}

async function view(admin: SupabaseClient, row: PaymentRow) {
  let transaction: unknown = null;
  if (row.transaction_id) {
    const { data } = await admin.from('transactions').select('*').eq('id', row.transaction_id).maybeSingle();
    transaction = data;
  }
  return {
    order_id: row.order_id,
    status: row.status,
    gross_amount: Number(row.gross_amount),
    qr_string: row.qr_string,
    qr_url: row.qr_url,
    expires_at: row.expires_at,
    error: row.error,
    transaction,
    is_production: midtransIsProduction(),
  };
}

async function loadOwn(ctx: Ctx, request: Request): Promise<PaymentRow | Response> {
  const orderId = new URL(request.url).searchParams.get('order_id') ?? '';
  if (!orderId) return json(request, { error: 'Parameter order_id wajib diisi.' }, 400);
  const { data } = await ctx.admin.from('qris_payments').select('*').eq('order_id', orderId).maybeSingle();
  const row = data as PaymentRow | null;
  if (!row || row.cashier_id !== ctx.auth.user.id) {
    return json(request, { error: 'Pembayaran tidak ditemukan.' }, 404);
  }
  return row;
}

async function setStatus(admin: SupabaseClient, orderId: string, patch: Partial<PaymentRow>, onlyIf?: PaymentRow['status']) {
  let q = admin
    .from('qris_payments')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('order_id', orderId);
  if (onlyIf) q = q.eq('status', onlyIf);
  const { data } = await q.select('*').maybeSingle();
  return data as PaymentRow | null;
}

/** Uang sudah masuk → catat transaksi tepat sekali (klaim baris 'pending' → 'processing' dulu). */
async function finalize(ctx: Ctx, row: PaymentRow): Promise<PaymentRow> {
  const claimed = await setStatus(ctx.admin, row.order_id, { status: 'processing' }, 'pending');
  if (!claimed) {
    // Sudah diproses oleh request lain.
    const { data } = await ctx.admin.from('qris_payments').select('*').eq('order_id', row.order_id).maybeSingle();
    return (data as PaymentRow | null) ?? row;
  }
  // Dipanggil dengan JWT kasir → auth.uid() = kasir, stok terpotong, invoice dibuat.
  const { data: tx, error } = await ctx.auth.supabase.rpc('create_transaction', {
    p_items: row.items,
    p_payment_method: 'qris',
    p_paid_amount: null,
    p_discount: 0,
  });
  if (error || !tx) {
    const message = `Pembayaran diterima, tetapi transaksi gagal dicatat: ${error?.message ?? 'respons kosong'}. Catat manual.`;
    return (await setStatus(ctx.admin, row.order_id, { status: 'failed', error: message })) ?? row;
  }
  const txId = (tx as { id: string }).id;
  return (await setStatus(ctx.admin, row.order_id, { status: 'paid', transaction_id: txId, error: null })) ?? row;
}

/** Sinkronkan status dengan Midtrans bila masih pending. */
async function sync(ctx: Ctx, row: PaymentRow): Promise<PaymentRow> {
  if (row.status !== 'pending') return row;
  const mt = await getStatus(row.order_id);
  switch (outcomeOf(mt.transaction_status)) {
    case 'paid':
      return finalize(ctx, row);
    case 'expired':
      return (await setStatus(ctx.admin, row.order_id, { status: 'expired' }, 'pending')) ?? row;
    case 'cancelled':
      return (await setStatus(ctx.admin, row.order_id, { status: 'cancelled' }, 'pending')) ?? row;
    default:
      return row;
  }
}

export async function POST(request: Request) {
  const ctx = await context(request);
  if ('error' in ctx) return ctx.error;

  let body: { items?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json(request, { error: 'Body harus JSON.' }, 400);
  }
  if (!Array.isArray(body.items) || body.items.length === 0 || body.items.length > 100) {
    return json(request, { error: 'Keranjang kosong atau terlalu banyak item.' }, 400);
  }

  const items: PaymentRow['items'] = [];
  for (const raw of body.items as Record<string, unknown>[]) {
    const id = typeof raw?.menu_item_id === 'string' ? raw.menu_item_id : '';
    const qty = Number(raw?.qty);
    if (!UUID_RE.test(id) || !Number.isInteger(qty) || qty <= 0 || qty > 999) {
      return json(request, { error: 'Item keranjang tidak valid.' }, 400);
    }
    const notes = typeof raw.notes === 'string' && raw.notes.trim() ? raw.notes.trim().slice(0, 200) : null;
    items.push({ menu_item_id: id, qty, notes });
  }

  // Harga dari database, sama seperti create_transaction.
  const ids = [...new Set(items.map((i) => i.menu_item_id))];
  const { data: menus, error: menuError } = await ctx.admin
    .from('menu_items')
    .select('id, name, price, is_active')
    .in('id', ids);
  if (menuError) return json(request, { error: menuError.message }, 500);
  const byId = new Map((menus ?? []).map((m) => [m.id as string, m]));
  let total = 0;
  for (const item of items) {
    const menu = byId.get(item.menu_item_id);
    if (!menu || !menu.is_active) return json(request, { error: 'Ada menu yang tidak ditemukan atau nonaktif.' }, 400);
    total += Number(menu.price) * item.qty;
  }
  if (total < 1 || !Number.isInteger(total)) {
    return json(request, { error: 'Total QRIS harus bilangan bulat Rupiah dan lebih dari 0.' }, 400);
  }

  const stamp = new Date().toISOString().replace(/\D/g, '').slice(2, 14); // YYMMDDHHmmss (UTC)
  const orderId = `POS-${stamp}-${crypto.randomUUID().slice(0, 8)}`;
  const { error: insertError } = await ctx.admin.from('qris_payments').insert({
    order_id: orderId,
    cashier_id: ctx.auth.user.id,
    items,
    gross_amount: total,
    status: 'pending',
  });
  if (insertError) {
    const hint = insertError.code === '42P01' ? ' Jalankan migrasi supabase/migrations/004_qris_payments.sql.' : '';
    return json(request, { error: `Gagal menyimpan pembayaran: ${insertError.message}.${hint}` }, 500);
  }

  try {
    const qr = await chargeQris(orderId, total, EXPIRY_MINUTES);
    const row = await setStatus(ctx.admin, orderId, {
      qr_string: qr.qrString,
      qr_url: qr.qrUrl,
      expires_at: new Date(Date.now() + EXPIRY_MINUTES * 60_000).toISOString(),
    });
    if (!row) return json(request, { error: 'Gagal memperbarui pembayaran.' }, 500);
    return json(request, await view(ctx.admin, row), 201);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    await setStatus(ctx.admin, orderId, { status: 'failed', error: message });
    return json(request, { error: `Gagal membuat QRIS: ${message}` }, 502);
  }
}

export async function GET(request: Request) {
  const ctx = await context(request);
  if ('error' in ctx) return ctx.error;
  const row = await loadOwn(ctx, request);
  if (row instanceof Response) return row;
  try {
    return json(request, await view(ctx.admin, await sync(ctx, row)));
  } catch (e) {
    return json(request, { error: `Gagal cek status: ${e instanceof Error ? e.message : e}` }, 502);
  }
}

export async function DELETE(request: Request) {
  const ctx = await context(request);
  if ('error' in ctx) return ctx.error;
  const row = await loadOwn(ctx, request);
  if (row instanceof Response) return row;
  if (row.status !== 'pending') return json(request, await view(ctx.admin, row));
  try {
    await cancelCharge(row.order_id);
    // Bisa saja pelanggan membayar tepat sebelum dibatalkan → jangan sampai uang masuk tanpa transaksi.
    const synced = await sync(ctx, row);
    const final =
      synced.status === 'pending'
        ? ((await setStatus(ctx.admin, row.order_id, { status: 'cancelled' }, 'pending')) ?? synced)
        : synced;
    return json(request, await view(ctx.admin, final));
  } catch (e) {
    return json(request, { error: `Gagal membatalkan: ${e instanceof Error ? e.message : e}` }, 502);
  }
}
