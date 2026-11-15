-- supabase/migrations/004_qris_payments.sql
-- Pembayaran QRIS dinamis via Midtrans (Core API).
--
-- Alur: kasir minta QR → API (service role) insert baris 'pending' + charge ke Midtrans →
-- app polling status → saat Midtrans 'settlement', API memanggil create_transaction SEBAGAI kasir
-- (stok terpotong, invoice dibuat) lalu menandai baris 'paid' + transaction_id.
-- Transaksi QRIS hanya tercipta setelah uang benar-benar masuk.
--
-- Aman dijalankan ulang (idempoten). Jalankan via `supabase db push` atau paste ke SQL Editor.

create table if not exists public.qris_payments (
  order_id        text primary key,
  cashier_id      uuid not null references public.profiles (id) on delete cascade,
  items           jsonb not null,
  gross_amount    numeric(12, 2) not null check (gross_amount > 0),
  status          text not null default 'pending'
                  check (status in ('pending', 'processing', 'paid', 'expired', 'cancelled', 'failed')),
  qr_string       text,
  qr_url          text,
  expires_at      timestamptz,
  transaction_id  uuid references public.transactions (id) on delete set null,
  error           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists qris_payments_cashier_idx on public.qris_payments (cashier_id, created_at desc);
create index if not exists qris_payments_status_idx  on public.qris_payments (status, created_at desc);

alter table public.qris_payments enable row level security;

-- Baca: kasir miliknya sendiri, admin/owner semua.
-- Tulis: TIDAK ada policy untuk authenticated → hanya service role (apps/api) yang bisa insert/update.
drop policy if exists "qris_payments: baca milik sendiri atau admin" on public.qris_payments;
create policy "qris_payments: baca milik sendiri atau admin"
  on public.qris_payments for select to authenticated
  using (cashier_id = auth.uid() or public.is_admin());
