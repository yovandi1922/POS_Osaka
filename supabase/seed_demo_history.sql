-- supabase/seed_demo_history.sql
-- OPSIONAL — data transaksi & pengeluaran historis 45 hari untuk mencoba dashboard,
-- laporan, prediksi, dan chatbot. JANGAN jalankan di database produksi yang sudah berisi data asli.
--
-- Prasyarat: sudah ada minimal 1 user dengan role 'owner' (lihat README).
-- Cara pakai: buka Supabase Dashboard → SQL Editor → paste file ini → Run.
-- Catatan: data demo ini TIDAK memotong stok (stok di-seed apa adanya).

do $$
declare
  v_owner     uuid;
  v_day       date;
  v_tx_count  integer;
  v_tx_id     uuid;
  v_ts        timestamptz;
  v_subtotal  numeric(12, 2);
  v_lines     integer;
  v_menu      record;
  v_qty       integer;
  v_method    text;
  v_paid      numeric(12, 2);
  i           integer;
  j           integer;
begin
  select id into v_owner from public.profiles where role = 'owner' order by created_at limit 1;
  if v_owner is null then
    raise exception 'Belum ada user owner. Buat user dan set role owner terlebih dahulu.';
  end if;

  for v_day in
    select gs::date from generate_series(
      ((now() at time zone 'Asia/Jakarta')::date - 45)::timestamp,
      ((now() at time zone 'Asia/Jakarta')::date - 1)::timestamp,
      interval '1 day'
    ) gs
  loop
    -- Akhir pekan lebih ramai
    v_tx_count := 18 + floor(random() * 12)::int
                  + case when extract(isodow from v_day) in (6, 7) then 12 else 0 end;

    for i in 1..v_tx_count loop
      v_ts := (v_day::timestamp + make_interval(hours => 8 + floor(random() * 13)::int,
                                                mins  => floor(random() * 60)::int))
              at time zone 'Asia/Jakarta';
      v_method := (array['cash', 'qris', 'qris', 'debit'])[1 + floor(random() * 4)::int];
      v_tx_id := null;

      insert into public.transactions
        (invoice_no, cashier_id, subtotal, discount, total, payment_method, paid_amount, change, status, created_at)
      values
        ('DEMO-' || to_char(v_day, 'YYYYMMDD') || '-' || lpad(i::text, 4, '0'),
         v_owner, 0, 0, 0, v_method, 0, 0, 'paid', v_ts)
      on conflict (invoice_no) do nothing
      returning id into v_tx_id;

      if v_tx_id is null then
        continue;
      end if;

      v_subtotal := 0;
      v_lines := 1 + floor(random() * 3)::int;
      for j in 1..v_lines loop
        -- Bobot popularitas: Kopi Susu Gula Aren & Americano paling laku, Espresso paling jarang
        select m.id, m.price into v_menu
        from public.menu_items m
        cross join lateral (
          select case m.name
                   when 'Kopi Susu Gula Aren' then 6
                   when 'Americano'           then 4
                   when 'Cappuccino'          then 3
                   when 'Matcha Latte'        then 3
                   when 'Croissant'           then 2
                   when 'Chocolate'           then 2
                   when 'Roti Bakar Coklat'   then 2
                   else 1
                 end as w
        ) wt
        where m.is_active
        order by random() / wt.w
        limit 1;

        v_qty := 1 + floor(random() * 2)::int;
        insert into public.transaction_items (transaction_id, menu_item_id, qty, price, subtotal)
        values (v_tx_id, v_menu.id, v_qty, v_menu.price, v_menu.price * v_qty);
        v_subtotal := v_subtotal + v_menu.price * v_qty;
      end loop;

      v_paid := case when v_method = 'cash' then ceil(v_subtotal / 50000.0) * 50000 else v_subtotal end;
      update public.transactions
        set subtotal = v_subtotal, total = v_subtotal, paid_amount = v_paid, change = v_paid - v_subtotal
        where id = v_tx_id;
    end loop;

    -- Pengeluaran harian kecil + bahan baku tiap 3 hari
    insert into public.expenses (category, amount, description, expense_date, created_by)
    values ('Operasional', 50000 + floor(random() * 50000)::int, 'Es batu, gas, kebersihan', v_day, v_owner);
    if extract(day from v_day)::int % 3 = 0 then
      insert into public.expenses (category, amount, description, expense_date, created_by)
      values ('Bahan Baku', 600000 + floor(random() * 400000)::int, 'Belanja kopi & susu', v_day, v_owner);
    end if;
  end loop;

  -- Pengeluaran bulanan
  insert into public.expenses (category, amount, description, expense_date, created_by) values
    ('Sewa',          4500000, 'Sewa tempat bulanan',  (now() at time zone 'Asia/Jakarta')::date - 30, v_owner),
    ('Gaji',          6000000, 'Gaji 2 barista',       (now() at time zone 'Asia/Jakarta')::date - 28, v_owner),
    ('Listrik & Air', 850000,  'Tagihan PLN & PDAM',   (now() at time zone 'Asia/Jakarta')::date - 25, v_owner);
end;
$$;
