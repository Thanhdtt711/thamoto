// Supabase Edge Function (Deno) — P1-1b: Webhook đối soát chuyển khoản tự động (SePay / Casso / payOS)
// Deploy: supabase functions deploy payment-webhook
// Secrets:
//   supabase secrets set PAYMENT_WEBHOOK_SECRET=xxx SUPABASE_URL=xxx SUPABASE_SERVICE_ROLE_KEY=xxx

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
  }

  // Fail-closed: bắt buộc khớp secret
  const expectedSecret = Deno.env.get('PAYMENT_WEBHOOK_SECRET');
  if (!expectedSecret || expectedSecret.trim().length < 12) {
    return new Response(JSON.stringify({ error: 'Webhook secret not configured' }), { status: 500 });
  }
  const authHeader = req.headers.get('authorization') || req.headers.get('x-webhook-secret') || '';
  const token = authHeader.replace(/^Bearer\s+/i, '').replace(/^Apikey\s+/i, '').trim();
  if (token !== expectedSecret) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400 });
  }

  // Chuẩn hóa payload phổ biến từ SePay / Casso / payOS
  const provider = String(body.provider || body.gateway || 'bank_webhook').toLowerCase();
  const providerRef = String(body.referenceCode || body.id || body.transaction_id || '').trim();
  const amount = Math.floor(Number(body.transferAmount ?? body.amount ?? 0));
  const content = String(body.content || body.description || '');

  // Tìm mã đơn dạng TT-YYMMDD-XXXXXX hoặc TTYYMMDDXXXXXX trong nội dung chuyển khoản
  const match = content.toUpperCase().match(/TT-?\d{6}-?[A-Z0-9]{6}/);
  if (!match || !providerRef || amount <= 0) {
    return new Response(JSON.stringify({ ok: true, ignored: true, reason: 'no_order_code_or_invalid_amount' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' }
    });
  }

  let orderCode = match[0];
  if (!orderCode.includes('-')) {
    orderCode = `${orderCode.slice(0, 2)}-${orderCode.slice(2, 8)}-${orderCode.slice(8)}`;
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
  if (!supabaseUrl || !serviceKey) {
    return new Response(JSON.stringify({ error: 'Supabase credentials missing' }), { status: 500 });
  }

  const supabase = createClient(supabaseUrl, serviceKey);
  const { data, error } = await supabase.rpc('system_mark_paid', {
    p_order_code: orderCode,
    p_amount: amount,
    p_provider: provider,
    p_provider_ref: providerRef,
    p_raw: body
  });

  if (error) {
    return new Response(JSON.stringify({ ok: false, error: error.message }), { status: 400 });
  }

  return new Response(JSON.stringify({ ok: true, result: data }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
});
