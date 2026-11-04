-- supabase/migrations/001_init.sql
-- Skema inti Coffee Shop POS & Smart Assistant.
-- Semua tanggal "bisnis" dihitung dalam zona waktu Asia/Jakarta (WIB, UTC+7).

create extension if not exists pgcrypto;

-- =====================================================================
-- TABEL
-- =====================================================================

create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  name        text,
  role        text not null default 'kasir' check (role in ('kasir', 'admin', 'owner')),
  created_at  timestamptz not null default now()
);

create table public.menu_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  integer not null default 0
);

create table public.menu_items (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid references public.menu_categories (id) on delete set null,
  name         text not null unique,
  price        numeric(12, 2) not null check (price >= 0),
  cost         numeric(12, 2) not null default 0 check (cost >= 0),
  image_url    text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create table public.ingredients (
  id             uuid primary key default gen_random_uuid(),
  name           text not null unique,
  unit           text not null,
  current_stock  numeric(12, 3) not null default 0,
  min_stock      numeric(12, 3) not null default 0 check (min_stock >= 0),
  cost_per_unit  numeric(12, 2) not null default 0 check (cost_per_unit >= 0)
);

create table public.recipes (
  id             uuid primary key default gen_random_uuid(),
  menu_item_id   uuid not null references public.menu_items (id) on delete cascade,
  ingredient_id  uuid not null references public.ingredients (id) on delete restrict,
  qty_needed     numeric(12, 3) not null check (qty_needed > 0),
  unique (menu_item_id, ingredient_id)
);

create sequence public.invoice_seq;

create table public.transactions (
  id              uuid primary key default gen_random_uuid(),
  invoice_no      text not null unique,
  cashier_id      uuid references public.profiles (id) on delete set null default auth.uid(),
  subtotal        numeric(12, 2) not null check (subtotal >= 0),
  discount        numeric(12, 2) not null default 0 check (discount >= 0),
  total           numeric(12, 2) not null check (total >= 0),
  payment_method  text not null check (payment_method in ('cash', 'qris', 'debit')),
  paid_amount     numeric(12, 2) not null check (paid_amount >= 0),
  change          numeric(12, 2) not null default 0 check (change >= 0),
  status          text not null default 'paid' check (status in ('paid', 'void')),
  created_at      timestamptz not null default now()
);

create table public.transaction_items (
  id              uuid primary key default gen_random_uuid(),
  transaction_id  uuid not null references public.transactions (id) on delete cascade,
  menu_item_id    uuid not null references public.menu_items (id) on delete restrict,
  qty             integer not null check (qty > 0),
  price           numeric(12, 2) not null check (price >= 0),
  subtotal        numeric(12, 2) not null check (subtotal >= 0),
  notes           text
);

create table public.stock_movements (
  id                  uuid primary key default gen_random_uuid(),
  ingredient_id       uuid not null references public.ingredients (id) on delete cascade,
  type                text not null check (type in ('in', 'out', 'waste')),
  qty                 numeric(12, 3) not null check (qty > 0),
  notes               text,
  ref_transaction_id  uuid references public.transactions (id) on delete set null,
  created_by          uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at          timestamptz not null default now()
);

create table public.expenses (
  id            uuid primary key default gen_random_uuid(),
  category      text not null,
  amount        numeric(12, 2) not null check (amount > 0),
  description   text,
  expense_date  date not null default ((now() at time zone 'Asia/Jakarta')::date),
  created_by    uuid references public.profiles (id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now()
);

create table public.chat_messages (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles (id) on delete cascade default auth.uid(),
  role             text not null check (role in ('user', 'assistant')),
  content          text not null,
  tool_calls_json  jsonb,
  created_at       timestamptz not null default now()
);

-- =====================================================================
-- INDEX
-- =====================================================================
create index transactions_created_at_idx      on public.transactions (created_at desc);
create index transactions_cashier_idx         on public.transactions (cashier_id, created_at desc);
create index transaction_items_tx_idx         on public.transaction_items (transaction_id);
create index transaction_items_menu_idx       on public.transaction_items (menu_item_id);
create index recipes_menu_idx                 on public.recipes (menu_item_id);
create index stock_movements_ingredient_idx   on public.stock_movements (ingredient_id, created_at desc);
create index expenses_date_idx                on public.expenses (expense_date desc);
create index chat_messages_user_idx           on public.chat_messages (user_id, created_at);
create index menu_items_category_idx          on public.menu_items (category_id);

-- =====================================================================
-- AUTO-CREATE PROFILE SAAT SIGNUP
-- Role selalu 'kasir' (metadata dari client diabaikan untuk mencegah eskalasi).
-- Owner/admin di-set manual via SQL atau halaman /users.
-- =====================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, role)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(coalesce(new.email, ''), '@', 1)),
    'kasir'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- NOMOR INVOICE: INV-YYYYMMDD-00001
