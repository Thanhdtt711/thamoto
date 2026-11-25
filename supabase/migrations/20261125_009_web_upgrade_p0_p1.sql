-- ============================================================================
-- MIGRATION 009: Nâng cấp Web P0 & P1
--   - P0-3: Hoàn coupons.used_count idempotent khi đơn cancelled/returned
--   - P0-2: Cột client_fingerprint + RPC expire_stale_orders() tự hủy đơn treo
--   - P1-1a/1b: Cấu hình ngân hàng trong app_settings, bảng payment_events, RPC system_mark_paid
--   - P1-2: Phí vận chuyển & mã vận đơn (shipping_fee, shipping_carrier, tracking_code, admin_update_shipping)
--   - P1-3: RPC track_order(p_order_code, p_phone) cho trang /tra-cuu-don (không lộ PII)
--   - P1-5: Nâng cấp get_catalog_prices() trả thêm in_stock, low_stock (không lộ tồn kho chính xác)
--   - P1-1a: RPC get_storefront_config() trả cấu hình ngân hàng & phí ship public
--
-- Thứ tự chạy: 009 (sau 008). Idempotent: Có.
-- ============================================================================

-- 1. Mở rộng bảng orders (phí ship, vận đơn, đối soát thanh toán, hoàn coupon, chống spam)
alter table public.orders
  add column if not exists shipping_fee bigint not null default 0 check (shipping_fee >= 0),
  add column if not exists shipping_carrier text,
  add column if not exists tracking_code text,
  add column if not exists payment_ref text,
  add column if not exists paid_at timestamptz,
  add column if not exists client_fingerprint text,
  add column if not exists coupon_restored boolean not null default false;

-- 2. Mở rộng app_settings (ngân hàng VietQR, phí vận chuyển, hạn giữ đơn)
insert into public.app_settings (key, value, description)
values
  ('bank_name', '"VietinBank"'::jsonb, 'Tên ngân hàng nhận chuyển khoản VietQR'),
  ('bank_bin', '"970415"'::jsonb, 'Mã BIN ngân hàng chuẩn VietQR (VietinBank = 970415)'),
  ('bank_account', '"109876543210"'::jsonb, 'Số tài khoản nhận chuyển khoản'),
  ('bank_holder', '"CT CO PHAN TRUNG THANH"'::jsonb, 'Tên chủ tài khoản nhận tiền'),
  ('shipping_base_fee', '0'::jsonb, 'Phí vận chuyển cơ bản (VNĐ, 0 = miễn phí toàn quốc)'),
  ('free_ship_threshold', '1500000'::jsonb, 'Giá trị đơn hàng tối thiểu được miễn phí vận chuyển (VNĐ)'),
  ('order_expire_hours', '48'::jsonb, 'Số giờ tự hủy đơn mới chưa xác nhận để hoàn tồn kho')
on conflict (key) do nothing;

-- 3. P0-3: Trigger hoàn coupons.used_count 1 lần duy nhất khi đơn cancelled/returned
create or replace function public.restore_coupon_on_order_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('cancelled', 'returned')
     and old.status not in ('cancelled', 'returned')
     and new.coupon_code is not null
     and coalesce(old.coupon_restored, false) = false then
    update public.coupons
    set used_count = greatest(0, coalesce(used_count, 0) - 1)
    where upper(code) = upper(new.coupon_code);

    update public.orders
    set coupon_restored = true
    where id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_restore_coupon_on_order_cancel on public.orders;
create trigger trg_restore_coupon_on_order_cancel
after update of status on public.orders
for each row execute function public.restore_coupon_on_order_cancel();

-- 4. P0-2: RPC expire_stale_orders() tự hủy đơn 'new' quá hạn (kích hoạt hoàn kho + hoàn coupon)
create or replace function public.expire_stale_orders(p_hours int default null)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hours int;
  v_cnt int := 0;
