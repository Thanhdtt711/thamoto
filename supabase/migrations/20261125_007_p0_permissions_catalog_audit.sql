-- ============================================================
-- MIGRATION 007: Đồng bộ tên quyền (V-perm) + Catalog/Coupon/Rule/Setting ghi qua RPC có audit (V-catalog)
-- Thứ tự chạy: sau 006.
-- Nội dung:
--   1. Chuẩn hóa tên quyền staff: orders | payouts | affiliates | products | coupons
--      (tên cũ manage_orders / approve_commissions / pay_commissions / manage_affiliates được ánh xạ tự động).
--   2. Trigger chuẩn hóa + kiểm tra whitelist cột affiliates.permissions.
--   3. Gỡ policy ghi trực tiếp trên products / coupons / commission_rules / product_categories / app_settings,
--      thu hồi INSERT/UPDATE/DELETE của anon + authenticated; thay bằng RPC security definer có audit.
--   4. Quy tắc hoa hồng: KHÔNG xóa cứng, chỉ vô hiệu hóa (giữ lịch sử đối soát).
-- Rollback (tham khảo):
--   drop function if exists public.admin_save_product(uuid, text, text, bigint, int, boolean, text);
--   drop function if exists public.admin_save_coupon(uuid, text, text, numeric, bigint, bigint, int, timestamptz, boolean, text);
--   drop function if exists public.admin_save_commission_rule(uuid, uuid, uuid, numeric, boolean, timestamptz, timestamptz, text);
--   drop function if exists public.admin_update_setting(text, jsonb, text);
--   drop trigger if exists trg_normalize_affiliate_permissions on public.affiliates;
--   drop function if exists public.normalize_affiliate_permissions();
--   (khôi phục policy ghi cũ nếu cần: xem migration 002 mục RLS và 005 mục 10)
-- ============================================================

-- ------------------------------------------------------------
-- 1. Chuẩn hóa tên quyền
-- ------------------------------------------------------------
create or replace function public.canonical_permission(p_perm text)
returns text
language sql
immutable
as $$
  select case p_perm
    when 'manage_orders' then 'orders'
    when 'approve_commissions' then 'payouts'
    when 'pay_commissions' then 'payouts'
    when 'manage_affiliates' then 'affiliates'
    else p_perm
  end;
$$;

create or replace function public.has_permission(p_perm text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.affiliates
    where user_id = auth.uid()
      and status = 'active'
      and (
        role in ('admin', 'develop')
        or (
          role = 'staff'
          and permissions ?| array[public.canonical_permission(p_perm), p_perm]
        )
      )
  );
$$;

-- ------------------------------------------------------------
-- 2. Trigger chuẩn hóa + whitelist quyền
-- ------------------------------------------------------------
create or replace function public.normalize_affiliate_permissions()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_item text;
  v_canon text;
  v_out jsonb := '[]'::jsonb;
begin
  if new.permissions is null then
    new.permissions := '[]'::jsonb;
  end if;

  if jsonb_typeof(new.permissions) <> 'array' then
    raise exception 'permissions phải là mảng JSON';
  end if;

  for v_item in select jsonb_array_elements_text(new.permissions) loop
    v_canon := public.canonical_permission(v_item);
    if v_canon not in ('orders', 'payouts', 'affiliates', 'products', 'coupons') then
      raise exception 'Quyền không hợp lệ: %. Chỉ chấp nhận: orders, payouts, affiliates, products, coupons', v_item;
    end if;
    if not (v_out ? v_canon) then
      v_out := v_out || to_jsonb(v_canon);
    end if;
  end loop;

  new.permissions := v_out;
  return new;
end;
$$;

drop trigger if exists trg_normalize_affiliate_permissions on public.affiliates;
create trigger trg_normalize_affiliate_permissions
before insert or update of permissions on public.affiliates
for each row
execute function public.normalize_affiliate_permissions();

-- Backfill: chuẩn hóa quyền staff đã lưu theo tên cũ (bật cờ tin cậy để qua trigger guard)
do $$
begin
  perform set_config('app.trusted_rpc', 'develop_rpc', true);
  update public.affiliates
     set permissions = permissions
   where role = 'staff'
     and permissions is not null
     and permissions <> '[]'::jsonb;
  perform set_config('app.trusted_rpc', '', true);
end;
$$;

