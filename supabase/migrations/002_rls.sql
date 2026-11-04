-- supabase/migrations/002_rls.sql
-- Row Level Security untuk semua tabel. Tidak ada tabel tanpa policy.
-- Idempoten: aman dijalankan ulang (policy lama di-drop lalu dibuat ulang).

-- =====================================================================
-- HELPER ROLE (SECURITY DEFINER → tidak memicu rekursi RLS pada profiles)
-- =====================================================================
create or replace function public.get_my_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.get_my_role() in ('admin', 'owner'), false);
$$;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.get_my_role() = 'owner', false);
$$;

revoke execute on function public.get_my_role() from public, anon;
revoke execute on function public.is_admin() from public, anon;
revoke execute on function public.is_owner() from public, anon;
grant execute on function public.get_my_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_owner() to authenticated;

-- =====================================================================
-- ENABLE RLS
-- =====================================================================
alter table public.profiles           enable row level security;
alter table public.menu_categories    enable row level security;
alter table public.menu_items         enable row level security;
alter table public.ingredients        enable row level security;
alter table public.recipes            enable row level security;
alter table public.transactions       enable row level security;
alter table public.transaction_items  enable row level security;
alter table public.stock_movements    enable row level security;
alter table public.expenses           enable row level security;
alter table public.chat_messages      enable row level security;

-- =====================================================================
-- PROFILES
-- Insert dilakukan trigger handle_new_user (security definer).
-- Hanya owner yang boleh mengubah profil (termasuk role) agar tidak ada eskalasi.
-- =====================================================================
drop policy if exists "profiles: baca milik sendiri" on public.profiles;
create policy "profiles: baca milik sendiri"
  on public.profiles for select to authenticated
  using (id = auth.uid());

drop policy if exists "profiles: admin/owner baca semua" on public.profiles;
create policy "profiles: admin/owner baca semua"
  on public.profiles for select to authenticated
  using (public.is_admin());

drop policy if exists "profiles: owner update" on public.profiles;
create policy "profiles: owner update"
  on public.profiles for update to authenticated
  using (public.is_owner())
  with check (public.is_owner());

-- =====================================================================
-- MENU CATEGORIES / MENU ITEMS / INGREDIENTS / RECIPES
-- Read: semua user login. Write: admin/owner.
-- =====================================================================
drop policy if exists "menu_categories: read authed" on public.menu_categories;
create policy "menu_categories: read authed"
  on public.menu_categories for select to authenticated using (true);
drop policy if exists "menu_categories: admin insert" on public.menu_categories;
create policy "menu_categories: admin insert"
  on public.menu_categories for insert to authenticated with check (public.is_admin());
drop policy if exists "menu_categories: admin update" on public.menu_categories;
create policy "menu_categories: admin update"
  on public.menu_categories for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "menu_categories: admin delete" on public.menu_categories;
create policy "menu_categories: admin delete"
  on public.menu_categories for delete to authenticated using (public.is_admin());

drop policy if exists "menu_items: read authed" on public.menu_items;
create policy "menu_items: read authed"
  on public.menu_items for select to authenticated using (true);
drop policy if exists "menu_items: admin insert" on public.menu_items;
create policy "menu_items: admin insert"
  on public.menu_items for insert to authenticated with check (public.is_admin());
drop policy if exists "menu_items: admin update" on public.menu_items;
create policy "menu_items: admin update"
  on public.menu_items for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "menu_items: admin delete" on public.menu_items;
create policy "menu_items: admin delete"
  on public.menu_items for delete to authenticated using (public.is_admin());

drop policy if exists "ingredients: read authed" on public.ingredients;
create policy "ingredients: read authed"
  on public.ingredients for select to authenticated using (true);
drop policy if exists "ingredients: admin insert" on public.ingredients;
create policy "ingredients: admin insert"
  on public.ingredients for insert to authenticated with check (public.is_admin());
drop policy if exists "ingredients: admin update" on public.ingredients;
create policy "ingredients: admin update"
  on public.ingredients for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "ingredients: admin delete" on public.ingredients;
