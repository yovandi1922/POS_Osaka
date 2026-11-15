# Coffee Shop POS & Smart Assistant ☕

Sistem POS untuk coffee shop kecil–menengah. Aplikasi kasir dan web admin ditulis dengan **Dart (Flutter)**,
backend AI dengan Next.js, database Supabase.

| Bagian | Untuk | Stack |
|---|---|---|
| `apps/mobile` | Kasir/staff: transaksi, stok masuk, catat biaya, laporan, chat AI | Flutter (Dart) · Android/iOS · Provider |
| `apps/admin` | Owner/admin: dashboard, laporan, CRUD, prediksi, pengguna, chat AI | Flutter Web (Dart) · go_router · fl_chart |
| `packages/coffee_core` | Kode Dart bersama: model, format Rupiah/WIB, repository Supabase, prediksi, klien API | Dart |
| `apps/api` | Backend: asisten AI "Kopi" (`/api/chat`), buat user (`/api/users`), `/api/health` | Next.js 14 Route Handlers · Anthropic SDK |
| `supabase/` | Database, Auth, RLS, fungsi bisnis | PostgreSQL (Supabase) |

```
.
├── package.json · pnpm-workspace.yaml · .env.example
├── supabase/
│   ├── config.toml
│   ├── migrations/001_init.sql      # tabel, index, trigger, RPC bisnis
│   ├── migrations/002_rls.sql       # RLS semua tabel
│   ├── migrations/003_seed.sql      # 3 kategori, 8 menu, 8 bahan, 20 resep
│   └── seed_demo_history.sql        # OPSIONAL: 45 hari transaksi demo
├── packages/coffee_core/            # Dart: models, format, predict, repository, chat_api (+ unit test)
├── apps/mobile/                     # Flutter: lib/screens (login, home, pos, checkout, stock, expense, report, chat)
├── apps/admin/                      # Flutter Web: lib/pages (dashboard, chat, transaksi, menu, stok, ...)
└── apps/api/                        # Next.js: app/api/{chat,users,health}, lib/ai/{system-prompt,tools}.ts, lib/predict.ts
```

> **Kenapa chatbot tetap di Next.js?** Anthropic tidak menyediakan SDK resmi untuk Dart, dan API key + service role
> Supabase harus tetap di server. Kedua app Flutter memanggil `POST {API_BASE_URL}/api/chat` dengan
> `Authorization: Bearer <access token Supabase>`.

---

## Arsitektur singkat

- **Checkout atomik** — kasir memanggil RPC `create_transaction(p_items, p_payment_method, p_paid_amount, p_discount)`.
  Dalam satu transaksi database: harga diambil dari `menu_items` (tidak bisa dimanipulasi dari HP), insert
  `transactions` + `transaction_items`, potong `ingredients.current_stock` sesuai `recipes`, dan catat tiap potongan ke
  `stock_movements` (type `out`, `ref_transaction_id` terisi).
- **Stok masuk / terbuang** — RPC `adjust_stock(p_ingredient_id, 'in'|'waste', p_qty, p_notes)`.
- **Laporan** — RPC `revenue_by_day(p_start, p_end)` dan `menu_performance(p_start, p_end)` dalam zona **Asia/Jakarta (WIB)**,
  `SECURITY INVOKER` sehingga RLS tetap berlaku (kasir hanya melihat transaksinya sendiri).
- **Role** — `kasir` (default saat signup), `admin`, `owner`. Web admin menolak akun kasir.
- **Chatbot** — loop maksimal 6 langkah tool use (`get_stock`, `get_low_stock_items`, `get_menu_performance`, `get_revenue`,
  `get_expenses`, `predict_revenue`). Tool keuangan ditolak untuk kasir. Riwayat disimpan di `chat_messages`.
- **Prediksi** — weighted moving average 7 hari (bobot linear 1..N) × faktor hari-dalam-seminggu, rentang 85%–115%,
  error informatif bila data < 3 hari, flag `low_accuracy` bila < 7 hari. Algoritma identik di
  `packages/coffee_core/lib/src/predict.dart` (halaman Prediksi) dan `apps/api/lib/predict.ts` (tool AI).

### Ringkasan RLS

| Tabel | Read | Write |
|---|---|---|
| profiles | milik sendiri; admin/owner semua | update: owner saja · insert via trigger |
| menu_categories, menu_items, ingredients, recipes | semua user login | admin/owner |
| transactions, transaction_items | kasir: miliknya · admin/owner: semua | insert: kasir untuk dirinya · update: admin/owner |
| stock_movements | semua user login | admin/owner (staff via RPC `adjust_stock`) |
| expenses | admin/owner | insert: semua user login · update/delete: admin/owner |
| chat_messages | milik sendiri | milik sendiri |