-- ------------------------------------------------------------
-- 3. Gỡ ghi trực tiếp, chỉ giữ quyền đọc
-- ------------------------------------------------------------
drop policy if exists "Admins manage categories" on public.product_categories;
drop policy if exists "admin_manage_categories" on public.product_categories;
drop policy if exists "Admins manage products" on public.products;
drop policy if exists "admin_manage_products" on public.products;
drop policy if exists "Admins manage coupons" on public.coupons;
drop policy if exists "admin_manage_coupons" on public.coupons;
drop policy if exists "Admins manage commission rules" on public.commission_rules;
drop policy if exists "admin_manage_commission_rules" on public.commission_rules;
drop policy if exists "Admins can update app settings" on public.app_settings;

drop policy if exists "staff_read_categories" on public.product_categories;
create policy "staff_read_categories"
on public.product_categories for select
to authenticated
using (public.has_permission('products'));

drop policy if exists "staff_read_products" on public.products;
create policy "staff_read_products"
on public.products for select
to authenticated
using (public.has_permission('products'));

drop policy if exists "staff_read_coupons" on public.coupons;
create policy "staff_read_coupons"
on public.coupons for select
to authenticated
using (public.has_permission('coupons'));

drop policy if exists "staff_read_commission_rules" on public.commission_rules;
create policy "staff_read_commission_rules"
on public.commission_rules for select
to authenticated
using (public.has_permission('products'));

revoke insert, update, delete on
  public.products,
  public.product_categories,
  public.coupons,
  public.commission_rules,
  public.app_settings
from anon, authenticated;

