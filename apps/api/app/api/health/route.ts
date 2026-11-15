// apps/api/app/api/health/route.ts
// Cek cepat bahwa API hidup & env sudah lengkap (tanpa membocorkan nilai rahasia).
import { json, preflight } from '@/lib/http';
import { midtransConfigured, midtransIsProduction } from '@/lib/midtrans';

export const dynamic = 'force-dynamic';

export function OPTIONS(request: Request) {
  return preflight(request);
}

/** true hanya jika terisi DAN bukan teks contoh dari .env.example. */
function configured(value: string | undefined): boolean {
  if (!value || !value.trim()) return false;
  return !/YOUR-PROJECT-REF|your-anon|your-service|sk-ant-x{4,}/i.test(value);
}

export function GET(request: Request) {
  return json(request, {
    ok: true,
    service: 'coffee-pos-api',
    env: {
      SUPABASE_URL: configured(process.env.SUPABASE_URL),
      SUPABASE_ANON_KEY: configured(process.env.SUPABASE_ANON_KEY),
      SUPABASE_SERVICE_ROLE_KEY: configured(process.env.SUPABASE_SERVICE_ROLE_KEY),
      ANTHROPIC_API_KEY: configured(process.env.ANTHROPIC_API_KEY),
      MIDTRANS_SERVER_KEY: midtransConfigured(),
    },
    model: process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-5',
    midtrans: midtransIsProduction() ? 'production' : 'sandbox',
  });
}