begin
  v_hours := coalesce(
    p_hours,
    (select (value #>> '{}')::int from public.app_settings where key = 'order_expire_hours'),
    48
  );
  v_hours := greatest(1, least(720, v_hours));

  with expired as (
    update public.orders
    set status = 'cancelled',
        cancel_reason = format('Tự động hủy do quá %s giờ chưa xác nhận', v_hours),
        updated_at = now()
    where status = 'new'
      and payment_status = 'unpaid'
      and created_at < now() - make_interval(hours => v_hours)
    returning id
  )
  select count(*) into v_cnt from expired;

  return v_cnt;
end;
$$;

revoke all on function public.expire_stale_orders(int) from public, anon, authenticated;
grant execute on function public.expire_stale_orders(int) to service_role;

-- 5. P1-1b: Bảng payment_events & RPC system_mark_paid (idempotent, chỉ service_role)
create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_ref text not null,
  order_id uuid references public.orders(id),
  order_code text,
  amount bigint not null,
  status text not null default 'matched' check (status in ('matched', 'amount_mismatch', 'not_found')),
  raw jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (provider, provider_ref)
);

alter table public.payment_events enable row level security;

drop policy if exists "admin_read_payment_events" on public.payment_events;
create policy "admin_read_payment_events"
  on public.payment_events for select
  to authenticated
  using (public.is_admin());

create or replace function public.system_mark_paid(
  p_order_code text,
  p_amount bigint,
  p_provider text,
  p_provider_ref text,
  p_raw jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.payment_events;
  v_order public.orders;
  v_code text := upper(trim(coalesce(p_order_code, '')));
begin
  -- Idempotency check
  select * into v_existing
  from public.payment_events
  where provider = p_provider and provider_ref = p_provider_ref;
  if found then
    return jsonb_build_object('idempotent', true, 'status', v_existing.status, 'order_code', v_existing.order_code);
  end if;

  select * into v_order from public.orders where upper(order_code) = v_code for update;
  if not found then
    insert into public.payment_events (provider, provider_ref, order_code, amount, status, raw)
    values (p_provider, p_provider_ref, v_code, p_amount, 'not_found', coalesce(p_raw, '{}'::jsonb));
    return jsonb_build_object('matched', false, 'status', 'not_found');
  end if;

  if p_amount < v_order.total_amount then
    insert into public.payment_events (provider, provider_ref, order_id, order_code, amount, status, raw)
    values (p_provider, p_provider_ref, v_order.id, v_order.order_code, p_amount, 'amount_mismatch', coalesce(p_raw, '{}'::jsonb));
    return jsonb_build_object('matched', false, 'status', 'amount_mismatch', 'expected', v_order.total_amount, 'received', p_amount);
  end if;

  insert into public.payment_events (provider, provider_ref, order_id, order_code, amount, status, raw)
  values (p_provider, p_provider_ref, v_order.id, v_order.order_code, p_amount, 'matched', coalesce(p_raw, '{}'::jsonb));

  update public.orders
  set payment_status = 'paid',
      payment_ref = p_provider_ref,
      paid_at = coalesce(paid_at, now()),
      updated_at = now()
  where id = v_order.id;

  perform public.write_audit_log(
    'system_mark_paid', 'orders', v_order.id::text,
    jsonb_build_object('payment_status', v_order.payment_status),
    jsonb_build_object('payment_status', 'paid', 'payment_ref', p_provider_ref, 'amount', p_amount),
    'Webhook ' || p_provider
  );

  return jsonb_build_object('matched', true, 'status', 'matched', 'order_code', v_order.order_code);
end;
$$;

revoke all on function public.system_mark_paid(text, bigint, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.system_mark_paid(text, bigint, text, text, jsonb) to service_role;

-- 6. P1-2: Admin cập nhật đơn vị vận chuyển & mã vận đơn (có audit log)
create or replace function public.admin_update_shipping(
  p_order_id uuid,
  p_carrier text,
  p_tracking_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.orders;
begin
  if not public.has_permission('orders') then
    raise exception 'Không có quyền cập nhật vận đơn';
  end if;

  select * into v_old from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Không tìm thấy đơn hàng';
  end if;

  update public.orders
  set shipping_carrier = nullif(trim(coalesce(p_carrier, '')), ''),
      tracking_code = nullif(trim(coalesce(p_tracking_code, '')), ''),
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_order_id;

  perform public.write_audit_log(
    'admin_update_shipping', 'orders', p_order_id::text,
    jsonb_build_object('shipping_carrier', v_old.shipping_carrier, 'tracking_code', v_old.tracking_code),
    jsonb_build_object('shipping_carrier', nullif(trim(coalesce(p_carrier, '')), ''), 'tracking_code', nullif(trim(coalesce(p_tracking_code, '')), ''))
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_update_shipping(uuid, text, text) from public, anon;
grant execute on function public.admin_update_shipping(uuid, text, text) to authenticated;

-- 7. P1-3: RPC tra cứu đơn hàng công khai (yêu cầu khớp CẢ mã đơn + SĐT, không lộ địa chỉ/PII)
create or replace function public.track_order(
  p_order_code text,
  p_phone text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_order_code, '')));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_order record;
begin
  if length(v_code) < 5 or length(v_phone) < 9 then
    return jsonb_build_object('found', false, 'message', 'Vui lòng nhập đầy đủ mã đơn hàng và số điện thoại đặt hàng.');
  end if;

  select
    o.order_code,
    public.mask_customer_name(o.customer_name) as customer_name_masked,
    o.status,
    o.payment_method,
    o.payment_status,
    o.total_amount,
    o.shipping_fee,
    o.shipping_carrier,
    o.tracking_code,
    o.items_summary,
    o.cancel_reason,
    o.created_at,
    o.updated_at
  into v_order
  from public.orders o
  where upper(o.order_code) = v_code
    and regexp_replace(coalesce(o.phone, ''), '[^0-9]', '', 'g') = v_phone
  limit 1;

  if not found then
    return jsonb_build_object('found', false, 'message', 'Không tìm thấy đơn hàng khớp với mã đơn và số điện thoại này.');
  end if;

  return jsonb_build_object('found', true, 'order', row_to_json(v_order));
end;
$$;

revoke all on function public.track_order(text, text) from public;
grant execute on function public.track_order(text, text) to anon, authenticated;

-- 8. P1-1a & P1-2: RPC get_storefront_config() (trả cấu hình ngân hàng & ship public)
create or replace function public.get_storefront_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
  from public.app_settings
  where key in (
    'bank_name', 'bank_bin', 'bank_account', 'bank_holder',
    'shipping_base_fee', 'free_ship_threshold'
  );
$$;

revoke all on function public.get_storefront_config() from public;
grant execute on function public.get_storefront_config() to anon, authenticated;

-- 9. P1-5: Nâng cấp get_catalog_prices() trả thêm in_stock & low_stock (không lộ số tồn chính xác)
create or replace function public.get_catalog_prices()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'sku', p.sku,
      'name', p.name,
      'product_type', p.product_type,
      'base_price', p.base_price,
      'image_url', p.image_url,
      'in_stock', (p.stock_qty is null or p.stock_qty > 0),
      'low_stock', (p.stock_qty is not null and p.stock_qty > 0 and p.stock_qty <= 5)
    )
    order by p.product_type, p.base_price asc
  ), '[]'::jsonb)
  from public.products p
  where p.is_active = true;
$$;

revoke all on function public.get_catalog_prices() from public;
grant execute on function public.get_catalog_prices() to anon, authenticated;

notify pgrst, 'reload schema';

-- ============================================================================
-- ROLLBACK (ghi chú):
--   drop function if exists public.get_storefront_config();
--   drop function if exists public.track_order(text, text);
--   drop function if exists public.admin_update_shipping(uuid, text, text);
--   drop function if exists public.system_mark_paid(text, bigint, text, text, jsonb);
--   drop table if exists public.payment_events;
--   drop function if exists public.expire_stale_orders(int);
--   drop trigger if exists trg_restore_coupon_on_order_cancel on public.orders;
--   drop function if exists public.restore_coupon_on_order_cancel();
-- ============================================================================
