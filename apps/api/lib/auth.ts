// apps/api/lib/auth.ts
// Autentikasi Route Handler via header `Authorization: Bearer <access_token>` Supabase.
// Dipakai oleh app Flutter mobile (kasir) dan Flutter Web admin.
import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';
import type { Profile } from './types';

export interface AuthedRequest {
  /** Client yang bertindak sebagai user (RLS berlaku). */
  supabase: SupabaseClient;
  user: User;
  profile: Profile;
}

export async function authenticateRequest(request: Request): Promise<AuthedRequest | null> {
  const header = request.headers.get('authorization') ?? '';
  if (!header.toLowerCase().startsWith('bearer ')) return null;
  const token = header.slice(7).trim();
  if (!token) return null;

  const supabase = createClient(process.env.SUPABASE_URL!, process.env.SUPABASE_ANON_KEY!, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return null;

  const { data: profile } = await supabase
    .from('profiles')
    .select('id, email, name, role, created_at')
    .eq('id', data.user.id)
    .maybeSingle();

  if (!profile) return null;
  return { supabase, user: data.user, profile: profile as Profile };
}
