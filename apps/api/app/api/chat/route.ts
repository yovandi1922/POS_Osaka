// apps/api/app/api/chat/route.ts
// Endpoint chatbot "Kopi": Claude + tool use atas data Supabase.
// Auth: `Authorization: Bearer <supabase access_token>` dari app Flutter (mobile & admin web).
import Anthropic from '@anthropic-ai/sdk';
import { buildSystemPrompt } from '@/lib/ai/system-prompt';
import { executeTool, tools } from '@/lib/ai/tools';
import { authenticateRequest } from '@/lib/auth';
import { jakartaDate } from '@/lib/format';
import { json, preflight } from '@/lib/http';
import { createAdminClient } from '@/lib/supabase/admin';

export const runtime = 'nodejs';
export const maxDuration = 60;
export const dynamic = 'force-dynamic';

const MODEL = process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-5';
const MAX_STEPS = 6;
const MAX_HISTORY = 20;
const MAX_CONTENT_CHARS = 4000;

const anthropic = new Anthropic(); // membaca ANTHROPIC_API_KEY dari env

export function OPTIONS(request: Request) {
  return preflight(request);
}

interface IncomingMessage {
  role: 'user' | 'assistant';
  content: string;
}

function parseMessages(body: unknown): IncomingMessage[] | null {
  if (!body || typeof body !== 'object') return null;
  const raw = (body as { messages?: unknown }).messages;
  if (!Array.isArray(raw)) return null;

  const cleaned: IncomingMessage[] = [];
  for (const m of raw) {
    if (!m || typeof m !== 'object') continue;
    const role = (m as { role?: unknown }).role;
    const content = (m as { content?: unknown }).content;
    if ((role !== 'user' && role !== 'assistant') || typeof content !== 'string') continue;
    const text = content.trim().slice(0, MAX_CONTENT_CHARS);
    if (!text) continue;
    cleaned.push({ role, content: text });
  }

  const recent = cleaned.slice(-MAX_HISTORY);
  // Percakapan untuk API harus diawali pesan user.
  while (recent.length > 0 && recent[0].role !== 'user') recent.shift();
  if (recent.length === 0 || recent[recent.length - 1].role !== 'user') return null;
  return recent;
}

interface ToolLogEntry {
  name: string;
  input: unknown;
  is_error: boolean;
}

export async function POST(request: Request) {
  const auth = await authenticateRequest(request);
  if (!auth) {
    return json(request, { error: 'Unauthorized' }, 401);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(request, { error: 'Body harus JSON.' }, 400);
  }

  const messages = parseMessages(body);
  if (!messages) {
    return json(
      request,
      { error: 'Format salah. Kirim { messages: [{ role, content }] } dengan pesan terakhir dari user.' },
      400,
    );
  }
  const channel = (body as { channel?: unknown }).channel === 'mobile' ? 'mobile' : 'web';

  const { supabase, user, profile } = auth;
  const system = buildSystemPrompt({
    today: jakartaDate(),
    channel,
    role: profile.role,
    userName: profile.name || profile.email,
  });

  // Tools membaca agregat seluruh toko → service role (akses dibatasi per role di executeTool).
  // Jika service role tidak dikonfigurasi, fallback ke client user (RLS berlaku).
  const dataClient = createAdminClient() ?? supabase;

  const convo: Anthropic.MessageParam[] = messages.map((m) => ({ role: m.role, content: m.content }));
  const toolLog: ToolLogEntry[] = [];
  let finalText = '';

  try {
    for (let step = 0; step < MAX_STEPS; step++) {
      const response = await anthropic.messages.create({
        model: MODEL,
        max_tokens: 1024,
        system,
        tools,
        messages: convo,
      });

      if (response.stop_reason === 'tool_use') {
        const toolUses = response.content.filter(
          (block): block is Anthropic.ToolUseBlock => block.type === 'tool_use',
        );
        convo.push({ role: 'assistant', content: response.content });

        const results: Anthropic.ToolResultBlockParam[] = await Promise.all(
          toolUses.map(async (toolUse) => {
            const result = await executeTool(toolUse.name, toolUse.input, {
              supabase: dataClient,
              role: profile.role,
            });
            toolLog.push({ name: toolUse.name, input: toolUse.input, is_error: result.isError });
            return {
              type: 'tool_result' as const,
              tool_use_id: toolUse.id,
              content: result.content,
              is_error: result.isError,
            };
          }),
        );
        // Semua tool_result dikirim dalam SATU pesan user.
        convo.push({ role: 'user', content: results });
        continue;
      }

      finalText = response.content
        .filter((block): block is Anthropic.TextBlock => block.type === 'text')
        .map((block) => block.text)
        .join('\n')
        .trim();

      if (response.stop_reason === 'refusal' && !finalText) {
        finalText =
          'Maaf, Kopi tidak bisa membantu permintaan itu. Coba tanyakan seputar stok, penjualan, atau pengeluaran toko ya.';
      }
      break;
    }
  } catch (err) {
    console.error('[api/chat] Anthropic error:', err);
    if (err instanceof Anthropic.RateLimitError) {
      return json(request, { error: 'Kopi sedang sibuk (rate limit). Coba lagi sebentar lagi.' }, 429);
    }
    if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
      return json(request, { error: 'Konfigurasi ANTHROPIC_API_KEY di server tidak valid.' }, 500);
    }
    if (err instanceof Anthropic.BadRequestError) {
      return json(request, { error: 'Permintaan ke AI ditolak (bad request). Coba mulai percakapan baru.' }, 400);
    }
    if (err instanceof Anthropic.APIError) {
      return json(request, { error: 'Layanan AI sedang bermasalah. Coba lagi nanti.' }, 502);
    }
    return json(request, { error: 'Terjadi kesalahan pada server.' }, 500);
  }

  if (!finalText) {
    finalText =
      'Maaf, Kopi butuh terlalu banyak langkah untuk menjawab. Coba pertanyaan yang lebih spesifik, misalnya "omset 7 hari terakhir".';
  }

  // Simpan riwayat (RLS: user hanya bisa insert miliknya). Timestamp dibedakan agar urutan stabil.
  const now = Date.now();
  const lastUser = messages[messages.length - 1];
  const { error: saveError } = await supabase.from('chat_messages').insert([
    {
      user_id: user.id,
      role: 'user',
      content: lastUser.content,
      created_at: new Date(now).toISOString(),
    },
    {
      user_id: user.id,
      role: 'assistant',
      content: finalText,
      tool_calls_json: toolLog.length > 0 ? toolLog : null,
      created_at: new Date(now + 1).toISOString(),
    },
  ]);
  if (saveError) {
    console.error('[api/chat] gagal menyimpan chat_messages:', saveError.message);
  }

  return json(request, { content: finalText });
}