-- ------------------------------------------------------------
-- 4. RPC: Sản phẩm
-- ------------------------------------------------------------
create or replace function public.admin_save_product(
  p_id uuid,
  p_sku text,
  p_name text,
  p_base_price bigint,
  p_stock_qty int default null,
  p_is_active boolean default true,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.products;
  v_new public.products;
  v_sku text := upper(trim(coalesce(p_sku, '')));
begin
  if auth.uid() is null or not public.has_permission('products') then
    raise exception 'Bạn không có quyền quản lý sản phẩm';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception 'Tên sản phẩm không được để trống';
  end if;
  if p_base_price is null or p_base_price < 0 then
    raise exception 'Giá sản phẩm phải lớn hơn hoặc bằng 0';
  end if;
  if p_stock_qty is not null and p_stock_qty < 0 then
    raise exception 'Tồn kho không được âm';
  end if;

  if p_id is null then
    if v_sku !~ '^[A-Z0-9][A-Z0-9_-]{1,39}$' then
      raise exception 'SKU không hợp lệ (chỉ A-Z, 0-9, dấu - và _, dài 2-40 ký tự)';
    end if;

    begin
      insert into public.products (sku, category_id, name, product_type, base_price, stock_qty, is_active)
      values (
        v_sku,
        (select id from public.product_categories where slug = 'tham-san'),
        trim(p_name),
        'mat',
        p_base_price,
        p_stock_qty,
        coalesce(p_is_active, true)
      )
      returning * into v_new;
    exception when unique_violation then
      raise exception 'SKU % đã tồn tại', v_sku;
    end;

    perform public.write_audit_log('admin_create_product', 'products', v_new.id::text, null, to_jsonb(v_new), p_reason);
  else
    select * into v_old from public.products where id = p_id for update;
    if not found then
      raise exception 'Không tìm thấy sản phẩm';
    end if;

    update public.products
       set name = trim(p_name),
           base_price = p_base_price,
           stock_qty = p_stock_qty,
           is_active = coalesce(p_is_active, is_active),
           updated_at = now()
     where id = p_id
     returning * into v_new;

    perform public.write_audit_log('admin_update_product', 'products', p_id::text, to_jsonb(v_old), to_jsonb(v_new), p_reason);
  end if;

  return to_jsonb(v_new);
end;
$$;

revoke all on function public.admin_save_product(uuid, text, text, bigint, int, boolean, text) from public;
grant execute on function public.admin_save_product(uuid, text, text, bigint, int, boolean, text) to authenticated;

-- ------------------------------------------------------------
-- 5. RPC: Mã giảm giá
-- ------------------------------------------------------------
create or replace function public.admin_save_coupon(
  p_id uuid,
  p_code text,
  p_discount_type text,
  p_discount_value numeric,
  p_min_order_amount bigint default 0,
  p_max_discount_amount bigint default null,
  p_usage_limit int default null,
  p_expires_at timestamptz default null,
  p_is_active boolean default true,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.coupons;
  v_new public.coupons;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  if auth.uid() is null or not public.has_permission('coupons') then
    raise exception 'Bạn không có quyền quản lý mã giảm giá';
  end if;

  if p_discount_type is null or p_discount_type not in ('fixed', 'percent') then
    raise exception 'Loại giảm giá không hợp lệ';
  end if;
  if p_discount_value is null or p_discount_value <= 0 then
    raise exception 'Giá trị giảm phải lớn hơn 0';
  end if;
  if p_discount_type = 'percent' and p_discount_value > 100 then
    raise exception 'Giảm theo phần trăm không được vượt quá 100';
  end if;
  if coalesce(p_min_order_amount, 0) < 0 then
    raise exception 'Đơn tối thiểu không được âm';
  end if;
  if p_max_discount_amount is not null and p_max_discount_amount <= 0 then
    raise exception 'Mức giảm tối đa phải lớn hơn 0 (để trống nếu không giới hạn)';
  end if;
  if p_usage_limit is not null and p_usage_limit <= 0 then
    raise exception 'Giới hạn lượt dùng phải lớn hơn 0 (để trống nếu không giới hạn)';
  end if;

  if p_id is null then
    if v_code !~ '^[A-Z0-9_-]{3,30}$' then
      raise exception 'Mã giảm giá không hợp lệ (A-Z, 0-9, - hoặc _, dài 3-30 ký tự)';
    end if;

    begin
      insert into public.coupons (
        code, discount_type, discount_value, min_order_amount, max_discount_amount,
        usage_limit, expires_at, is_active
      ) values (
        v_code, p_discount_type, p_discount_value, coalesce(p_min_order_amount, 0), p_max_discount_amount,
        p_usage_limit, p_expires_at, coalesce(p_is_active, true)
      )
      returning * into v_new;
    exception when unique_violation then
      raise exception 'Mã giảm giá % đã tồn tại', v_code;
    end;

    perform public.write_audit_log('admin_create_coupon', 'coupons', v_new.id::text, null, to_jsonb(v_new), p_reason);
  else
    select * into v_old from public.coupons where id = p_id for update;
    if not found then
      raise exception 'Không tìm thấy mã giảm giá';
    end if;

    if p_usage_limit is not null and p_usage_limit < v_old.used_count then
      raise exception 'Giới hạn lượt dùng không được nhỏ hơn số lượt đã dùng (%)', v_old.used_count;
    end if;

    update public.coupons
       set discount_type = p_discount_type,
           discount_value = p_discount_value,
           min_order_amount = coalesce(p_min_order_amount, 0),
           max_discount_amount = p_max_discount_amount,
           usage_limit = p_usage_limit,
           expires_at = p_expires_at,
           is_active = coalesce(p_is_active, is_active)
     where id = p_id
     returning * into v_new;

    perform public.write_audit_log('admin_update_coupon', 'coupons', p_id::text, to_jsonb(v_old), to_jsonb(v_new), p_reason);
  end if;

  return to_jsonb(v_new);
end;
$$;

revoke all on function public.admin_save_coupon(uuid, text, text, numeric, bigint, bigint, int, timestamptz, boolean, text) from public;
grant execute on function public.admin_save_coupon(uuid, text, text, numeric, bigint, bigint, int, timestamptz, boolean, text) to authenticated;

-- ------------------------------------------------------------
-- 6. RPC: Quy tắc hoa hồng (chỉ admin/develop; không xóa cứng)
-- ------------------------------------------------------------
create or replace function public.admin_save_commission_rule(
  p_id uuid,
  p_product_id uuid,
  p_affiliate_id uuid,
  p_rate numeric,
  p_is_active boolean default true,
  p_valid_from timestamptz default null,
  p_valid_to timestamptz default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.commission_rules;
  v_new public.commission_rules;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Chỉ Admin mới được thay đổi quy tắc hoa hồng';
  end if;

  if p_rate is null or p_rate < 0 or p_rate > 50 then
    raise exception 'Tỷ lệ hoa hồng phải từ 0 đến 50';
  end if;
  if p_valid_from is not null and p_valid_to is not null and p_valid_to <= p_valid_from then
    raise exception 'Thời điểm hết hiệu lực phải sau thời điểm bắt đầu';
  end if;

  if p_id is null then
    insert into public.commission_rules (product_id, affiliate_id, rate, is_active, valid_from, valid_to)
    values (p_product_id, p_affiliate_id, p_rate, coalesce(p_is_active, true), p_valid_from, p_valid_to)
    returning * into v_new;

    perform public.write_audit_log('admin_create_commission_rule', 'commission_rules', v_new.id::text, null, to_jsonb(v_new), p_reason);
  else
    select * into v_old from public.commission_rules where id = p_id for update;
    if not found then
      raise exception 'Không tìm thấy quy tắc hoa hồng';
    end if;

    update public.commission_rules
       set product_id = p_product_id,
           affiliate_id = p_affiliate_id,
           rate = p_rate,
           is_active = coalesce(p_is_active, is_active),
           valid_from = p_valid_from,
           valid_to = p_valid_to
     where id = p_id
     returning * into v_new;

    perform public.write_audit_log(
      case when v_old.is_active and not v_new.is_active then 'admin_deactivate_commission_rule' else 'admin_update_commission_rule' end,
      'commission_rules', p_id::text, to_jsonb(v_old), to_jsonb(v_new), p_reason
    );
  end if;

  return to_jsonb(v_new);
end;
$$;

revoke all on function public.admin_save_commission_rule(uuid, uuid, uuid, numeric, boolean, timestamptz, timestamptz, text) from public;
grant execute on function public.admin_save_commission_rule(uuid, uuid, uuid, numeric, boolean, timestamptz, timestamptz, text) to authenticated;

-- ------------------------------------------------------------
-- 7. RPC: Cài đặt hệ thống (chỉ admin/develop, có kiểm tra khoảng giá trị)
-- ------------------------------------------------------------
create or replace function public.admin_update_setting(
  p_key text,
  p_value jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.app_settings;
  v_new public.app_settings;
  v_num numeric;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'Chỉ Admin mới được thay đổi cấu hình hệ thống';
  end if;

  select * into v_old from public.app_settings where key = p_key for update;
  if not found then
    raise exception 'Không tồn tại cấu hình %', p_key;
  end if;

  if p_key in (
    'default_commission_rate', 'commission_hold_days', 'attribution_ttl_days',
    'min_payout_amount', 'payout_weekday', 'tax_withholding_rate', 'tax_threshold_per_payment'
  ) then
    if p_value is null or jsonb_typeof(p_value) <> 'number' then
      raise exception 'Giá trị của % phải là số', p_key;
    end if;
    v_num := (p_value #>> '{}')::numeric;

    if p_key = 'default_commission_rate' and (v_num < 0 or v_num > 50) then
      raise exception 'default_commission_rate phải từ 0 đến 50';
    elsif p_key = 'commission_hold_days' and (v_num < 0 or v_num > 90 or v_num <> trunc(v_num)) then
      raise exception 'commission_hold_days phải là số nguyên từ 0 đến 90';
    elsif p_key = 'attribution_ttl_days' and (v_num < 1 or v_num > 365 or v_num <> trunc(v_num)) then
      raise exception 'attribution_ttl_days phải là số nguyên từ 1 đến 365';
    elsif p_key = 'min_payout_amount' and (v_num < 0 or v_num > 100000000) then
      raise exception 'min_payout_amount phải từ 0 đến 100.000.000';
    elsif p_key = 'payout_weekday' and (v_num < 1 or v_num > 7 or v_num <> trunc(v_num)) then
      raise exception 'payout_weekday phải là số nguyên từ 1 đến 7';
    elsif p_key = 'tax_withholding_rate' and (v_num < 0 or v_num > 35) then
      raise exception 'tax_withholding_rate phải từ 0 đến 35';
    elsif p_key = 'tax_threshold_per_payment' and v_num < 0 then
      raise exception 'tax_threshold_per_payment không được âm';
    end if;
  end if;

  update public.app_settings
     set value = p_value,
         updated_at = now(),
         updated_by = auth.uid()
   where key = p_key
   returning * into v_new;

  perform public.write_audit_log('admin_update_setting', 'app_settings', p_key, to_jsonb(v_old), to_jsonb(v_new), p_reason);

  return to_jsonb(v_new);
end;
$$;

revoke all on function public.admin_update_setting(text, jsonb, text) from public;
grant execute on function public.admin_update_setting(text, jsonb, text) to authenticated;
