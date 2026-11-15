// apps/api/lib/midtrans.ts
// Klien minimal Midtrans Core API untuk QRIS dinamis (charge, status, cancel).
// Server key HANYA di server. MIDTRANS_IS_PRODUCTION=true untuk akun produksi; default sandbox.
// Docs: https://docs.midtrans.com/reference/qris

export interface MidtransResponse {
  status_code?: string;
  status_message?: string;
  transaction_status?: string;
  order_id?: string;
  gross_amount?: string;
  qr_string?: string;
  expiry_time?: string;
  actions?: { name: string; method: string; url: string }[];
}

export function midtransConfigured(): boolean {
  const key = process.env.MIDTRANS_SERVER_KEY ?? '';
  return key.trim().length > 0 && !/x{4,}|your-server-key/i.test(key);
}

export function midtransIsProduction(): boolean {
  return (process.env.MIDTRANS_IS_PRODUCTION ?? '').toLowerCase() === 'true';
}

function baseUrl(): string {
  return midtransIsProduction() ? 'https://api.midtrans.com' : 'https://api.sandbox.midtrans.com';
}

async function call(method: 'GET' | 'POST', path: string, body?: unknown): Promise<MidtransResponse> {
  const key = process.env.MIDTRANS_SERVER_KEY ?? '';
  const res = await fetch(`${baseUrl()}${path}`, {
    method,
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      Authorization: `Basic ${Buffer.from(`${key}:`).toString('base64')}`,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: 'no-store',
    signal: AbortSignal.timeout(20_000),
  });
  let data: MidtransResponse = {};
  try {
    data = (await res.json()) as MidtransResponse;
  } catch {
    // respons non-JSON → ditangani di bawah
  }
  if (!res.ok && !data.status_code) {
    throw new Error(`Midtrans HTTP ${res.status}`);
  }
  return data;
}

/** Buat QRIS dinamis. gross_amount wajib bilangan bulat Rupiah. */
export async function chargeQris(orderId: string, grossAmount: number, expiryMinutes: number) {
  const data = await call('POST', '/v2/charge', {
    payment_type: 'qris',
    transaction_details: { order_id: orderId, gross_amount: grossAmount },
    qris: { acquirer: 'gopay' },
    custom_expiry: { expiry_duration: expiryMinutes, unit: 'minute' },
  });
  if (data.status_code !== '201' || !data.qr_string) {
    throw new Error(data.status_message || `Midtrans menolak charge (status ${data.status_code ?? '?'})`);
  }
  return {
    qrString: data.qr_string,
    qrUrl: data.actions?.find((a) => a.name === 'generate-qr-code')?.url ?? null,
  };
}

export async function getStatus(orderId: string): Promise<MidtransResponse> {
  return call('GET', `/v2/${encodeURIComponent(orderId)}/status`);
}

export async function cancelCharge(orderId: string): Promise<MidtransResponse> {
  return call('POST', `/v2/${encodeURIComponent(orderId)}/cancel`);
}

export type PaymentOutcome = 'paid' | 'pending' | 'expired' | 'cancelled' | 'unknown';

/** Petakan transaction_status Midtrans ke status internal. */
export function outcomeOf(status: string | undefined): PaymentOutcome {
  switch (status) {
    case 'settlement':
    case 'capture':
      return 'paid';
    case 'pending':
      return 'pending';
    case 'expire':
      return 'expired';
    case 'cancel':
    case 'deny':
    case 'failure':
      return 'cancelled';
    default:
      return 'unknown';
  }
}
