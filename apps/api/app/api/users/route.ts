// apps/api/app/api/users/route.ts
// Owner membuat akun staff baru (kasir/admin/owner) dari Flutter Web admin.
// Memakai service role untuk auth.admin.createUser; trigger handle_new_user membuat profile.
import { authenticateRequest } from '@/lib/auth';
import { json, preflight } from '@/lib/http';
import { createAdminClient } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function OPTIONS(request: Request) {
  return preflight(request);
}

export async function POST(request: Request) {
  const auth = await authenticateRequest(request);
  if (!auth) return json(request, { error: 'Unauthorized' }, 401);
  if (auth.profile.role !== 'owner') {
    return json(request, { error: 'Hanya owner yang dapat menambah pengguna.' }, 403);
  }

  const admin = createAdminClient();
  if (!admin) {
    return json(request, { error: 'SUPABASE_SERVICE_ROLE_KEY belum dikonfigurasi di server.' }, 500);
  }

  let body: { email?: unknown; password?: unknown; name?: unknown; role?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json(request, { error: 'Body harus JSON.' }, 400);
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  const role = body.role === 'admin' || body.role === 'owner' ? body.role : 'kasir';

  if (!EMAIL_RE.test(email)) return json(request, { error: 'Email tidak valid.' }, 400);
  if (password.length < 8) return json(request, { error: 'Password minimal 8 karakter.' }, 400);

  const displayName = name || email.split('@')[0];
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name: displayName },
  });
  if (error || !data.user) {
    return json(request, { error: error?.message ?? 'Gagal membuat user.' }, 400);
  }

  // Trigger membuat profile dengan role 'kasir'; set role & nama sesuai input.
  const { error: profileError } = await admin
    .from('profiles')
    .upsert({ id: data.user.id, email, name: displayName, role }, { onConflict: 'id' });
  if (profileError) {
    return json(request, { error: `User dibuat, tetapi gagal set role: ${profileError.message}` }, 500);
  }

  return json(request, { id: data.user.id, email, name: displayName, role }, 201);
}
