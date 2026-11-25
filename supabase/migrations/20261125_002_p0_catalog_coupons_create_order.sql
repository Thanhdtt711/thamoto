-- ============================================================
-- Migration: 20261125_002_p0_catalog_coupons_create_order.sql
-- Phạm vi: P0-1 (Đặt đơn qua RPC create_order, bảng giá/coupon phía server,
--          ép trạng thái khởi tạo, chống tự giới thiệu, bỏ anon direct insert)
--          Giải quyết V01, V07, V08, V12, V14
-- Thứ tự chạy: 002 (sau 001)
-- Điều kiện tiên quyết: Đã chạy 001_p0_settings_audit_security.sql
--
-- ROLLBACK (chạy thủ công nếu cần):
--   drop function if exists public.create_order(text, text, text, text, text, text, text, text, jsonb, uuid);
--   drop function if exists public.create_lead(text, text, text, text, text);
--   drop function if exists public.validate_coupon(text, bigint);
--   drop function if exists public.validate_affiliate_code(text);
--   drop table if exists public.order_items;
--   drop table if exists public.commission_rules;
--   drop table if exists public.coupons;
--   drop table if exists public.products;
--   drop table if exists public.product_categories;
-- ============================================================

-- 1. Bảng Danh mục & Sản phẩm/Phụ kiện (nguồn giá duy nhất phía server)
create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  sku text unique not null,
  category_id uuid references public.product_categories(id),
  name text not null,
  product_type text not null default 'mat' check (product_type in ('mat', 'addon')),
  base_price bigint not null check (base_price >= 0),
  image_url text,
  commission_eligible boolean not null default true,
  stock_qty int,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Seed danh mục & bảng giá chuẩn khớp với shared/utils/vehicles.ts
insert into public.product_categories (slug, name, sort_order) values
  ('tham-san', 'Thảm lót sàn ô tô', 1),
  ('phu-kien', 'Phụ kiện kèm theo', 2)
on conflict (slug) do nothing;

insert into public.products (sku, category_id, name, product_type, base_price, image_url, commission_eligible) values
  ('MAT-6D', (select id from public.product_categories where slug = 'tham-san'), 'Thảm 6D Cao Cấp', 'mat', 1350000, '/assets/images/mat-6d-red.webp', true),
  ('MAT-360', (select id from public.product_categories where slug = 'tham-san'), 'Thảm 360 Full Xe', 'mat', 2200000, '/assets/images/mat-carbon-gold.webp', true),
  ('MAT-TPE', (select id from public.product_categories where slug = 'tham-san'), 'Thảm Nhựa TPE Đúc Khuôn', 'mat', 1890000, '/assets/images/mat-tpe-black.webp', true),
  ('MAT-5D', (select id from public.product_categories where slug = 'tham-san'), 'Thảm Da 5D Quả Trám', 'mat', 1250000, '/assets/images/mat-5d-brown.webp', true),
  ('ADDON-THAM-ROI', (select id from public.product_categories where slug = 'phu-kien'), 'Thảm rối chống bẩn', 'addon', 150000, null, true),
  ('ADDON-LOT-COP', (select id from public.product_categories where slug = 'phu-kien'), 'Thảm lót cốp', 'addon', 300000, null, true)
on conflict (sku) do nothing;

