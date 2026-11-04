-- supabase/migrations/003_seed.sql
-- Data awal: 3 kategori, 8 menu, 8 bahan, 20 baris resep. Idempoten (aman dijalankan ulang).

-- ---------------------------------------------------------------------
-- Kategori
-- ---------------------------------------------------------------------
insert into public.menu_categories (name, sort_order) values
  ('Coffee', 1),
  ('Non-Coffee', 2),
  ('Snack', 3)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------
insert into public.menu_items (category_id, name, price, cost, is_active)
select c.id, v.name, v.price, v.cost, true
from (values
  ('Coffee',     'Espresso',             15000, 5000),
  ('Coffee',     'Americano',            18000, 5500),
  ('Coffee',     'Cappuccino',           25000, 8500),
  ('Coffee',     'Kopi Susu Gula Aren',  22000, 8000),
  ('Non-Coffee', 'Matcha Latte',         28000, 10000),
  ('Non-Coffee', 'Chocolate',            25000, 9000),
  ('Snack',      'Roti Bakar Coklat',    20000, 6000),
  ('Snack',      'Croissant',            22000, 10000)
) as v(category, name, price, cost)
join public.menu_categories c on c.name = v.category
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- Bahan baku (Bubuk Matcha sengaja di bawah minimum untuk demo peringatan stok)
-- ---------------------------------------------------------------------
insert into public.ingredients (name, unit, current_stock, min_stock, cost_per_unit) values
  ('Biji Kopi Arabika', 'gram',   2000,  500,  250),
  ('Susu UHT',          'ml',     10000, 2000, 18),
  ('Gula Aren Cair',    'ml',     2000,  500,  40),
  ('Bubuk Matcha',      'gram',   80,    100,  600),
  ('Bubuk Coklat',      'gram',   1000,  200,  150),
  ('Roti Tawar',        'lembar', 40,    10,   1500),
  ('Croissant Frozen',  'pcs',    20,    5,    9000),
  ('Cup Plastik 16oz',  'pcs',    300,   50,   1200)
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- Resep (qty_needed per 1 porsi)
-- ---------------------------------------------------------------------
insert into public.recipes (menu_item_id, ingredient_id, qty_needed)
select m.id, i.id, v.qty
from (values
  ('Espresso',            'Biji Kopi Arabika', 18),
  ('Espresso',            'Cup Plastik 16oz',  1),
  ('Americano',           'Biji Kopi Arabika', 18),
  ('Americano',           'Cup Plastik 16oz',  1),
  ('Cappuccino',          'Biji Kopi Arabika', 18),
  ('Cappuccino',          'Susu UHT',          150),
  ('Cappuccino',          'Cup Plastik 16oz',  1),
  ('Kopi Susu Gula Aren', 'Biji Kopi Arabika', 18),
  ('Kopi Susu Gula Aren', 'Susu UHT',          150),
  ('Kopi Susu Gula Aren', 'Gula Aren Cair',    30),
  ('Kopi Susu Gula Aren', 'Cup Plastik 16oz',  1),
  ('Matcha Latte',        'Bubuk Matcha',      5),
  ('Matcha Latte',        'Susu UHT',          200),
  ('Matcha Latte',        'Cup Plastik 16oz',  1),
  ('Chocolate',           'Bubuk Coklat',      30),
  ('Chocolate',           'Susu UHT',          200),
  ('Chocolate',           'Cup Plastik 16oz',  1),
  ('Roti Bakar Coklat',   'Roti Tawar',        2),
  ('Roti Bakar Coklat',   'Bubuk Coklat',      15),
  ('Croissant',           'Croissant Frozen',  1)
) as v(menu, ingredient, qty)
join public.menu_items  m on m.name = v.menu
join public.ingredients i on i.name = v.ingredient
on conflict (menu_item_id, ingredient_id) do nothing;