create policy "ingredients: admin delete"
  on public.ingredients for delete to authenticated using (public.is_admin());

drop policy if exists "recipes: read authed" on public.recipes;
create policy "recipes: read authed"
  on public.recipes for select to authenticated using (true);
drop policy if exists "recipes: admin insert" on public.recipes;
create policy "recipes: admin insert"
  on public.recipes for insert to authenticated with check (public.is_admin());
drop policy if exists "recipes: admin update" on public.recipes;
create policy "recipes: admin update"
  on public.recipes for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "recipes: admin delete" on public.recipes;
create policy "recipes: admin delete"
  on public.recipes for delete to authenticated using (public.is_admin());

-- =====================================================================
-- TRANSACTIONS & TRANSACTION ITEMS
-- Kasir: insert & baca miliknya. Admin/owner: baca semua, update (mis. void).
-- (Checkout normal memakai RPC create_transaction yang atomik.)
-- =====================================================================
drop policy if exists "transactions: kasir insert milik sendiri" on public.transactions;
create policy "transactions: kasir insert milik sendiri"
  on public.transactions for insert to authenticated
  with check (cashier_id = auth.uid());

drop policy if exists "transactions: baca milik sendiri atau admin" on public.transactions;
create policy "transactions: baca milik sendiri atau admin"
  on public.transactions for select to authenticated
  using (cashier_id = auth.uid() or public.is_admin());

drop policy if exists "transactions: admin update" on public.transactions;
create policy "transactions: admin update"
  on public.transactions for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "transaction_items: insert untuk transaksi sendiri" on public.transaction_items;
create policy "transaction_items: insert untuk transaksi sendiri"
  on public.transaction_items for insert to authenticated
  with check (
    exists (
      select 1 from public.transactions t
      where t.id = transaction_id and t.cashier_id = auth.uid()
    )
  );

drop policy if exists "transaction_items: baca sesuai transaksi" on public.transaction_items;
create policy "transaction_items: baca sesuai transaksi"
  on public.transaction_items for select to authenticated
  using (
    exists (
      select 1 from public.transactions t
      where t.id = transaction_id
        and (t.cashier_id = auth.uid() or public.is_admin())
    )
  );

-- =====================================================================
-- STOCK MOVEMENTS
-- Read: semua user login. Insert langsung: admin/owner (staff via RPC adjust_stock).
-- =====================================================================
drop policy if exists "stock_movements: read authed" on public.stock_movements;
create policy "stock_movements: read authed"
  on public.stock_movements for select to authenticated using (true);
drop policy if exists "stock_movements: admin insert" on public.stock_movements;
create policy "stock_movements: admin insert"
  on public.stock_movements for insert to authenticated
  with check (public.is_admin());

-- =====================================================================
-- EXPENSES
-- Read: admin/owner. Insert: semua user login (atas nama sendiri). Update/delete: admin/owner.
-- =====================================================================
drop policy if exists "expenses: admin read" on public.expenses;
create policy "expenses: admin read"
  on public.expenses for select to authenticated using (public.is_admin());
drop policy if exists "expenses: authed insert" on public.expenses;
create policy "expenses: authed insert"
  on public.expenses for insert to authenticated
  with check (created_by = auth.uid());
drop policy if exists "expenses: admin update" on public.expenses;
create policy "expenses: admin update"
  on public.expenses for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "expenses: admin delete" on public.expenses;
create policy "expenses: admin delete"
  on public.expenses for delete to authenticated using (public.is_admin());

-- =====================================================================
-- CHAT MESSAGES — hanya milik sendiri
-- =====================================================================
drop policy if exists "chat_messages: baca milik sendiri" on public.chat_messages;
create policy "chat_messages: baca milik sendiri"
  on public.chat_messages for select to authenticated using (user_id = auth.uid());
drop policy if exists "chat_messages: insert milik sendiri" on public.chat_messages;
create policy "chat_messages: insert milik sendiri"
  on public.chat_messages for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "chat_messages: hapus milik sendiri" on public.chat_messages;
create policy "chat_messages: hapus milik sendiri"
  on public.chat_messages for delete to authenticated using (user_id = auth.uid());
