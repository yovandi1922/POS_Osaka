// apps/api/app/api/users/route.ts
// Owner mengelola akun staff dari Flutter Web admin:
//   POST   — buat akun (kasir/admin/owner); trigger handle_new_user membuat profile.
//   PATCH  — ubah nama, email, password, dan/atau role.
//   DELETE — hapus akun (?id=...). Profile & riwayat chat ikut terhapus (cascade);
//            transaksi/pengeluaran tetap ada dengan kasir/pembuat = null.
// Memakai service role untuk auth.admin.*, jadi setiap handler wajib cek role owner dulu.
import type { SupabaseClient } from '@supabase/supabase-js';
import { authenticateRequest, type AuthedRequest } from '@/lib/auth';
import { json, preflight } from '@/lib/http';
import { createAdminClient } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ROLES = ['kasir', 'admin', 'owner'] as const;
type Role = (typeof ROLES)[number];

export function OPTIONS(request: Request) {
  return preflight(request);
}

/** Pastikan pemanggil owner dan service role tersedia. */
async function ownerContext(
  request: Request,
): Promise<{ auth: AuthedRequest; admin: SupabaseClient } | { error: Response }> {
  const auth = await authenticateRequest(request);
  if (!auth) return { error: json(request, { error: 'Unauthorized' }, 401) };
  if (auth.profile.role !== 'owner') {
    return { error: json(request, { error: 'Hanya owner yang dapat mengelola pengguna.' }, 403) };
  }
  const admin = createAdminClient();
  if (!admin) {
    return { error: json(request, { error: 'SUPABASE_SERVICE_ROLE_KEY belum dikonfigurasi di server.' }, 500) };
  }
  return { auth, admin };
}

async function readBody(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = (await request.json()) as unknown;
    return body && typeof body === 'object' ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

export async function POST(request: Request) {
  const ctx = await ownerContext(request);
  if ('error' in ctx) return ctx.error;
  const { admin } = ctx;

  const body = await readBody(request);
  if (!body) return json(request, { error: 'Body harus JSON.' }, 400);

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  const role: Role = body.role === 'admin' || body.role === 'owner' ? body.role : 'kasir';

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

export async function PATCH(request: Request) {
  const ctx = await ownerContext(request);
  if ('error' in ctx) return ctx.error;
  const { auth, admin } = ctx;

  const body = await readBody(request);
  if (!body) return json(request, { error: 'Body harus JSON.' }, 400);

  const id = typeof body.id === 'string' ? body.id : '';
  const { data: target } = await admin.from('profiles').select('id, email, name, role').eq('id', id).maybeSingle();
  if (!target) return json(request, { error: 'Pengguna tidak ditemukan.' }, 404);

  const profileUpdate: { name?: string; email?: string; role?: Role } = {};
  const authUpdate: { email?: string; password?: string; email_confirm?: boolean; user_metadata?: { name: string } } =
    {};

  if (typeof body.name === 'string') {
    const name = body.name.trim();
    if (!name) return json(request, { error: 'Nama tidak boleh kosong.' }, 400);
    if (name !== target.name) {
      profileUpdate.name = name;
      authUpdate.user_metadata = { name };
    }
  }

  if (typeof body.email === 'string') {
    const email = body.email.trim().toLowerCase();
    if (!EMAIL_RE.test(email)) return json(request, { error: 'Email tidak valid.' }, 400);
    if (email !== target.email) {
      profileUpdate.email = email;
      authUpdate.email = email;
      authUpdate.email_confirm = true;
    }
  }

  if (typeof body.password === 'string' && body.password.length > 0) {
    if (body.password.length < 8) return json(request, { error: 'Password minimal 8 karakter.' }, 400);
    authUpdate.password = body.password;
  }

  if (body.role !== undefined) {
    if (!ROLES.includes(body.role as Role)) return json(request, { error: 'Role tidak valid.' }, 400);
    if (body.role !== target.role) {
      // Cegah owner mengunci dirinya sendiri dari web admin.
      if (id === auth.user.id) return json(request, { error: 'Anda tidak dapat mengubah role akun sendiri.' }, 400);
      profileUpdate.role = body.role as Role;
    }
  }

  if (Object.keys(authUpdate).length > 0) {
    const { error } = await admin.auth.admin.updateUserById(id, authUpdate);
    if (error) return json(request, { error: error.message }, 400);
  }
  if (Object.keys(profileUpdate).length > 0) {
    const { error } = await admin.from('profiles').update(profileUpdate).eq('id', id);
    if (error) return json(request, { error: `Gagal memperbarui profil: ${error.message}` }, 500);
  }

  return json(request, { id, ...profileUpdate, passwordChanged: authUpdate.password !== undefined });
}

export async function DELETE(request: Request) {
  const ctx = await ownerContext(request);
  if ('error' in ctx) return ctx.error;
  const { auth, admin } = ctx;

  const id = new URL(request.url).searchParams.get('id') ?? '';
  if (!id) return json(request, { error: 'Parameter id wajib diisi.' }, 400);
  if (id === auth.user.id) return json(request, { error: 'Anda tidak dapat menghapus akun sendiri.' }, 400);

  const { error } = await admin.auth.admin.deleteUser(id);
  if (error) return json(request, { error: error.message }, 400);
  return json(request, { id, deleted: true });
}