-- =====================================================================
create or replace function public.next_invoice_no()
returns text
language sql
volatile
security definer
set search_path = public
as $$
  select 'INV-' || to_char(now() at time zone 'Asia/Jakarta', 'YYYYMMDD') || '-' ||
         lpad(nextval('public.invoice_seq')::text, 5, '0');
$$;

-- =====================================================================
-- RPC: create_transaction
-- Atomik: insert transaksi + item + auto-deduct stok via recipes + catat stock_movements.
-- Harga diambil dari menu_items di server (client tidak bisa memanipulasi harga).
-- p_items: [{ "menu_item_id": uuid, "qty": int, "notes": text|null }, ...]
-- Stok boleh minus (penjualan tidak diblokir), tapi akan muncul di peringatan stok.
-- =====================================================================
create or replace function public.create_transaction(
  p_items           jsonb,
  p_payment_method  text,
  p_paid_amount     numeric default null,
  p_discount        numeric default 0
)
returns public.transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_tx        public.transactions;
  v_item      jsonb;
  v_price     numeric(12, 2);
  v_qty       integer;
  v_subtotal  numeric(12, 2) := 0;
  v_discount  numeric(12, 2);
  v_total     numeric(12, 2);
  v_paid      numeric(12, 2);
  r           record;
begin
  if v_uid is null then
    raise exception 'Tidak terautentikasi' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'Profil pengguna tidak ditemukan' using errcode = '28000';
  end if;
  if p_payment_method is null or p_payment_method not in ('cash', 'qris', 'debit') then
    raise exception 'Metode pembayaran tidak valid: %', p_payment_method using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Keranjang kosong' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := nullif(v_item ->> 'qty', '')::integer;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Qty tidak valid' using errcode = '22023';
    end if;
    select m.price into v_price
    from public.menu_items m
    where m.id = (v_item ->> 'menu_item_id')::uuid and m.is_active;
    if not found then
      raise exception 'Menu tidak ditemukan atau nonaktif: %', v_item ->> 'menu_item_id' using errcode = '22023';
    end if;
    v_subtotal := v_subtotal + v_price * v_qty;
  end loop;

  v_discount := greatest(coalesce(p_discount, 0), 0);
  if v_discount > v_subtotal then
    raise exception 'Diskon melebihi subtotal' using errcode = '22023';
  end if;
  v_total := v_subtotal - v_discount;

  if p_payment_method = 'cash' then
    v_paid := coalesce(p_paid_amount, 0);
    if v_paid < v_total then
      raise exception 'Uang bayar kurang dari total' using errcode = '22023';
    end if;
  else
    v_paid := v_total;
  end if;

  insert into public.transactions
    (invoice_no, cashier_id, subtotal, discount, total, payment_method, paid_amount, change, status)
  values
    (public.next_invoice_no(), v_uid, v_subtotal, v_discount, v_total, p_payment_method, v_paid, v_paid - v_total, 'paid')
  returning * into v_tx;

  insert into public.transaction_items (transaction_id, menu_item_id, qty, price, subtotal, notes)
  select v_tx.id,
         m.id,
         (e.value ->> 'qty')::integer,
         m.price,
         m.price * (e.value ->> 'qty')::integer,
         nullif(trim(coalesce(e.value ->> 'notes', '')), '')
  from jsonb_array_elements(p_items) as e
  join public.menu_items m on m.id = (e.value ->> 'menu_item_id')::uuid;

  for r in
    select rc.ingredient_id, sum(rc.qty_needed * ti.qty) as qty
    from public.transaction_items ti
    join public.recipes rc on rc.menu_item_id = ti.menu_item_id
    where ti.transaction_id = v_tx.id
    group by rc.ingredient_id
  loop
    update public.ingredients
      set current_stock = current_stock - r.qty
      where id = r.ingredient_id;

    insert into public.stock_movements (ingredient_id, type, qty, notes, ref_transaction_id, created_by)
    values (r.ingredient_id, 'out', r.qty, 'Penjualan ' || v_tx.invoice_no, v_tx.id, v_uid);
  end loop;

  return v_tx;