---

## 1. Prasyarat

- **Flutter SDK 3.38+** (diuji dengan 3.47.7 / Dart 3.13) — <https://docs.flutter.dev/get-started/install>
  - Android: Android Studio + Android SDK · iOS: macOS + Xcode · Web admin: Chrome
- Node.js ≥ 20 + pnpm 9 (`npm i -g pnpm@9`, atau tanpa install: `npx pnpm@9.15.9 ...`) — untuk `apps/api`
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- Akun Supabase, Anthropic (API key), Vercel

> Windows: pasang Flutter di path pendek (mis. `C:\src\flutter`). Path SDK yang sangat panjang memicu error
> "filename or extension is too long" / batas 260 karakter.

## 2. Setup Supabase

```bash
supabase login
supabase link --project-ref <PROJECT_REF>
supabase db push                 # menjalankan 001_init, 002_rls, 003_seed
```

Di dashboard: **Authentication → Providers → Email** aktif. Untuk akun staff, buat user dengan *Auto Confirm User*.
Ambil kredensial di **Project Settings → API**: Project URL, anon/publishable key, service_role key.

### Membuat akun owner pertama

1. **Authentication → Users → Add user → Create new user** (centang *Auto Confirm User*).
   Trigger `handle_new_user()` otomatis membuat baris `profiles` dengan role `kasir`.
2. **SQL Editor**:

   ```sql
   update public.profiles
   set role = 'owner', name = 'Nama Owner'
   where email = 'owner@coffeeshop.id';

   select email, name, role from public.profiles order by created_at;
   ```

3. Akun kasir/admin berikutnya bisa dibuat dari web admin: **Pengguna → Tambah pengguna** (khusus owner).

### (Opsional) Data demo 45 hari

Paste isi `supabase/seed_demo_history.sql` ke **SQL Editor** lalu **Run** (butuh 1 user owner). Jangan di database produksi.

## 3. Konfigurasi

**Backend API** — `apps/api/.env.local` (salin dari `apps/api/.env.example`):

| Variabel | Keterangan |
|---|---|
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | dari Project Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | **rahasia**, untuk tools AI & pembuatan user |
| `ANTHROPIC_API_KEY` | API key Anthropic |
| `ANTHROPIC_MODEL` | opsional, default `claude-sonnet-4-5` |
| `CORS_ALLOWED_ORIGINS` | origin web admin, mis. `https://coffee-admin.vercel.app` (default `*`) |
| `MIDTRANS_SERVER_KEY` | **rahasia**, server key Midtrans untuk QRIS dinamis (`SB-Mid-server-…` untuk sandbox) |
| `MIDTRANS_IS_PRODUCTION` | `false` (sandbox, default) atau `true` dengan server key produksi |

**Flutter** — salin `env.example.json` → `env.json` di `apps/mobile` **dan** `apps/admin`:

```json
{
  "SUPABASE_URL": "https://YOUR-PROJECT-REF.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-public-key",
  "API_BASE_URL": "https://your-api.vercel.app"
}
```

`API_BASE_URL` tanpa `/api` di belakang. Saat dev: web admin → `http://localhost:3000`; emulator Android →
`http://10.0.2.2:3000`; HP fisik → `http://<IP-LAN-PC>:3000` (HP & PC satu Wi-Fi, izinkan port 3000 di firewall).

## 4. Menjalankan secara lokal

```bash
# Backend API (port 3000)
pnpm install
pnpm dev:api

# Web admin (Chrome)
cd apps/admin
flutter pub get
flutter run -d chrome --dart-define-from-file=env.json

# Aplikasi kasir (HP/emulator terhubung)
cd apps/mobile
flutter pub get
flutter run --dart-define-from-file=env.json
```

Cek kualitas:

```bash
cd packages/coffee_core && dart pub get && dart analyze && dart test
cd apps/mobile && dart analyze && flutter test       # unit + smoke test semua tab
cd apps/admin  && dart analyze && flutter test       # smoke test 9 halaman × desktop & ponsel
pnpm typecheck && pnpm build:api
```

### QRIS dinamis (Midtrans)

Kasir memilih **QRIS → Tampilkan QRIS**. API membuat QR lewat Midtrans Core API (`POST /api/payments/qris`, harga
dihitung server), app mengecek status tiap 3 detik (`GET /api/payments/qris?order_id=…`), dan begitu Midtrans
menyatakan lunas, **server** memanggil `create_transaction` sebagai kasir tersebut (invoice dibuat, stok terpotong)
tepat satu kali. Belum perlu webhook, jadi bisa dites di lokal. Opsi "Catat manual" tetap ada untuk QRIS statis.

