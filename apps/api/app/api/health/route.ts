// apps/api/app/api/health/route.ts
// Cek cepat bahwa API hidup & env sudah lengkap (tanpa membocorkan nilai rahasia).
import { json, preflight } from '@/lib/http';

export const dynamic = 'force-dynamic';

export function OPTIONS(request: Request) {
  return preflight(request);
}

export function GET(request: Request) {
  return json(request, {
    ok: true,
    service: 'coffee-pos-api',
    env: {
      SUPABASE_URL: Boolean(process.env.SUPABASE_URL),
      SUPABASE_ANON_KEY: Boolean(process.env.SUPABASE_ANON_KEY),
      SUPABASE_SERVICE_ROLE_KEY: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
      ANTHROPIC_API_KEY: Boolean(process.env.ANTHROPIC_API_KEY),
    },
    model: process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-5',
  });
}