-- 2. Bảng Mã giảm giá (coupons) quản lý phía server
create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  discount_type text not null check (discount_type in ('fixed', 'percent')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  min_order_amount bigint not null default 0 check (min_order_amount >= 0),
  max_discount_amount bigint,
  usage_limit int,
  used_count int not null default 0,
  starts_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.coupons (code, discount_type, discount_value, min_order_amount, is_active) values
  ('THAMOTO2026', 'fixed', 150000, 1000000, true),
  ('VIP10', 'percent', 10, 1000000, true)
on conflict (code) do nothing;

-- 3. Bảng Quy tắc hoa hồng theo Sản phẩm / CTV (Q1 priority: product+ctv -> product -> ctv -> default)
create table if not exists public.commission_rules (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  affiliate_id uuid references public.affiliates(id) on delete cascade,
  rate numeric(5,2) not null check (rate >= 0 and rate <= 50),
  is_active boolean not null default true,
  valid_from timestamptz,
  valid_to timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_commission_rules_lookup
  on public.commission_rules(product_id, affiliate_id) where is_active = true;

-- 4. Mở rộng bảng orders (Q1, Q2, Q4, V12)
alter table public.orders
  add column if not exists subtotal bigint not null default 0,
  add column if not exists discount_amount bigint not null default 0,
  add column if not exists shipping_fee bigint not null default 0,
  add column if not exists payment_status text not null default 'unpaid',
  add column if not exists affiliate_id uuid references public.affiliates(id),
  add column if not exists ref_source text,
  add column if not exists ref_click_id uuid,
  add column if not exists attributed_at timestamptz,
  add column if not exists self_referral boolean not null default false,
  add column if not exists completed_at timestamptz,
  add column if not exists cancel_reason text,
  add column if not exists customer_email text;

alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders
  add constraint orders_status_check check (status in ('new', 'confirmed', 'shipping', 'completed', 'cancelled', 'returned'));

alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders
  add constraint orders_payment_status_check check (payment_status in ('unpaid', 'paid', 'refunded'));

alter table public.orders drop constraint if exists orders_ref_source_check;
alter table public.orders
  add constraint orders_ref_source_check check (ref_source is null or ref_source in ('link', 'manual', 'admin_override'));

-- Backfill subtotal & affiliate_id cho các đơn cũ
update public.orders o
set subtotal = case when subtotal = 0 then total_amount else subtotal end,
    affiliate_id = coalesce(o.affiliate_id, (select a.id from public.affiliates a where upper(a.code) = upper(o.affiliate_code) limit 1)),
    completed_at = case when o.status = 'completed' and o.completed_at is null then o.created_at else o.completed_at end
where subtotal = 0 or (o.affiliate_code is not null and o.affiliate_id is null) or (o.status = 'completed' and o.completed_at is null);

-- 5. Bảng order_items chuẩn hóa từng dòng hàng (Q1)
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  product_name text not null,
  material text not null,
  color text,
  form_label text,
  addons jsonb not null default '[]'::jsonb,
  vehicle jsonb,
  unit_price bigint not null check (unit_price >= 0),
  quantity int not null check (quantity > 0),
  line_subtotal bigint not null check (line_subtotal >= 0),
  allocated_discount bigint not null default 0 check (allocated_discount >= 0),
  net_amount bigint not null check (net_amount >= 0),
  commission_eligible boolean not null default true,
  commission_rate numeric(5,2) not null default 0,
  commission_amount bigint not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_order_items_order_id on public.order_items(order_id);

-- RLS cho các bảng catalog / coupon / order_items
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.coupons enable row level security;
alter table public.commission_rules enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Public can read active categories" on public.product_categories;
create policy "Public can read active categories"
  on public.product_categories for select to anon, authenticated using (is_active = true or public.is_admin());

drop policy if exists "Admins manage categories" on public.product_categories;
create policy "Admins manage categories"
  on public.product_categories for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Public can read active products" on public.products;
create policy "Public can read active products"
  on public.products for select to anon, authenticated using (is_active = true or public.is_admin());

drop policy if exists "Admins manage products" on public.products;
create policy "Admins manage products"
  on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admins manage coupons" on public.coupons;
create policy "Admins manage coupons"
  on public.coupons for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admins manage commission rules" on public.commission_rules;
create policy "Admins manage commission rules"
  on public.commission_rules for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "Admins view order items" on public.order_items;
create policy "Admins view order items"
  on public.order_items for select to authenticated using (public.is_staff_or_admin());

-- 6. GỠ bỏ policy INSERT tự do trên orders và leads (fix V01)
drop policy if exists "Anyone can place orders" on public.orders;
drop policy if exists "Anyone can submit leads" on public.leads;
drop trigger if exists trg_orders_calc_commission on public.orders;

-- 7. Helper xác định tỷ lệ hoa hồng theo Q1 (product+ctv -> product -> ctv -> default)
create or replace function public.resolve_commission_rate(
  p_product_id uuid,
  p_affiliate_id uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rate numeric;
begin
  if p_affiliate_id is null then
    return 0;
  end if;

  -- (1a) Rule riêng theo sản phẩm + CTV
  if p_product_id is not null then
    select rate into v_rate
    from public.commission_rules
    where is_active = true
      and product_id = p_product_id
      and affiliate_id = p_affiliate_id
      and (valid_from is null or valid_from <= now())
      and (valid_to is null or valid_to >= now())
    order by created_at desc
    limit 1;
    if v_rate is not null then return v_rate; end if;

    -- (1b) Rule riêng theo sản phẩm (mọi CTV)
    select rate into v_rate
    from public.commission_rules
    where is_active = true
      and product_id = p_product_id
      and affiliate_id is null
      and (valid_from is null or valid_from <= now())
      and (valid_to is null or valid_to >= now())
    order by created_at desc
    limit 1;
    if v_rate is not null then return v_rate; end if;
  end if;

  -- (2) Tỷ lệ riêng theo CTV
  select commission_rate into v_rate
  from public.affiliates
  where id = p_affiliate_id and status = 'active';
  if v_rate is not null then return v_rate; end if;

  -- (3) Tỷ lệ mặc định trong app_settings
  return public.get_setting_numeric('default_commission_rate', 10.00);
end;
$$;

-- 8. RPC công khai kiểm tra mã giảm giá (dùng ở gio-hang.vue & thanh-toan.vue)
create or replace function public.validate_coupon(
  p_code text,
  p_subtotal bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_coupon public.coupons;
  v_discount bigint := 0;
begin
  if p_code is null or length(trim(p_code)) = 0 then
    return jsonb_build_object('valid', false, 'message', 'Vui lòng nhập mã giảm giá.');
  end if;

  select * into v_coupon
  from public.coupons
  where upper(code) = upper(trim(p_code))
    and is_active = true
  limit 1;

  if not found then
    return jsonb_build_object('valid', false, 'message', 'Mã giảm giá không tồn tại hoặc đã ngừng áp dụng.');
  end if;

  if v_coupon.starts_at is not null and now() < v_coupon.starts_at then
    return jsonb_build_object('valid', false, 'message', 'Mã giảm giá chưa đến thời gian áp dụng.');
  end if;

  if v_coupon.expires_at is not null and now() > v_coupon.expires_at then
    return jsonb_build_object('valid', false, 'message', 'Mã giảm giá đã hết hạn.');
  end if;

  if v_coupon.usage_limit is not null and v_coupon.used_count >= v_coupon.usage_limit then
    return jsonb_build_object('valid', false, 'message', 'Mã giảm giá đã hết lượt sử dụng.');
  end if;

  if p_subtotal < v_coupon.min_order_amount then
    return jsonb_build_object('valid', false, 'message', format('Đơn tối thiểu %s đ để áp dụng mã này.', v_coupon.min_order_amount));
  end if;

  if v_coupon.discount_type = 'percent' then
    v_discount := floor((p_subtotal * v_coupon.discount_value) / 100.0);
    if v_coupon.max_discount_amount is not null then
      v_discount := least(v_discount, v_coupon.max_discount_amount);
    end if;
  else
    v_discount := floor(v_coupon.discount_value);
  end if;

  v_discount := least(v_discount, greatest(p_subtotal, 0));

  return jsonb_build_object(
    'valid', true,
    'code', v_coupon.code,
    'discount_type', v_coupon.discount_type,
    'discount_value', v_coupon.discount_value,
    'discount_amount', v_discount,
    'message', format('Áp dụng mã %s thành công!', v_coupon.code)
  );
end;
$$;

revoke all on function public.validate_coupon(text, bigint) from public;
grant execute on function public.validate_coupon(text, bigint) to anon, authenticated;

-- 9. RPC công khai kiểm tra mã CTV hợp lệ (không lộ PII của CTV)
create or replace function public.validate_affiliate_code(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_clean text := upper(trim(coalesce(p_code, '')));
  v_exists boolean;
begin
  if length(v_clean) < 3 then
    return jsonb_build_object('valid', false, 'message', 'Mã giới thiệu không hợp lệ.');
  end if;

  select exists (
    select 1 from public.affiliates where code = v_clean and status = 'active'
  ) into v_exists;

  if v_exists then
    return jsonb_build_object('valid', true, 'code', v_clean, 'message', 'Mã giới thiệu hợp lệ.');
  end if;

  return jsonb_build_object('valid', false, 'message', 'Mã giới thiệu không tồn tại hoặc CTV chưa kích hoạt.');
end;
$$;

revoke all on function public.validate_affiliate_code(text) from public;
grant execute on function public.validate_affiliate_code(text) to anon, authenticated;

-- 10. RPC create_order: server tự tính giá, mã giảm giá, hoa hồng từng dòng, ép trạng thái (V01, V07, V08)
create or replace function public.create_order(
  p_customer_name text,
  p_phone text,
  p_address text,
  p_notes text default null,
  p_payment_method text default 'COD',
  p_coupon_code text default null,
  p_affiliate_code text default null,
  p_ref_source text default null,
  p_items jsonb default '[]'::jsonb,
  p_ref_click_id uuid default null,
  p_customer_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\s+', '', 'g');
  v_recent_count int;
  v_item jsonb;
  v_prod public.products;
  v_addon_price bigint;
  v_addon_label text;
  v_qty int;
  v_unit_price bigint;
  v_line_subtotal bigint;
  v_subtotal bigint := 0;
  v_coupon_res jsonb;
  v_discount_total bigint := 0;
  v_applied_coupon text := null;
  v_total_amount bigint := 0;
  v_aff public.affiliates;
  v_aff_id uuid := null;
  v_aff_code text := null;
  v_aff_warning text := null;
  v_self_referral boolean := false;
  v_order_code text;
  v_order_id uuid;
  v_summary_lines text[] := '{}';
  v_summary text := '';
  v_total_comm bigint := 0;
  v_weighted_rate numeric(5,2) := 0;
  v_item_rec record;
  v_alloc_disc bigint;
  v_net bigint;
  v_item_rate numeric(5,2);
  v_item_comm bigint;
  v_norm_phone text := regexp_replace(v_phone, '\D', '', 'g');
begin
  -- Validate đầu vào cơ bản
  if length(trim(coalesce(p_customer_name, ''))) < 2 then
    raise exception 'Vui lòng nhập họ và tên nhận hàng (ít nhất 2 ký tự).';
  end if;
  if v_phone !~ '^0[35789]\d{8}$' then
    raise exception 'Số điện thoại không hợp lệ (cần đúng 10 số Việt Nam).';
  end if;
  if length(trim(coalesce(p_address, ''))) < 5 then
    raise exception 'Vui lòng nhập đầy đủ địa chỉ nhận hàng / lắp đặt.';
  end if;
  if p_payment_method not in ('COD', 'VietQR') then
    raise exception 'Phương thức thanh toán không hợp lệ.';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Giỏ hàng trống, không thể tạo đơn.';
  end if;

  -- Chống spam cơ bản (T10): tối đa 5 đơn trong 10 phút cho cùng SĐT
  select count(*) into v_recent_count
  from public.orders
  where phone = v_phone and created_at >= now() - interval '10 minutes';
  if v_recent_count >= 5 then
    raise exception 'Bạn gửi quá nhiều yêu cầu trong thời gian ngắn. Vui lòng thử lại sau ít phút.';
  end if;

  -- Bước 1: Tính tạm tính từng dòng từ bảng products ở DB (không tin giá client!)
  create temp table if not exists _tmp_order_lines (
    product_id uuid,
    product_name text,
    material text,
    color text,
    form_label text,
    addons jsonb,
    vehicle jsonb,
    unit_price bigint,
    quantity int,
    line_subtotal bigint,
    commission_eligible boolean
  ) on commit drop;
  truncate _tmp_order_lines;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := coalesce((v_item->>'quantity')::int, 1);
    if v_qty <= 0 or v_qty > 50 then
      raise exception 'Số lượng sản phẩm không hợp lệ.';
    end if;

    select * into v_prod
    from public.products
    where is_active = true
      and product_type = 'mat'
      and (lower(name) = lower(trim(coalesce(v_item->>'material', '')))
           or upper(sku) = upper(trim(coalesce(v_item->>'sku', ''))))
    limit 1;

    if not found then
      raise exception 'Chất liệu thảm "%" không tồn tại hoặc đã ngừng bán.', coalesce(v_item->>'material', '');
    end if;

    -- Tính phụ kiện đi kèm từ DB
    v_addon_price := 0;
    if v_item ? 'addons' and jsonb_typeof(v_item->'addons') = 'array' then
      for v_addon_label in select jsonb_array_elements_text(v_item->'addons')
      loop
        select v_addon_price + coalesce(p.base_price, 0) into v_addon_price
        from public.products p
        where p.is_active = true
          and p.product_type = 'addon'
          and (lower(p.name) = lower(trim(v_addon_label)) or upper(p.sku) = upper(trim(v_addon_label)))
        limit 1;
      end loop;
    end if;

    v_unit_price := v_prod.base_price + v_addon_price;
    v_line_subtotal := v_unit_price * v_qty;
    v_subtotal := v_subtotal + v_line_subtotal;

    insert into _tmp_order_lines values (
      v_prod.id,
      coalesce(nullif(trim(v_item->>'name'), ''), v_prod.name),
      v_prod.name,
      nullif(trim(v_item->>'color'), ''),
      nullif(trim(v_item->>'formLabel'), ''),
      coalesce(v_item->'addons', '[]'::jsonb),
      v_item->'vehicle',
      v_unit_price,
      v_qty,
      v_line_subtotal,
      v_prod.commission_eligible
    );

    v_summary_lines := array_append(
      v_summary_lines,
      format('%sx %s (%s)',
        v_qty,
        coalesce(nullif(trim(v_item->>'name'), ''), v_prod.name),
        concat_ws(' | ',
          nullif(trim(coalesce(v_item->'vehicle'->>'brand', '') || ' ' || coalesce(v_item->'vehicle'->>'model', '')), ''),
          nullif(trim(v_item->>'formLabel'), ''),
          v_prod.name,
          nullif(trim(v_item->>'color'), '')
        )
      )
    );
  end loop;

  v_summary := array_to_string(v_summary_lines, E'\n');

  -- Bước 2: Kiểm tra mã giảm giá phía server
  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    v_coupon_res := public.validate_coupon(p_coupon_code, v_subtotal);
    if coalesce((v_coupon_res->>'valid')::boolean, false) then
      v_discount_total := (v_coupon_res->>'discount_amount')::bigint;
      v_applied_coupon := v_coupon_res->>'code';
      update public.coupons set used_count = used_count + 1 where code = v_applied_coupon;
    end if;
  end if;

  v_total_amount := greatest(0, v_subtotal - v_discount_total);

  -- Bước 3: Kiểm tra mã CTV & chống tự giới thiệu (Q4 / T32 / T33)
  if p_affiliate_code is not null and length(trim(p_affiliate_code)) > 0 then
    select * into v_aff
    from public.affiliates
    where code = upper(trim(p_affiliate_code))
      and status = 'active'
    limit 1;

    if found then
      v_aff_id := v_aff.id;
      v_aff_code := v_aff.code;
      if (auth.uid() is not null and v_aff.user_id = auth.uid())
         or (length(v_norm_phone) >= 9 and regexp_replace(coalesce(v_aff.phone, ''), '\D', '', 'g') = v_norm_phone)
         or (p_customer_email is not null and lower(trim(p_customer_email)) = lower(v_aff.email)) then
        v_self_referral := true;
      end if;
    else
      v_aff_warning := 'Mã giới thiệu không hợp lệ hoặc CTV chưa kích hoạt (đơn vẫn được tạo bình thường).';
    end if;
  end if;

  -- Sinh mã đơn khó đoán (V07): TT-YYMMDD-XXXXXX
  v_order_code := 'TT-' || to_char(now(), 'YYMMDD') || '-' || upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));

  -- Bước 4: Tạo bản ghi orders (ép status='new', payment_status='unpaid', commission_status='pending')
  insert into public.orders (
    order_code, customer_name, phone, customer_email, address, notes,
    payment_method, payment_status, coupon_code,
    subtotal, discount_amount, shipping_fee, total_amount,
    items, items_summary,
    affiliate_id, affiliate_code, ref_source, ref_click_id, attributed_at, self_referral,
    commission_rate, commission_amount, status, commission_status
  ) values (
    v_order_code, trim(p_customer_name), v_phone, nullif(trim(p_customer_email), ''), trim(p_address), nullif(trim(p_notes), ''),
    p_payment_method, 'unpaid', v_applied_coupon,
    v_subtotal, v_discount_total, 0, v_total_amount,
    p_items, v_summary,
    v_aff_id, v_aff_code,
    case when v_aff_id is not null then coalesce(nullif(p_ref_source, ''), 'manual') else null end,
    p_ref_click_id,
    case when v_aff_id is not null then now() else null end,
    v_self_referral,
    0, 0, 'new', 'pending'
  ) returning id into v_order_id;

  -- Bước 5: Lưu order_items + phân bổ giảm giá theo tỷ lệ & tính hoa hồng từng dòng (Q1)
  for v_item_rec in select * from _tmp_order_lines
  loop
    v_alloc_disc := case
      when v_subtotal > 0 and v_discount_total > 0 then floor((v_discount_total * v_item_rec.line_subtotal)::numeric / v_subtotal)
      else 0
    end;
    v_net := greatest(0, v_item_rec.line_subtotal - v_alloc_disc);

    if v_aff_id is not null and not v_self_referral and v_item_rec.commission_eligible then
      v_item_rate := public.resolve_commission_rate(v_item_rec.product_id, v_aff_id);
      v_item_comm := floor((v_net * v_item_rate) / 100.0);
    else
      v_item_rate := 0;
      v_item_comm := 0;
    end if;

    v_total_comm := v_total_comm + v_item_comm;

    insert into public.order_items (
      order_id, product_id, product_name, material, color, form_label, addons, vehicle,
      unit_price, quantity, line_subtotal, allocated_discount, net_amount,
      commission_eligible, commission_rate, commission_amount
    ) values (
      v_order_id, v_item_rec.product_id, v_item_rec.product_name, v_item_rec.material,
      v_item_rec.color, v_item_rec.form_label, v_item_rec.addons, v_item_rec.vehicle,
      v_item_rec.unit_price, v_item_rec.quantity, v_item_rec.line_subtotal, v_alloc_disc, v_net,
      v_item_rec.commission_eligible, v_item_rate, v_item_comm
    );
  end loop;

  if v_total_amount > 0 and v_total_comm > 0 then
    v_weighted_rate := round((v_total_comm * 100.0) / v_total_amount, 2);
  end if;

  update public.orders
  set commission_rate = v_weighted_rate,
      commission_amount = v_total_comm
  where id = v_order_id;

  return jsonb_build_object(
    'order_id', v_order_id,
    'order_code', v_order_code,
    'subtotal', v_subtotal,
    'discount_amount', v_discount_total,
    'total_amount', v_total_amount,
    'affiliate_code', v_aff_code,
    'self_referral', v_self_referral,
    'warning', v_aff_warning
  );
end;
$$;

revoke all on function public.create_order(text, text, text, text, text, text, text, text, jsonb, uuid, text) from public;
grant execute on function public.create_order(text, text, text, text, text, text, text, text, jsonb, uuid, text) to anon, authenticated;

-- 11. RPC create_lead (thay anon direct INSERT vào leads + chống spam)
create or replace function public.create_lead(
  p_customer_name text,
  p_phone text,
  p_vehicle text default null,
  p_message text default null,
  p_affiliate_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\s+', '', 'g');
  v_recent_count int;
  v_aff_code text := null;
  v_lead_id uuid;
begin
  if length(trim(coalesce(p_customer_name, ''))) < 2 then
    raise exception 'Vui lòng nhập họ tên của bạn.';
  end if;
  if v_phone !~ '^0[35789]\d{8}$' then
    raise exception 'Số điện thoại không hợp lệ.';
  end if;

  select count(*) into v_recent_count
  from public.leads
  where phone = v_phone and created_at >= now() - interval '10 minutes';
  if v_recent_count >= 5 then
    raise exception 'Bạn đã gửi quá nhiều yêu cầu liên tiếp. Vui lòng thử lại sau ít phút.';
  end if;

  if p_affiliate_code is not null and length(trim(p_affiliate_code)) > 0 then
    select code into v_aff_code
    from public.affiliates
    where code = upper(trim(p_affiliate_code)) and status = 'active'
    limit 1;
  end if;

  insert into public.leads (customer_name, phone, vehicle, message, affiliate_code, status)
  values (trim(p_customer_name), v_phone, nullif(trim(p_vehicle), ''), nullif(trim(p_message), ''), v_aff_code, 'new')
  returning id into v_lead_id;

  return jsonb_build_object('lead_id', v_lead_id, 'ok', true);
end;
$$;

revoke all on function public.create_lead(text, text, text, text, text) from public;
grant execute on function public.create_lead(text, text, text, text, text) to anon, authenticated;
