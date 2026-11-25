// Supabase Edge Function (Deno) — P1-10: Thông báo đơn hàng / chi trả qua Telegram hoặc Email
// Deploy: supabase functions deploy notify-order
// Cấu hình secrets trên Supabase (KHÔNG commit secret thật vào repo):
//   supabase secrets set TELEGRAM_BOT_TOKEN=xxx TELEGRAM_CHAT_ID=xxx NOTIFY_WEBHOOK_SECRET=xxx

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

interface NotifyPayload {
  type: 'order_created' | 'payout_requested' | 'payout_paid';
  record: Record<string, unknown>;
}

const formatVnd = (n: unknown) => `${Number(n || 0).toLocaleString('vi-VN')} đ`;

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405 });
  }

  // Xác thực webhook secret từ Database Webhook của Supabase
  const expectedSecret = Deno.env.get('NOTIFY_WEBHOOK_SECRET');
  const incomingSecret = req.headers.get('x-webhook-secret');
  if (expectedSecret && incomingSecret !== expectedSecret) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  let payload: NotifyPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400 });
  }

  const botToken = Deno.env.get('TELEGRAM_BOT_TOKEN');
  const chatId = Deno.env.get('TELEGRAM_CHAT_ID');

  if (!botToken || !chatId) {
    return new Response(
      JSON.stringify({ ok: false, message: 'Chưa cấu hình TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID' }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const r = payload.record || {};
  let text = '';

  if (payload.type === 'order_created') {
    text = [
      `🛒 *ĐƠN HÀNG MỚI* #${r.order_code || ''}`,
      `Khách: ${r.customer_name || ''} · ${r.customer_phone || ''}`,
      `Tổng tiền: ${formatVnd(r.total)}`,
      r.affiliate_code ? `CTV: ${r.affiliate_code} (HH: ${formatVnd(r.commission_amount)})` : 'CTV: Không',
    ].join('\n');
  } else if (payload.type === 'payout_requested') {
    text = [
      `💸 *YÊU CẦU RÚT TIỀN MỚI*`,
      `Số tiền: ${formatVnd(r.amount)}`,
      `Trạng thái: ${r.status || 'requested'}`,
    ].join('\n');
  } else if (payload.type === 'payout_paid') {
    text = [
      `✅ *ĐÃ CHI TRẢ HOA HỒNG*`,
      `Thực nhận: ${formatVnd(r.net_amount ?? r.amount)}`,
      `Mã GD: ${r.transaction_ref || '—'}`,
    ].join('\n');
  } else {
    return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200 });
  }

  const tgRes = await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      parse_mode: 'Markdown',
    }),
  });

  if (!tgRes.ok) {
    const errText = await tgRes.text();
    return new Response(JSON.stringify({ ok: false, error: errText }), { status: 502 });
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