1. Jalankan migrasi `supabase/migrations/004_qris_payments.sql` (`supabase db push` atau paste ke SQL Editor).
2. Daftar di <https://dashboard.sandbox.midtrans.com> → **Settings → Access Keys** → salin *Server Key* ke
   `MIDTRANS_SERVER_KEY` di `apps/api/.env.local`, restart API, cek `/api/health` → `MIDTRANS_SERVER_KEY: true`.
3. Uji bayar sandbox: QR sandbox tidak bisa di-scan e-wallet asli. Di layar QR tekan **Salin URL QR**, buka
   <https://simulator.sandbox.midtrans.com/v2/qris/index>, tempel URL, klik **Pay** → app otomatis menampilkan sukses.

Produksi: aktifkan QRIS di akun Midtrans produksi, ganti server key, set `MIDTRANS_IS_PRODUCTION=true`.

## 5. Deploy

### Backend API → Vercel

1. Vercel → **Add New Project** → import repo → **Root Directory: `apps/api`**.
2. Environment Variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `ANTHROPIC_API_KEY`,
   `CORS_ALLOWED_ORIGINS` (isi dengan URL web admin setelah langkah berikut).
3. Deploy, lalu cek `https://<api>.vercel.app/api/health` — semua nilai `env` harus `true`.
   `apps/api/vercel.json` menetapkan region `sin1` dan `maxDuration` 60 detik untuk `/api/chat`.

### Web admin → Vercel (static)

Vercel tidak punya Flutter bawaan, jadi build di lokal/CI lalu upload hasilnya:

```bash
cd apps/admin
flutter build web --release --dart-define-from-file=env.json
npx vercel deploy build/web --prod          # atau Firebase Hosting / Netlify / Cloudflare Pages
```

Routing memakai hash URL (`/#/dashboard`), jadi tidak perlu aturan rewrite di hosting.
Tambahkan domain ini ke `CORS_ALLOWED_ORIGINS` di project API.

### Aplikasi kasir → Android / iOS

```bash
cd apps/mobile
flutter build apk --release --dart-define-from-file=env.json          # APK untuk dipasang langsung di HP kasir
flutter build appbundle --release --dart-define-from-file=env.json    # AAB untuk Google Play
flutter build ipa --release --dart-define-from-file=env.json          # iOS (macOS + Xcode)
```

Sebelum rilis ke store: ganti `applicationId` di `android/app/build.gradle.kts` dan bundle identifier di Xcode
(saat ini `id.coffeepos.coffee_pos_mobile`), lalu konfigurasi signing
(<https://docs.flutter.dev/deployment/android#signing-the-app>). Build cloud bisa memakai Codemagic atau GitHub Actions.

## 6. Contoh pertanyaan untuk "Kopi"

1. "Berapa omset hari ini dan berapa transaksinya?" → `get_revenue(days=1)`
2. "Bahan apa saja yang stoknya menipis? Perlu restock berapa?" → `get_low_stock_items`
3. "Menu apa yang paling laku dan paling jarang laku minggu ini?" → `get_menu_performance(days=7)`
4. "Berapa laba kotor 30 hari terakhir, dan pengeluaran terbesar di kategori apa?" → `get_revenue(30)` + `get_expenses(30)`
5. "Prediksi omset 7 hari ke depan dong" → `predict_revenue(days_ahead=7)` (selalu dengan disclaimer & rentang)

Pertanyaan di luar coffee shop ditolak dengan sopan; kasir yang menanyakan data keuangan diberi tahu itu khusus admin/owner.

## Troubleshooting

| Gejala | Solusi |
|---|---|
| App menampilkan "Konfigurasi belum lengkap" | Jalankan dengan `--dart-define-from-file=env.json` dan pastikan `env.json` terisi. |
| Login web admin ditolak "tidak memiliki akses" | Role akun masih `kasir`. Jalankan SQL `update profiles set role='owner' ...`. |
| Chat: "Tidak dapat terhubung ke server" | `API_BASE_URL` harus bisa diakses dari perangkat (bukan `localhost` di HP fisik). |
| Chat web admin gagal karena CORS | Tambahkan origin web admin ke `CORS_ALLOWED_ORIGINS` di API lalu redeploy. |
| Chat: "Konfigurasi ANTHROPIC_API_KEY … tidak valid" | Cek env API, lalu redeploy. Cek `/api/health`. |
| Menu terjual tapi stok tidak berkurang | Menu belum punya resep. Web admin → Menu → ikon resep → tambah bahan. |
| APK release tidak bisa konek internet | Pastikan `<uses-permission android:name="android.permission.INTERNET"/>` ada di `android/app/src/main/AndroidManifest.xml` (sudah ditambahkan). |
