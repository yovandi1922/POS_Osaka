// apps/api/lib/supabase/admin.ts
// Supabase client dengan SERVICE ROLE — HANYA untuk kode server (route handler).
// Bypass RLS, jadi setiap pemakaian wajib didahului cek autentikasi + role di kode pemanggil.
import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let cached: SupabaseClient | null = null;

export function createAdminClient(): SupabaseClient | null {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  if (!cached) {
    cached = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
  }
  return cached;
}