end;
$$;

-- =====================================================================
-- RPC: adjust_stock — stok masuk ('in') atau terbuang ('waste').
-- Dipakai kasir (mobile) dan admin (web). Selalu tercatat di stock_movements.
-- =====================================================================
create or replace function public.adjust_stock(
  p_ingredient_id  uuid,
  p_type           text,
  p_qty            numeric,
  p_notes          text default null
)
returns public.ingredients
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_ing  public.ingredients;
begin
  if v_uid is null then
    raise exception 'Tidak terautentikasi' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles where id = v_uid) then
    raise exception 'Profil pengguna tidak ditemukan' using errcode = '28000';
  end if;
  if p_type not in ('in', 'waste') then
    raise exception 'Tipe penyesuaian harus in atau waste' using errcode = '22023';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Qty harus lebih dari 0' using errcode = '22023';
  end if;

  update public.ingredients
    set current_stock = current_stock + case when p_type = 'in' then p_qty else -p_qty end
    where id = p_ingredient_id
    returning * into v_ing;

  if not found then
    raise exception 'Bahan tidak ditemukan' using errcode = '22023';
  end if;

  insert into public.stock_movements (ingredient_id, type, qty, notes, created_by)
  values (p_ingredient_id, p_type, p_qty, nullif(trim(coalesce(p_notes, '')), ''), v_uid);

  return v_ing;
end;
$$;

-- =====================================================================
-- RPC LAPORAN (SECURITY INVOKER → RLS tetap berlaku:
-- kasir hanya melihat transaksinya sendiri, admin/owner melihat semua).
-- p_start / p_end = tanggal lokal WIB (inklusif).
-- =====================================================================
create or replace function public.revenue_by_day(p_start date, p_end date)
returns table (day date, revenue numeric, tx_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select d.day,
         coalesce(sum(t.total), 0)::numeric as revenue,
         count(t.id)::bigint as tx_count
  from (
    select gs::date as day
    from generate_series(p_start::timestamp, p_end::timestamp, interval '1 day') as gs
  ) d
  left join public.transactions t
    on t.status = 'paid'
   and t.created_at >= (d.day::timestamp at time zone 'Asia/Jakarta')
   and t.created_at <  ((d.day + 1)::timestamp at time zone 'Asia/Jakarta')
  group by d.day
  order by d.day;
$$;

create or replace function public.menu_performance(p_start date, p_end date)
returns table (
  menu_item_id  uuid,
  name          text,
  category      text,
  is_active     boolean,
  qty_sold      bigint,
  revenue       numeric
)
language sql
stable
security invoker
set search_path = public
as $$
  with sold as (
    select ti.menu_item_id,
           sum(ti.qty)::bigint as qty,
           sum(ti.subtotal)::numeric as rev
    from public.transaction_items ti
    join public.transactions t on t.id = ti.transaction_id
    where t.status = 'paid'
      and t.created_at >= (p_start::timestamp at time zone 'Asia/Jakarta')
      and t.created_at <  ((p_end + 1)::timestamp at time zone 'Asia/Jakarta')
    group by ti.menu_item_id
  )
  select m.id,
         m.name,
         coalesce(c.name, 'Tanpa Kategori'),
         m.is_active,
         coalesce(s.qty, 0)::bigint,
         coalesce(s.rev, 0)::numeric
  from public.menu_items m
  left join public.menu_categories c on c.id = m.category_id
  left join sold s on s.menu_item_id = m.id
  where m.is_active or s.qty is not null
  order by 5 desc, 2 asc;
$$;

-- =====================================================================
-- HAK EKSEKUSI FUNGSI
-- =====================================================================
revoke execute on function public.create_transaction(jsonb, text, numeric, numeric) from public, anon;
revoke execute on function public.adjust_stock(uuid, text, numeric, text) from public, anon;
revoke execute on function public.revenue_by_day(date, date) from public, anon;
revoke execute on function public.menu_performance(date, date) from public, anon;
revoke execute on function public.next_invoice_no() from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

grant execute on function public.create_transaction(jsonb, text, numeric, numeric) to authenticated;
grant execute on function public.adjust_stock(uuid, text, numeric, text) to authenticated;
grant execute on function public.revenue_by_day(date, date) to authenticated, service_role;
grant execute on function public.menu_performance(date, date) to authenticated, service_role;
grant usage on sequence public.invoice_seq to authenticated, service_role;
