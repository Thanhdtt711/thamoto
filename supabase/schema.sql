-- ============================================================
-- Supabase Schema: Trung Thành Auto (Orders + Leads + Affiliates)
-- Chạy toàn bộ file này trong Supabase Dashboard -> SQL Editor
-- ============================================================

create extension if not exists "pgcrypto";

-- 1. Bảng Cộng tác viên & Quản trị viên
create table if not exists public.affiliates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid unique references auth.users(id) on delete cascade,
  code text unique not null,
  full_name text not null,
  email text not null,
  phone text not null,
  zalo text,
  area text,
  job_type text default 'Bán online',
  role text not null default 'ctv' check (role in ('ctv', 'admin', 'develop')),
  commission_rate numeric(5,2) not null default 10.00 check (commission_rate >= 0 and commission_rate <= 50),
  status text not null default 'pending' check (status in ('pending', 'active', 'suspended', 'cancelled')),
  created_at timestamptz not null default now()
);

-- 2. Bảng Đơn đặt hàng
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_code text unique not null,
  customer_name text not null,
  phone text not null,
  address text not null,
  notes text,
  payment_method text not null default 'COD' check (payment_method in ('COD', 'VietQR')),
  coupon_code text,
  total_amount bigint not null check (total_amount >= 0),
  items jsonb not null default '[]'::jsonb,
  items_summary text not null default '',
  affiliate_code text,
  commission_rate numeric(5,2) not null default 0,
  commission_amount bigint not null default 0,
  status text not null default 'new' check (status in ('new', 'confirmed', 'shipping', 'completed', 'cancelled')),
  commission_status text not null default 'pending' check (commission_status in ('pending', 'approved', 'paid')),
  created_at timestamptz not null default now()
);

-- 3. Bảng Yêu cầu tư vấn / Đo phom xe riêng
create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  customer_name text not null,
  phone text not null,
  vehicle text,
  message text,
  affiliate_code text,
  status text not null default 'new' check (status in ('new', 'contacted', 'closed')),
  created_at timestamptz not null default now()
);

-- 3b. Bảng Lịch sử đối soát & thanh toán hoa hồng cho CTV
create table if not exists public.commission_payouts (
  id uuid primary key default gen_random_uuid(),
  affiliate_code text not null,
  amount bigint not null check (amount > 0),
  order_count int not null default 0,
  note text,
  paid_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

-- Index tối ưu truy vấn
create index if not exists idx_orders_affiliate_code on public.orders(affiliate_code);
create index if not exists idx_orders_created_at on public.orders(created_at desc);
create index if not exists idx_leads_created_at on public.leads(created_at desc);
create index if not exists idx_affiliates_code on public.affiliates(code);
create index if not exists idx_payouts_affiliate_code on public.commission_payouts(affiliate_code);

-- 4. Trigger tự động tính hoa hồng trên server khi có đơn mới
create or replace function public.calc_order_commission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rate numeric(5,2);
begin
  if new.affiliate_code is not null and length(trim(new.affiliate_code)) > 0 then
    new.affiliate_code := upper(trim(new.affiliate_code));
    select commission_rate into v_rate
    from public.affiliates
    where upper(code) = new.affiliate_code
      and status = 'active'
    limit 1;

    if v_rate is not null then
      new.commission_rate := v_rate;
      new.commission_amount := round((new.total_amount * v_rate) / 100.0);
    else
      new.commission_rate := 0;
      new.commission_amount := 0;
    end if;
  else
    new.affiliate_code := null;
    new.commission_rate := 0;
    new.commission_amount := 0;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_orders_calc_commission on public.orders;
create trigger trg_orders_calc_commission
before insert on public.orders
for each row
execute function public.calc_order_commission();

-- 4b. Trigger tự tạo hồ sơ CTV khi user đăng ký qua Supabase Auth (hoạt động kể cả khi bật Confirm email)
create or replace function public.handle_new_affiliate_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_full_name text;
  v_phone text;
  v_area text;
  v_job_type text;
begin
  v_full_name := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1));
  v_phone := coalesce(nullif(trim(new.raw_user_meta_data->>'phone'), ''), '');
  v_area := nullif(trim(new.raw_user_meta_data->>'area'), '');
  v_job_type := coalesce(nullif(trim(new.raw_user_meta_data->>'job_type'), ''), 'Bán online');
  v_code := upper(regexp_replace(coalesce(new.raw_user_meta_data->>'code', ''), '[^A-Za-z0-9_-]', '', 'g'));

  if length(v_code) < 3 then
    v_code := 'CTV' || upper(substr(replace(new.id::text, '-', ''), 1, 5));
  end if;

  if exists (select 1 from public.affiliates where upper(code) = v_code) then
    v_code := v_code || upper(substr(replace(new.id::text, '-', ''), 1, 3));
  end if;

  insert into public.affiliates (user_id, code, full_name, email, phone, zalo, area, job_type, role, status)
  values (new.id, v_code, v_full_name, new.email, v_phone, v_phone, v_area, v_job_type, 'ctv', 'pending')
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_affiliate_user();

-- 5. Helper kiểm tra quyền Admin / Develop & lấy mã CTV hiện tại (tránh đệ quy RLS)
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.affiliates
    where user_id = auth.uid()
      and role in ('admin', 'develop')
      and status = 'active'
  );
$$;

create or replace function public.is_develop()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.affiliates
    where user_id = auth.uid()
      and role = 'develop'
      and status = 'active'
  );
$$;

-- RPC chỉ dành cho Develop: kích hoạt & gán vai trò (admin/ctv/develop) ngay sau khi tạo tài khoản
create or replace function public.develop_set_account_role(
  p_email text,
  p_role text,
  p_status text default 'active',
  p_commission_rate numeric default 10.00
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_develop() then
    raise exception 'Chỉ tài khoản Develop mới có quyền thực hiện thao tác này';
  end if;

  if p_role not in ('ctv', 'admin', 'develop') then
    raise exception 'Vai trò không hợp lệ';
  end if;

  update auth.users
  set email_confirmed_at = coalesce(email_confirmed_at, now())
  where lower(email) = lower(trim(p_email));

  update public.affiliates
  set role = p_role,
      status = p_status,
      commission_rate = coalesce(p_commission_rate, commission_rate)
  where lower(email) = lower(trim(p_email));
end;
$$;

create or replace function public.current_affiliate_code()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select upper(code) from public.affiliates
  where user_id = auth.uid()
    and status = 'active'
  limit 1;
$$;

-- 6. Bật Row Level Security (RLS)
alter table public.affiliates enable row level security;
alter table public.orders enable row level security;
alter table public.leads enable row level security;
alter table public.commission_payouts enable row level security;

-- Policies: affiliates
drop policy if exists "Affiliates can insert own signup" on public.affiliates;
create policy "Affiliates can insert own signup"
  on public.affiliates for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and role = 'ctv'
    and status = 'pending'
  );

drop policy if exists "Affiliates can view own profile" on public.affiliates;
create policy "Affiliates can view own profile"
  on public.affiliates for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "Admins can update affiliates" on public.affiliates;
create policy "Admins can update affiliates"
  on public.affiliates for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Policies: orders
drop policy if exists "Anyone can place orders" on public.orders;
create policy "Anyone can place orders"
  on public.orders for insert
  to anon, authenticated
  with check (true);

drop policy if exists "CTV views own orders and Admin views all" on public.orders;
create policy "CTV views own orders and Admin views all"
  on public.orders for select
  to authenticated
  using (
    public.is_admin()
    or (
      public.current_affiliate_code() is not null
      and upper(affiliate_code) = public.current_affiliate_code()
    )
  );

drop policy if exists "Admins can update orders" on public.orders;
create policy "Admins can update orders"
  on public.orders for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Policies: leads
drop policy if exists "Anyone can submit leads" on public.leads;
create policy "Anyone can submit leads"
  on public.leads for insert
  to anon, authenticated
  with check (true);

drop policy if exists "CTV views own leads and Admin views all" on public.leads;
create policy "CTV views own leads and Admin views all"
  on public.leads for select
  to authenticated
  using (
    public.is_admin()
    or (
      public.current_affiliate_code() is not null
      and upper(affiliate_code) = public.current_affiliate_code()
    )
  );

drop policy if exists "Admins can update leads" on public.leads;
create policy "Admins can update leads"
  on public.leads for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Policies: commission_payouts
drop policy if exists "CTV views own payouts and Admin views all" on public.commission_payouts;
create policy "CTV views own payouts and Admin views all"
  on public.commission_payouts for select
  to authenticated
  using (
    public.is_admin()
    or (
      public.current_affiliate_code() is not null
      and upper(affiliate_code) = public.current_affiliate_code()
    )
  );

drop policy if exists "Admins can insert payouts" on public.commission_payouts;
create policy "Admins can insert payouts"
  on public.commission_payouts for insert
  to authenticated
  with check (public.is_admin());

drop policy if exists "Admins can update payouts" on public.commission_payouts;
create policy "Admins can update payouts"
  on public.commission_payouts for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ============================================================
-- HƯỚNG DẪN TẠO TÀI KHOẢN ADMIN (CTV CẤP 1) SAU KHI ĐĂNG KÝ:
-- 1. Vào /cong-tac-vien.html đăng ký tài khoản bằng email của bạn.
-- 2. Chạy lệnh SQL sau (thay email của bạn vào):
--    update public.affiliates
--    set role = 'admin', status = 'active', code = 'ADMIN01'
--    where email = 'dothanh0711@gmail.com';
-- ============================================================

-- === CUMULATIVE MIGRATIONS SNAPSHOT ===
-- Đồng bộ tự động từ supabase/migrations/20261125_001..006


-- [MIGRATION: 20261125_001_p0_settings_audit_security.sql]
-- ============================================================
-- Migration: 20261125_001_p0_settings_audit_security.sql
-- Phạm vi: P0-2 (Siết quyền affiliates, chống leo thang V02)
--        + P0-7 (Bảng app_settings, bảng audit_logs bất biến, trigger audit V09)
--        + Nền tảng P1-8 (vai trò staff + cột permissions)
-- Thứ tự chạy: 001 (sau khi chạy 000 kiểm tra dữ liệu)
-- Điều kiện tiên quyết: Đã có schema gốc (affiliates, orders, leads, commission_payouts)
--
-- ROLLBACK (chạy thủ công nếu cần hoàn tác):
--   drop trigger if exists trg_guard_affiliates_sensitive on public.affiliates;
--   drop trigger if exists trg_audit_affiliates on public.affiliates;
--   drop trigger if exists trg_audit_orders on public.orders;
--   drop trigger if exists trg_audit_payouts on public.commission_payouts;
--   drop function if exists public.admin_update_affiliate(uuid, text, numeric, text, jsonb);
--   drop function if exists public.has_permission(text);
--   drop function if exists public.write_audit_log(text, text, text, jsonb, jsonb);
--   drop table if exists public.audit_logs;
--   drop table if exists public.app_settings;
-- ============================================================

-- 1. Bảng cấu hình hệ thống (app_settings) theo QUYET-DINH-Q1-Q6.md
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.app_settings (key, value, description) values
  ('default_commission_rate', '10'::jsonb, 'Tỷ lệ hoa hồng mặc định (%) khi không có rule riêng theo sản phẩm hoặc CTV'),
  ('commission_hold_days', '7'::jsonb, 'Số ngày giữ hoa hồng sau khi đơn chuyển completed trước khi mở khóa available'),
  ('attribution_ttl_days', '30'::jsonb, 'Thời hạn lưu mã giới thiệu (ngày) theo quy tắc last-click'),
  ('min_payout_amount', '200000'::jsonb, 'Hạn mức rút tiền tối thiểu (VND)'),
  ('payout_weekday', '1'::jsonb, 'Ngày chi trả gộp hàng tuần (1 = Thứ Hai .. 7 = Chủ Nhật)'),
  ('tax_withholding_rate', '0'::jsonb, 'Tỷ lệ khấu trừ thuế TNCN (%) - mặc định 0, chỉ bật khi kế toán xác nhận'),
  ('tax_threshold_per_payment', '0'::jsonb, 'Ngưỡng mỗi lần chi trả áp dụng khấu trừ thuế (VND)')
on conflict (key) do nothing;

create or replace function public.get_setting_numeric(p_key text, p_default numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select (value #>> '{}')::numeric from public.app_settings where key = p_key), p_default);
$$;

alter table public.app_settings enable row level security;

drop policy if exists "Anyone can read non-sensitive app settings" on public.app_settings;
create policy "Anyone can read non-sensitive app settings"
  on public.app_settings for select
  to anon, authenticated
  using (true);

drop policy if exists "Admins can update app settings" on public.app_settings;
create policy "Admins can update app settings"
  on public.app_settings for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 2. Bảng Nhật ký hoạt động (audit_logs) - APPEND-ONLY bất biến
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  actor_role text,
  action text not null,
  table_name text not null,
  record_id text not null,
  old_data jsonb,
  new_data jsonb,
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_created_at on public.audit_logs(created_at desc);
create index if not exists idx_audit_logs_table_record on public.audit_logs(table_name, record_id);
create index if not exists idx_audit_logs_actor on public.audit_logs(actor_id, created_at desc);

create or replace function public.block_immutable_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Bảng % là bất biến (append-only), không được phép %', tg_table_name, tg_op;
end;
$$;

drop trigger if exists trg_audit_logs_immutable on public.audit_logs;
create trigger trg_audit_logs_immutable
before update or delete on public.audit_logs
for each row
execute function public.block_immutable_mutation();

alter table public.audit_logs enable row level security;

drop policy if exists "Admins can view audit logs" on public.audit_logs;
create policy "Admins can view audit logs"
  on public.audit_logs for select
  to authenticated
  using (public.is_admin());

-- Helper ghi audit log (dùng trong trigger/RPC)
create or replace function public.write_audit_log(
  p_action text,
  p_table_name text,
  p_record_id text,
  p_old_data jsonb default null,
  p_new_data jsonb default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role text;
begin
  if v_actor is not null then
    select role into v_role from public.affiliates where user_id = v_actor limit 1;
  end if;

  insert into public.audit_logs (actor_id, actor_role, action, table_name, record_id, old_data, new_data, reason)
  values (v_actor, coalesce(v_role, 'system'), p_action, p_table_name, p_record_id, p_old_data, p_new_data, p_reason);
end;
$$;

-- 3. Mở rộng bảng affiliates (hỗ trợ staff, permissions, duyệt/từ chối có lý do)
alter table public.affiliates
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists reject_reason text,
  add column if not exists permissions jsonb not null default '[]'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

alter table public.affiliates drop constraint if exists affiliates_role_check;
alter table public.affiliates
  add constraint affiliates_role_check check (role in ('ctv', 'staff', 'admin', 'develop'));

-- Mở rộng orders thêm updated_at, updated_by
alter table public.orders
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by uuid references auth.users(id);

-- 4. Helper kiểm tra quyền chi tiết (hỗ trợ staff + admin + develop)
create or replace function public.is_staff_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.affiliates
    where user_id = auth.uid()
      and role in ('staff', 'admin', 'develop')
      and status = 'active'
  );
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
        or (role = 'staff' and permissions ? p_perm)
      )
  );
$$;

-- 5. Chặn Admin/Client sửa trực tiếp các cột nhạy cảm trên affiliates (fix V02)
-- Chỉ cho phép sửa role/user_id/code/email khi có cờ transaction-local từ RPC của develop
create or replace function public.guard_affiliates_sensitive_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trusted text := current_setting('app.trusted_rpc', true);
begin
  new.updated_at := now();
  new.code := upper(trim(new.code));

  if v_trusted is distinct from 'develop_rpc' then
    if new.role is distinct from old.role
       or new.user_id is distinct from old.user_id
       or new.email is distinct from old.email
       or new.code is distinct from old.code then
      raise exception 'Không được phép sửa trực tiếp role, user_id, email hoặc code. Vui lòng dùng RPC hợp lệ.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_affiliates_sensitive on public.affiliates;
create trigger trg_guard_affiliates_sensitive
before update on public.affiliates
for each row
execute function public.guard_affiliates_sensitive_columns();

-- Bỏ policy UPDATE trực tiếp quá rộng trên affiliates (V02)
drop policy if exists "Admins can update affiliates" on public.affiliates;

-- 6. RPC admin_update_affiliate: whitelist cột được phép sửa + ghi audit log
create or replace function public.admin_update_affiliate(
  p_affiliate_id uuid,
  p_status text default null,
  p_commission_rate numeric default null,
  p_reject_reason text default null,
  p_permissions jsonb default null
)
returns public.affiliates
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.affiliates;
  v_new public.affiliates;
begin
  if not public.has_permission('manage_affiliates') then
    raise exception 'Bạn không có quyền quản lý CTV';
  end if;

  select * into v_old from public.affiliates where id = p_affiliate_id for update;
  if not found then
    raise exception 'Không tìm thấy hồ sơ CTV';
  end if;

  if v_old.user_id = auth.uid() and p_status is not null and p_status <> 'active' then
    raise exception 'Không thể tự khóa hoặc hủy tài khoản của chính mình';
  end if;

  if v_old.role = 'develop' and not public.is_develop() then
    raise exception 'Admin không được phép chỉnh sửa tài khoản Develop';
  end if;

  if p_status is not null and p_status not in ('pending', 'active', 'suspended', 'cancelled') then
    raise exception 'Trạng thái CTV không hợp lệ';
  end if;

  if p_commission_rate is not null and (p_commission_rate < 0 or p_commission_rate > 50) then
    raise exception 'Tỷ lệ hoa hồng phải từ 0 đến 50%%';
  end if;

  update public.affiliates
  set status = coalesce(p_status, status),
      commission_rate = coalesce(p_commission_rate, commission_rate),
      reject_reason = case
        when p_status in ('suspended', 'cancelled') then coalesce(nullif(trim(p_reject_reason), ''), reject_reason)
        when p_status = 'active' then null
        else reject_reason
      end,
      approved_at = case when p_status = 'active' and v_old.status <> 'active' then now() else approved_at end,
      approved_by = case when p_status = 'active' and v_old.status <> 'active' then auth.uid() else approved_by end,
      permissions = case when p_permissions is not null and public.is_admin() then p_permissions else permissions end
  where id = p_affiliate_id
  returning * into v_new;

  perform public.write_audit_log(
    'admin_update_affiliate',
    'affiliates',
    p_affiliate_id::text,
    jsonb_build_object('status', v_old.status, 'commission_rate', v_old.commission_rate, 'reject_reason', v_old.reject_reason, 'permissions', v_old.permissions),
    jsonb_build_object('status', v_new.status, 'commission_rate', v_new.commission_rate, 'reject_reason', v_new.reject_reason, 'permissions', v_new.permissions),
    p_reject_reason
  );

  return v_new;
end;
$$;

revoke all on function public.admin_update_affiliate(uuid, text, numeric, text, jsonb) from public, anon;
grant execute on function public.admin_update_affiliate(uuid, text, numeric, text, jsonb) to authenticated;

-- 7. Siết chặt develop_set_account_role: chặn tự hạ quyền / hạ develop cuối cùng (T12) + audit log
create or replace function public.develop_set_account_role(
  p_email text,
  p_role text,
  p_status text default 'active',
  p_commission_rate numeric default 10.00
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target public.affiliates;
  v_dev_count int;
begin
  if not public.is_develop() then
    raise exception 'Chỉ tài khoản Develop mới có quyền thực hiện thao tác này';
  end if;

  if p_role not in ('ctv', 'staff', 'admin', 'develop') then
    raise exception 'Vai trò không hợp lệ';
  end if;

  if p_status not in ('pending', 'active', 'suspended', 'cancelled') then
    raise exception 'Trạng thái không hợp lệ';
  end if;

  select * into v_target from public.affiliates where lower(email) = lower(trim(p_email)) for update;
  if not found then
    raise exception 'Không tìm thấy tài khoản với email %', p_email;
  end if;

  -- Chặn Develop tự hạ quyền chính mình (T12)
  if v_target.user_id = auth.uid() and (p_role <> 'develop' or p_status <> 'active') then
    raise exception 'Không thể tự hạ quyền hoặc khóa chính tài khoản Develop của bạn';
  end if;

  -- Chặn hạ quyền Develop cuối cùng đang hoạt động (T12)
  if v_target.role = 'develop' and (p_role <> 'develop' or p_status <> 'active') then
    select count(*) into v_dev_count from public.affiliates where role = 'develop' and status = 'active';
    if v_dev_count <= 1 then
      raise exception 'Không thể hạ quyền tài khoản Develop cuối cùng của hệ thống';
    end if;
  end if;

  perform set_config('app.trusted_rpc', 'develop_rpc', true);

  update auth.users
  set email_confirmed_at = coalesce(email_confirmed_at, now())
  where lower(email) = lower(trim(p_email));

  update public.affiliates
  set role = p_role,
      status = p_status,
      commission_rate = coalesce(p_commission_rate, commission_rate),
      approved_at = case when p_status = 'active' and v_target.status <> 'active' then now() else approved_at end,
      approved_by = case when p_status = 'active' and v_target.status <> 'active' then auth.uid() else approved_by end
  where id = v_target.id;

  perform public.write_audit_log(
    'develop_set_account_role',
    'affiliates',
    v_target.id::text,
    jsonb_build_object('role', v_target.role, 'status', v_target.status, 'commission_rate', v_target.commission_rate),
    jsonb_build_object('role', p_role, 'status', p_status, 'commission_rate', coalesce(p_commission_rate, v_target.commission_rate)),
    null
  );
end;
$$;

revoke all on function public.develop_set_account_role(text, text, text, numeric) from public, anon;
grant execute on function public.develop_set_account_role(text, text, text, numeric) to authenticated;

-- Chặn từ khóa cấm khi đăng ký CTV mới (V11 / T34) + chuẩn hóa chữ hoa
create or replace function public.handle_new_affiliate_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_full_name text;
  v_phone text;
  v_area text;
  v_job_type text;
  v_default_rate numeric;
begin
  v_full_name := coalesce(nullif(trim(new.raw_user_meta_data->>'full_name'), ''), split_part(new.email, '@', 1));
  v_phone := coalesce(nullif(trim(new.raw_user_meta_data->>'phone'), ''), '');
  v_area := nullif(trim(new.raw_user_meta_data->>'area'), '');
  v_job_type := coalesce(nullif(trim(new.raw_user_meta_data->>'job_type'), ''), 'Bán online');
  v_code := upper(regexp_replace(coalesce(new.raw_user_meta_data->>'code', ''), '[^A-Za-z0-9_-]', '', 'g'));
  v_default_rate := public.get_setting_numeric('default_commission_rate', 10.00);

  if length(v_code) < 3 or v_code in ('ADMIN', 'ROOT', 'DEVELOP', 'SYSTEM', 'STAFF', 'SUPPORT', 'TRUNGTHANH') then
    v_code := 'CTV' || upper(substr(replace(new.id::text, '-', ''), 1, 5));
  end if;

  if exists (select 1 from public.affiliates where code = v_code) then
    v_code := v_code || upper(substr(replace(new.id::text, '-', ''), 1, 3));
  end if;

  insert into public.affiliates (user_id, code, full_name, email, phone, zalo, area, job_type, role, commission_rate, status)
  values (new.id, v_code, v_full_name, new.email, v_phone, v_phone, v_area, v_job_type, 'ctv', v_default_rate, 'pending')
  on conflict (user_id) do nothing;

  return new;
end;
$$;

-- [MIGRATION: 20261125_002_p0_catalog_coupons_create_order.sql]
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

-- [MIGRATION: 20261125_003_p0_ctv_pii_masking.sql]
-- ============================================================
-- Migration: 20261125_003_p0_ctv_pii_masking.sql
-- Phạm vi: P0-3 (Che PII khách hàng cho CTV ở tầng DB - fix V03)
--          Thu hồi SELECT trực tiếp của CTV trên orders & leads;
--          Cung cấp RPC ctv_list_orders & ctv_list_leads chỉ trả cột an toàn.
-- Thứ tự chạy: 003 (sau 002)
--
-- ROLLBACK (nếu cần):
--   drop function if exists public.ctv_list_orders(text, text, int, int);
--   drop function if exists public.ctv_list_leads(int, int);
--   drop function if exists public.mask_customer_name(text);
-- ============================================================

-- 1. Helper rút gọn tên khách (vd "Nguyễn Văn An" -> "Nguyễn V.A.")
create or replace function public.mask_customer_name(p_name text)
returns text
language plpgsql
immutable
as $$
declare
  v_parts text[];
  v_len int;
  v_res text;
  i int;
begin
  v_parts := regexp_split_to_array(trim(coalesce(p_name, '')), '\s+');
  v_len := coalesce(array_length(v_parts, 1), 0);
  if v_len = 0 then return 'Khách hàng'; end if;
  if v_len = 1 then return left(v_parts[1], 1) || '***'; end if;

  v_res := v_parts[1] || ' ';
  for i in 2..v_len loop
    v_res := v_res || upper(left(v_parts[i], 1)) || '.';
  end loop;
  return v_res;
end;
$$;

-- 2. Thu hồi SELECT trực tiếp của CTV trên orders & leads (chỉ staff/admin/develop được SELECT trực tiếp)
drop policy if exists "CTV views own orders and Admin views all" on public.orders;
create policy "Staff and Admin view all orders"
  on public.orders for select
  to authenticated
  using (public.is_staff_or_admin());

drop policy if exists "CTV views own leads and Admin views all" on public.leads;
create policy "Staff and Admin view all leads"
  on public.leads for select
  to authenticated
  using (public.is_staff_or_admin());

-- 3. RPC ctv_list_orders: phân trang server + KHÔNG trả SĐT, email, địa chỉ, ghi chú khách (V03, V06)
create or replace function public.ctv_list_orders(
  p_status text default null,
  p_search text default null,
  p_page int default 1,
  p_page_size int default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text := public.current_affiliate_code();
  v_limit int := greatest(1, least(coalesce(p_page_size, 20), 100));
  v_offset int := greatest(0, (greatest(coalesce(p_page, 1), 1) - 1) * v_limit);
  v_total bigint;
  v_rows jsonb;
begin
  if v_code is null then
    return jsonb_build_object('items', '[]'::jsonb, 'total', 0, 'page', p_page, 'page_size', v_limit);
  end if;

  select count(*) into v_total
  from public.orders o
  where o.affiliate_code = v_code
    and (p_status is null or p_status = '' or o.status = p_status)
    and (
      p_search is null or p_search = ''
      or o.order_code ilike '%' || p_search || '%'
      or o.items_summary ilike '%' || p_search || '%'
    );

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows
  from (
    select
      o.id,
      o.order_code,
      public.mask_customer_name(o.customer_name) as customer_masked,
      o.items_summary,
      o.payment_method,
      o.payment_status,
      o.subtotal,
      o.discount_amount,
      o.total_amount,
      o.commission_rate,
      o.commission_amount,
      o.status,
      o.commission_status,
      o.self_referral,
      o.completed_at,
      o.created_at
    from public.orders o
    where o.affiliate_code = v_code
      and (p_status is null or p_status = '' or o.status = p_status)
      and (
        p_search is null or p_search = ''
        or o.order_code ilike '%' || p_search || '%'
        or o.items_summary ilike '%' || p_search || '%'
      )
    order by o.created_at desc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object(
    'items', v_rows,
    'total', v_total,
    'page', greatest(coalesce(p_page, 1), 1),
    'page_size', v_limit
  );
end;
$$;

revoke all on function public.ctv_list_orders(text, text, int, int) from public, anon;
grant execute on function public.ctv_list_orders(text, text, int, int) to authenticated;

-- 4. RPC ctv_list_leads: chỉ trả tên rút gọn, xe, ngày, trạng thái (không trả SĐT/nội dung nhạy cảm)
create or replace function public.ctv_list_leads(
  p_page int default 1,
  p_page_size int default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code text := public.current_affiliate_code();
  v_limit int := greatest(1, least(coalesce(p_page_size, 20), 100));
  v_offset int := greatest(0, (greatest(coalesce(p_page, 1), 1) - 1) * v_limit);
  v_total bigint;
  v_rows jsonb;
begin
  if v_code is null then
    return jsonb_build_object('items', '[]'::jsonb, 'total', 0);
  end if;

  select count(*) into v_total from public.leads where affiliate_code = v_code;

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows
  from (
    select
      id,
      public.mask_customer_name(customer_name) as customer_masked,
      vehicle,
      status,
      created_at
    from public.leads
    where affiliate_code = v_code
    order by created_at desc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object('items', v_rows, 'total', v_total);
end;
$$;

revoke all on function public.ctv_list_leads(int, int) from public, anon;
grant execute on function public.ctv_list_leads(int, int) to authenticated;

-- [MIGRATION: 20261125_004_p0_ledger_payouts_kpis.sql]
-- ============================================================
-- Migration: 20261125_004_p0_ledger_payouts_kpis.sql
-- Phạm vi: P0-4 (Sổ cái commission_ledger append-only + commissions +
--          hoàn/thu hồi clawback + luồng trạng thái đơn hợp lệ)
--        + P0-5 (Chi trả nguyên tử, idempotent, payout_items, payout bất biến)
--        + P0-6 (KPI & đối soát tính 100% ở DB + phân trang server)
--        Giải quyết V04, V05, V06, V13, V18
-- Thứ tự chạy: 004 (sau 003)
--
-- ROLLBACK (nếu cần):
--   drop trigger if exists trg_payouts_immutable on public.commission_payouts;
--   drop trigger if exists trg_commission_ledger_immutable on public.commission_ledger;
--   drop function if exists public.admin_pay_commissions(uuid, uuid[], text, text, text);
--   drop function if exists public.admin_approve_commissions(uuid[], text);
--   drop function if exists public.release_matured_commissions();
--   drop function if exists public.admin_set_order_status(uuid, text, text, text);
--   drop table if exists public.payout_items;
--   drop table if exists public.commission_ledger;
--   drop table if exists public.commissions;
-- ============================================================

-- 1. Bảng commissions (trạng thái hiện tại của từng dòng hoa hồng theo đơn)
create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid unique not null references public.orders(id) on delete cascade,
  affiliate_id uuid not null references public.affiliates(id),
  affiliate_code text not null,
  base_amount bigint not null default 0,
  rate numeric(5,2) not null default 0,
  amount bigint not null default 0,
  status text not null default 'pending' check (status in ('pending', 'holding', 'available', 'paid', 'reversed')),
  hold_until timestamptz,
  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  reversed_at timestamptz,
  reversed_reason text,
  payout_id uuid references public.commission_payouts(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_commissions_affiliate_status on public.commissions(affiliate_id, status);
create index if not exists idx_commissions_hold_until on public.commissions(hold_until) where status = 'holding';

-- 2. Sổ cái commission_ledger (APPEND-ONLY bất biến theo Q3)
create table if not exists public.commission_ledger (
  id uuid primary key default gen_random_uuid(),
  commission_id uuid references public.commissions(id),
  order_id uuid references public.orders(id),
  affiliate_id uuid not null references public.affiliates(id),
  affiliate_code text not null,
  entry_type text not null check (entry_type in ('accrual', 'holding', 'release', 'reversal', 'clawback', 'payout', 'adjustment')),
  amount bigint not null, -- dương khi mở khóa/ghi nhận, âm khi reversal/clawback/payout
  balance_impact bigint not null default 0, -- tác động trực tiếp vào số dư khả dụng (available)
  payout_id uuid references public.commission_payouts(id),
  idempotency_key text unique not null,
  reason text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_ledger_affiliate_created on public.commission_ledger(affiliate_id, created_at desc);

drop trigger if exists trg_commission_ledger_immutable on public.commission_ledger;
create trigger trg_commission_ledger_immutable
before update or delete on public.commission_ledger
for each row
execute function public.block_immutable_mutation();

-- 3. Mở rộng commission_payouts thành bất biến + thuế TNCN (Q5) + payout_items (V05)
alter table public.commission_payouts
  add column if not exists affiliate_id uuid references public.affiliates(id),
  add column if not exists gross_amount bigint,
  add column if not exists tax_amount bigint not null default 0,
  add column if not exists net_amount bigint,
  add column if not exists transaction_ref text,
  add column if not exists idempotency_key text unique;

update public.commission_payouts p
set affiliate_id = coalesce(p.affiliate_id, (select a.id from public.affiliates a where upper(a.code) = upper(p.affiliate_code) limit 1)),
    gross_amount = coalesce(p.gross_amount, p.amount),
    net_amount = coalesce(p.net_amount, p.amount)
where p.affiliate_id is null or p.gross_amount is null or p.net_amount is null;

create table if not exists public.payout_items (
  id uuid primary key default gen_random_uuid(),
  payout_id uuid not null references public.commission_payouts(id) on delete restrict,
  commission_id uuid unique not null references public.commissions(id) on delete restrict,
  amount bigint not null,
  created_at timestamptz not null default now()
);

-- Bỏ policy UPDATE trên commission_payouts & khóa bất biến bằng trigger (V05 / T24)
drop policy if exists "Admins can update payouts" on public.commission_payouts;
drop policy if exists "Admins can insert payouts" on public.commission_payouts;

drop trigger if exists trg_payouts_immutable on public.commission_payouts;
create trigger trg_payouts_immutable
before update or delete on public.commission_payouts
for each row
execute function public.block_immutable_mutation();

drop trigger if exists trg_payout_items_immutable on public.payout_items;
create trigger trg_payout_items_immutable
before update or delete on public.payout_items
for each row
execute function public.block_immutable_mutation();

-- RLS cho commissions, commission_ledger, payout_items (chỉ đọc; ghi qua RPC)
alter table public.commissions enable row level security;
alter table public.commission_ledger enable row level security;
alter table public.payout_items enable row level security;

drop policy if exists "CTV views own commissions and Admin views all" on public.commissions;
create policy "CTV views own commissions and Admin views all"
  on public.commissions for select to authenticated
  using (public.is_staff_or_admin() or affiliate_code = public.current_affiliate_code());

drop policy if exists "CTV views own ledger and Admin views all" on public.commission_ledger;
create policy "CTV views own ledger and Admin views all"
  on public.commission_ledger for select to authenticated
  using (public.is_staff_or_admin() or affiliate_code = public.current_affiliate_code());

drop policy if exists "CTV views own payout items and Admin views all" on public.payout_items;
create policy "CTV views own payout items and Admin views all"
  on public.payout_items for select to authenticated
  using (
    public.is_staff_or_admin()
    or exists (
      select 1 from public.commission_payouts cp
      where cp.id = payout_id and cp.affiliate_code = public.current_affiliate_code()
    )
  );

-- 4. Backfill dữ liệu cũ (idempotent, giữ nguyên số tiền lịch sử theo Q1-Q6)
insert into public.commissions (
  order_id, affiliate_id, affiliate_code, base_amount, rate, amount, status, hold_until, created_at
)
select
  o.id,
  a.id,
  a.code,
  o.total_amount,
  o.commission_rate,
  o.commission_amount,
  case
    when o.status in ('cancelled', 'returned') then 'reversed'
    when o.commission_status = 'paid' then 'paid'
    when o.commission_status = 'approved' then 'available'
    when o.status = 'completed' then 'holding'
    else 'pending'
  end,
  case
    when o.status = 'completed' and o.commission_status = 'pending'
      then coalesce(o.completed_at, o.created_at) + (public.get_setting_numeric('commission_hold_days', 7) || ' days')::interval
    else null
  end,
  o.created_at
from public.orders o
join public.affiliates a on upper(a.code) = upper(o.affiliate_code)
where o.affiliate_code is not null
  and o.commission_amount > 0
on conflict (order_id) do nothing;

-- Backfill bút toán vào commission_ledger
insert into public.commission_ledger (
  commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason, created_at
)
select
  c.id, c.order_id, c.affiliate_id, c.affiliate_code,
  case
    when c.status = 'available' then 'release'
    when c.status = 'paid' then 'payout'
    when c.status = 'reversed' then 'reversal'
    else 'accrual'
  end,
  case when c.status = 'reversed' then -c.amount else c.amount end,
  case when c.status = 'available' then c.amount else 0 end,
  'backfill:' || c.id::text,
  'Backfill dữ liệu lịch sử khi nâng cấp sổ cái P0-4',
  c.created_at
from public.commissions c
on conflict (idempotency_key) do nothing;

-- Trigger tự động ghi bản ghi commissions + ledger khi đơn mới được tạo qua create_order
create or replace function public.sync_commission_on_order_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comm_id uuid;
begin
  if new.affiliate_id is not null and new.commission_amount > 0 and not new.self_referral then
    insert into public.commissions (
      order_id, affiliate_id, affiliate_code, base_amount, rate, amount, status
    ) values (
      new.id, new.affiliate_id, new.affiliate_code, new.total_amount, new.commission_rate, new.commission_amount, 'pending'
    )
    on conflict (order_id) do update
      set base_amount = excluded.base_amount,
          rate = excluded.rate,
          amount = excluded.amount,
          updated_at = now()
    returning id into v_comm_id;

    insert into public.commission_ledger (
      commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason
    ) values (
      v_comm_id, new.id, new.affiliate_id, new.affiliate_code, 'accrual', new.commission_amount, 0,
      'accrual:' || new.id::text, 'Ghi nhận hoa hồng tạm tính khi tạo đơn #' || new.order_code
    ) on conflict (idempotency_key) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_sync_commission on public.orders;
create trigger trg_orders_sync_commission
after update of commission_amount on public.orders
for each row
when (new.commission_amount > 0 and old.commission_amount = 0)
execute function public.sync_commission_on_order_created();

-- 5. RPC admin_set_order_status: kiểm tra luồng chuyển trạng thái + xử lý holding/reversal/clawback (V04 / Q2 / Q3)
create or replace function public.admin_set_order_status(
  p_order_id uuid,
  p_new_status text,
  p_reason text default null,
  p_payment_status text default null
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_updated public.orders;
  v_comm public.commissions;
  v_hold_days numeric;
  v_valid boolean := false;
begin
  if not public.has_permission('manage_orders') then
    raise exception 'Bạn không có quyền xử lý đơn hàng';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Không tìm thấy đơn hàng';
  end if;

  if p_new_status = v_order.status and p_payment_status is null then
    return v_order;
  end if;

  -- Kiểm tra luồng chuyển trạng thái hợp lệ (T19)
  if p_new_status = v_order.status then
    v_valid := true;
  elsif v_order.status = 'new' and p_new_status in ('confirmed', 'cancelled') then
    v_valid := true;
  elsif v_order.status = 'confirmed' and p_new_status in ('shipping', 'completed', 'cancelled') then
    v_valid := true;
  elsif v_order.status = 'shipping' and p_new_status in ('completed', 'cancelled', 'returned') then
    v_valid := true;
  elsif v_order.status = 'completed' and p_new_status in ('returned') then
    v_valid := true;
  end if;

  if not v_valid then
    raise exception 'Không thể chuyển trạng thái đơn từ "%" sang "%"', v_order.status, p_new_status;
  end if;

  if p_new_status in ('cancelled', 'returned') and length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Vui lòng nhập lý do khi hủy hoặc hoàn đơn (ít nhất 3 ký tự).';
  end if;

  update public.orders
  set status = p_new_status,
      payment_status = coalesce(p_payment_status, case when p_new_status = 'completed' then 'paid' when p_new_status = 'returned' then 'refunded' else payment_status end),
      completed_at = case when p_new_status = 'completed' and completed_at is null then now() else completed_at end,
      cancel_reason = case when p_new_status in ('cancelled', 'returned') then trim(p_reason) else cancel_reason end,
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_order_id
  returning * into v_updated;

  -- Xử lý sổ cái hoa hồng kèm theo
  select * into v_comm from public.commissions where order_id = p_order_id for update;
  if found then
    if p_new_status = 'completed' and v_comm.status = 'pending' then
      v_hold_days := public.get_setting_numeric('commission_hold_days', 7);
      update public.commissions
      set status = case when v_hold_days <= 0 then 'available' else 'holding' end,
          hold_until = now() + (v_hold_days || ' days')::interval,
          updated_at = now()
      where id = v_comm.id;

      if v_hold_days <= 0 then
        insert into public.commission_ledger (
          commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason, created_by
        ) values (
          v_comm.id, p_order_id, v_comm.affiliate_id, v_comm.affiliate_code, 'release', v_comm.amount, v_comm.amount,
          'release:' || v_comm.id::text, 'Mở khóa hoa hồng ngay (hold = 0 ngày)', auth.uid()
        ) on conflict (idempotency_key) do nothing;
      else
        insert into public.commission_ledger (
          commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason, created_by
        ) values (
          v_comm.id, p_order_id, v_comm.affiliate_id, v_comm.affiliate_code, 'holding', v_comm.amount, 0,
          'holding:' || v_comm.id::text, format('Đơn hoàn thành, giữ %s ngày trước khi mở khóa', v_hold_days), auth.uid()
        ) on conflict (idempotency_key) do nothing;
      end if;

    elsif p_new_status in ('cancelled', 'returned') then
      if v_comm.status in ('pending', 'holding', 'available') then
        update public.commissions
        set status = 'reversed',
            reversed_at = now(),
            reversed_reason = trim(p_reason),
            updated_at = now()
        where id = v_comm.id;

        insert into public.commission_ledger (
          commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason, created_by
        ) values (
          v_comm.id, p_order_id, v_comm.affiliate_id, v_comm.affiliate_code, 'reversal', -v_comm.amount,
          case when v_comm.status = 'available' then -v_comm.amount else 0 end,
          'reversal:' || v_comm.id::text, 'Thu hồi hoa hồng do đơn ' || p_new_status || ': ' || trim(p_reason), auth.uid()
        ) on conflict (idempotency_key) do nothing;

      elsif v_comm.status = 'paid' then
        -- Q3: Đã chi trả rồi -> ghi bút toán clawback âm trừ vào số dư kỳ sau (T18)
        update public.commissions
        set status = 'reversed',
            reversed_at = now(),
            reversed_reason = trim(p_reason),
            updated_at = now()
        where id = v_comm.id;

        insert into public.commission_ledger (
          commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason, created_by
        ) values (
          v_comm.id, p_order_id, v_comm.affiliate_id, v_comm.affiliate_code, 'clawback', -v_comm.amount, -v_comm.amount,
          'clawback:' || v_comm.id::text, 'Truy thu (clawback) hoa hồng đã chi do đơn hoàn: ' || trim(p_reason), auth.uid()
        ) on conflict (idempotency_key) do nothing;
      end if;
    end if;
  end if;

  perform public.write_audit_log(
    'admin_set_order_status',
    'orders',
    p_order_id::text,
    jsonb_build_object('status', v_order.status, 'payment_status', v_order.payment_status),
    jsonb_build_object('status', v_updated.status, 'payment_status', v_updated.payment_status),
    p_reason
  );

  return v_updated;
end;
$$;

revoke all on function public.admin_set_order_status(uuid, text, text, text) from public, anon;
grant execute on function public.admin_set_order_status(uuid, text, text, text) to authenticated;

-- Bỏ policy UPDATE trực tiếp trên orders để bắt buộc đi qua RPC admin_set_order_status
drop policy if exists "Admins can update orders" on public.orders;

-- 6. RPC release_matured_commissions: chuyển holding -> available khi hết hold_days (Q2)
create or replace function public.release_matured_commissions()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec record;
  v_count int := 0;
begin
  for v_rec in
    select * from public.commissions
    where status = 'holding' and hold_until is not null and hold_until <= now()
    for update skip locked
  loop
    update public.commissions
    set status = 'available', approved_at = now(), updated_at = now()
    where id = v_rec.id;

    update public.orders set commission_status = 'approved' where id = v_rec.order_id;

    insert into public.commission_ledger (
      commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason
    ) values (
      v_rec.id, v_rec.order_id, v_rec.affiliate_id, v_rec.affiliate_code, 'release', v_rec.amount, v_rec.amount,
      'release:' || v_rec.id::text, 'Hết thời gian giữ (hold), mở khóa hoa hồng khả dụng'
    ) on conflict (idempotency_key) do nothing;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.release_matured_commissions() from public, anon;
grant execute on function public.release_matured_commissions() to authenticated;

-- 7. RPC admin_approve_commissions: Admin duyệt mở khóa thủ công (nếu muốn duyệt sớm)
create or replace function public.admin_approve_commissions(
  p_commission_ids uuid[],
  p_reason text default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rec record;
  v_count int := 0;
begin
  if not public.has_permission('approve_commissions') then
    raise exception 'Bạn không có quyền duyệt hoa hồng';
  end if;

  for v_rec in
    select c.* from public.commissions c
    join public.orders o on o.id = c.order_id
    where c.id = any(p_commission_ids)
      and c.status in ('pending', 'holding')
      and o.status = 'completed'
    for update of c
  loop
    update public.commissions
    set status = 'available', approved_at = now(), approved_by = auth.uid(), updated_at = now()
    where id = v_rec.id;

    update public.orders set commission_status = 'approved' where id = v_rec.order_id;

    insert into public.commission_ledger (
      commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact, idempotency_key, reason, created_by
    ) values (
      v_rec.id, v_rec.order_id, v_rec.affiliate_id, v_rec.affiliate_code, 'release', v_rec.amount, v_rec.amount,
      'release:' || v_rec.id::text, coalesce(nullif(trim(p_reason), ''), 'Admin duyệt mở khóa hoa hồng'), auth.uid()
    ) on conflict (idempotency_key) do nothing;

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    perform public.write_audit_log(
      'admin_approve_commissions', 'commissions', array_to_string(p_commission_ids, ','),
      null, jsonb_build_object('approved_count', v_count), p_reason
    );
  end if;

  return v_count;
end;
$$;

revoke all on function public.admin_approve_commissions(uuid[], text) from public, anon;
grant execute on function public.admin_approve_commissions(uuid[], text) to authenticated;

-- 8. RPC admin_pay_commissions: Chi trả nguyên tử + idempotent + tính thuế TNCN theo app_settings (V05 / Q5 / T21-T23)
create or replace function public.admin_pay_commissions(
  p_affiliate_id uuid,
  p_commission_ids uuid[],
  p_transaction_ref text,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing public.commission_payouts;
  v_aff public.affiliates;
  v_locked_count int := 0;
  v_gross bigint := 0;
  v_clawback bigint := 0;
  v_tax_rate numeric;
  v_tax_threshold bigint;
  v_tax bigint := 0;
  v_net bigint := 0;
  v_payout_id uuid;
  v_rec record;
  v_key text := coalesce(nullif(trim(p_idempotency_key), ''), 'pay:' || p_affiliate_id::text || ':' || md5(array_to_string(p_commission_ids, ',')));
begin
  if not public.has_permission('pay_commissions') then
    raise exception 'Bạn không có quyền xác nhận thanh toán hoa hồng';
  end if;

  if length(trim(coalesce(p_transaction_ref, ''))) < 3 then
    raise exception 'Bắt buộc nhập mã giao dịch / chứng từ chuyển khoản (ít nhất 3 ký tự).';
  end if;

  -- Idempotency check (T21)
  select * into v_existing from public.commission_payouts where idempotency_key = v_key;
  if found then
    return jsonb_build_object('payout_id', v_existing.id, 'idempotent', true, 'net_amount', v_existing.net_amount);
  end if;

  select * into v_aff from public.affiliates where id = p_affiliate_id;
  if not found then
    raise exception 'Không tìm thấy CTV';
  end if;

  -- Khóa toàn bộ các dòng commission được chọn và kiểm tra thuộc đúng CTV + đang available (T23)
  for v_rec in
    select * from public.commissions
    where id = any(p_commission_ids)
    for update
  loop
    if v_rec.affiliate_id <> p_affiliate_id then
      raise exception 'Danh sách có hoa hồng không thuộc CTV %', v_aff.code;
    end if;
    if v_rec.status <> 'available' then
      raise exception 'Hoa hồng % không ở trạng thái khả dụng (hiện tại: %)', v_rec.id, v_rec.status;
    end if;
    v_locked_count := v_locked_count + 1;
    v_gross := v_gross + v_rec.amount;
  end loop;

  if v_locked_count = 0 or v_locked_count <> coalesce(array_length(p_commission_ids, 1), 0) then
    raise exception 'Một hoặc nhiều khoản hoa hồng không hợp lệ hoặc đã được chi trả.';
  end if;

  -- Bù trừ số dư clawback âm (nếu có) từ sổ cái (Q3)
  select least(0, coalesce(sum(balance_impact), 0) - v_gross) into v_clawback
  from public.commission_ledger
  where affiliate_id = p_affiliate_id;
  -- Nếu tổng balance_impact trước khi trả nhỏ hơn v_gross nghĩa là có khoản âm clawback cần trừ
  select least(0, coalesce(sum(case when entry_type = 'clawback' then balance_impact else 0 end), 0)) into v_clawback
  from public.commission_ledger
  where affiliate_id = p_affiliate_id and payout_id is null;

  v_gross := greatest(0, v_gross + v_clawback);
  if v_gross <= 0 then
    raise exception 'Số tiền thực chi sau khi bù trừ clawback không dương (<= 0 đ).';
  end if;

  -- Khấu trừ thuế TNCN theo app_settings (mặc định 0%)
  v_tax_rate := public.get_setting_numeric('tax_withholding_rate', 0);
  v_tax_threshold := public.get_setting_numeric('tax_threshold_per_payment', 0)::bigint;
  if v_tax_rate > 0 and v_gross >= v_tax_threshold then
    v_tax := floor((v_gross * v_tax_rate) / 100.0);
  end if;
  v_net := greatest(0, v_gross - v_tax);

  insert into public.commission_payouts (
    affiliate_id, affiliate_code, amount, gross_amount, tax_amount, net_amount,
    order_count, transaction_ref, note, idempotency_key, created_by
  ) values (
    p_affiliate_id, v_aff.code, v_net, v_gross, v_tax, v_net,
    v_locked_count, trim(p_transaction_ref), coalesce(nullif(trim(p_note), ''), 'Chi trả hoa hồng ' || v_aff.code),
    v_key, auth.uid()
  ) returning id into v_payout_id;

  -- Liên kết payout_items + cập nhật commissions & orders + ghi ledger
  for v_rec in select * from public.commissions where id = any(p_commission_ids)
  loop
    insert into public.payout_items (payout_id, commission_id, amount)
    values (v_payout_id, v_rec.id, v_rec.amount);

    update public.commissions
    set status = 'paid', payout_id = v_payout_id, updated_at = now()
    where id = v_rec.id;

    update public.orders set commission_status = 'paid' where id = v_rec.order_id;

    insert into public.commission_ledger (
      commission_id, order_id, affiliate_id, affiliate_code, entry_type, amount, balance_impact,
      payout_id, idempotency_key, reason, created_by
    ) values (
      v_rec.id, v_rec.order_id, p_affiliate_id, v_aff.code, 'payout', -v_rec.amount, -v_rec.amount,
      v_payout_id, 'payout:' || v_payout_id::text || ':' || v_rec.id::text,
      'Chi trả hoa hồng (GD: ' || trim(p_transaction_ref) || ')', auth.uid()
    );
  end loop;

  perform public.write_audit_log(
    'admin_pay_commissions', 'commission_payouts', v_payout_id::text,
    null,
    jsonb_build_object('affiliate_code', v_aff.code, 'order_count', v_locked_count, 'gross_amount', v_gross, 'tax_amount', v_tax, 'net_amount', v_net, 'transaction_ref', trim(p_transaction_ref)),
    p_note
  );

  return jsonb_build_object(
    'payout_id', v_payout_id,
    'idempotent', false,
    'gross_amount', v_gross,
    'tax_amount', v_tax,
    'net_amount', v_net,
    'order_count', v_locked_count
  );
end;
$$;

revoke all on function public.admin_pay_commissions(uuid, uuid[], text, text, text) from public, anon;
grant execute on function public.admin_pay_commissions(uuid, uuid[], text, text, text) to authenticated;

-- 9. RPC tổng hợp KPI phía DB (fix V06 & V13 - không bao giờ bị cắt 300/200 đơn!)
create or replace function public.ctv_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_aff public.affiliates;
  v_total_orders bigint := 0;
  v_valid_orders bigint := 0;
  v_revenue bigint := 0;
  v_pending bigint := 0;
  v_holding bigint := 0;
  v_available bigint := 0;
  v_paid bigint := 0;
  v_reversed bigint := 0;
  v_ledger_available bigint := 0;
begin
  select * into v_aff from public.affiliates where user_id = auth.uid() and status = 'active' limit 1;
  if not found then
    return jsonb_build_object('ok', false);
  end if;

  select
    count(*),
    count(*) filter (where status not in ('cancelled', 'returned')),
    coalesce(sum(total_amount) filter (where status not in ('cancelled', 'returned')), 0)
  into v_total_orders, v_valid_orders, v_revenue
  from public.orders
  where affiliate_code = v_aff.code;

  select
    coalesce(sum(amount) filter (where status = 'pending'), 0),
    coalesce(sum(amount) filter (where status = 'holding'), 0),
    coalesce(sum(amount) filter (where status = 'available'), 0),
    coalesce(sum(amount) filter (where status = 'paid'), 0),
    coalesce(sum(amount) filter (where status = 'reversed'), 0)
  into v_pending, v_holding, v_available, v_paid, v_reversed
  from public.commissions
  where affiliate_id = v_aff.id;

  -- Số dư khả dụng thực tế tính từ sổ cái (đã trừ clawback & payout)
  select coalesce(sum(balance_impact), 0) into v_ledger_available
  from public.commission_ledger
  where affiliate_id = v_aff.id;

  return jsonb_build_object(
    'ok', true,
    'total_orders', v_total_orders,
    'valid_orders', v_valid_orders,
    'revenue', v_revenue,
    'pending_commission', v_pending,
    'holding_commission', v_holding,
    'available_commission', v_ledger_available,
    'paid_commission', v_paid,
    'reversed_commission', v_reversed,
    'min_payout_amount', public.get_setting_numeric('min_payout_amount', 200000)::bigint,
    'hold_days', public.get_setting_numeric('commission_hold_days', 7)::int
  );
end;
$$;

revoke all on function public.ctv_overview() from public, anon;
grant execute on function public.ctv_overview() to authenticated;

create or replace function public.admin_overview(
  p_from timestamptz default null,
  p_to timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total_orders bigint;
  v_direct_orders bigint;
  v_ctv_orders bigint;
  v_cancelled_orders bigint;
  v_revenue bigint;
  v_active_ctv bigint;
  v_pending_ctv bigint;
  v_comm_pending bigint;
  v_comm_holding bigint;
  v_comm_available bigint;
  v_comm_paid bigint;
begin
  if not public.is_staff_or_admin() then
    raise exception 'Không có quyền xem tổng quan quản trị';
  end if;

  select
    count(*),
    count(*) filter (where affiliate_code is null),
    count(*) filter (where affiliate_code is not null),
    count(*) filter (where status in ('cancelled', 'returned')),
    coalesce(sum(total_amount) filter (where status not in ('cancelled', 'returned')), 0)
  into v_total_orders, v_direct_orders, v_ctv_orders, v_cancelled_orders, v_revenue
  from public.orders
  where (p_from is null or created_at >= p_from)
    and (p_to is null or created_at <= p_to);

  select
    count(*) filter (where role = 'ctv' and status = 'active'),
    count(*) filter (where role = 'ctv' and status = 'pending')
  into v_active_ctv, v_pending_ctv
  from public.affiliates;

  select
    coalesce(sum(amount) filter (where status = 'pending'), 0),
    coalesce(sum(amount) filter (where status = 'holding'), 0),
    coalesce(sum(amount) filter (where status = 'available'), 0),
    coalesce(sum(amount) filter (where status = 'paid'), 0)
  into v_comm_pending, v_comm_holding, v_comm_available, v_comm_paid
  from public.commissions;

  return jsonb_build_object(
    'total_orders', v_total_orders,
    'direct_orders', v_direct_orders,
    'ctv_orders', v_ctv_orders,
    'cancelled_orders', v_cancelled_orders,
    'revenue', v_revenue,
    'active_ctv', v_active_ctv,
    'pending_ctv', v_pending_ctv,
    'comm_pending', v_comm_pending,
    'comm_holding', v_comm_holding,
    'comm_available', v_comm_available,
    'comm_paid', v_comm_paid
  );
end;
$$;

revoke all on function public.admin_overview(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_overview(timestamptz, timestamptz) to authenticated;

-- RPC admin_list_orders: phân trang & lọc hoàn toàn phía server (V06 / P2-1 / T38)
create or replace function public.admin_list_orders(
  p_search text default null,
  p_source text default null,
  p_status text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_page int default 1,
  p_page_size int default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := greatest(1, least(coalesce(p_page_size, 25), 100));
  v_offset int := greatest(0, (greatest(coalesce(p_page, 1), 1) - 1) * v_limit);
  v_total bigint;
  v_rows jsonb;
begin
  if not public.is_staff_or_admin() then
    raise exception 'Không có quyền xem danh sách đơn hàng';
  end if;

  select count(*) into v_total
  from public.orders o
  where (p_source is null or p_source = '' or (p_source = 'direct' and o.affiliate_code is null) or (p_source = 'ctv' and o.affiliate_code is not null))
    and (p_status is null or p_status = '' or o.status = p_status)
    and (p_from is null or o.created_at >= p_from)
    and (p_to is null or o.created_at <= p_to)
    and (
      p_search is null or p_search = ''
      or o.order_code ilike '%' || p_search || '%'
      or o.customer_name ilike '%' || p_search || '%'
      or o.phone ilike '%' || p_search || '%'
      or coalesce(o.affiliate_code, '') ilike '%' || p_search || '%'
    );

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows
  from (
    select
      o.*,
      c.status as ledger_commission_status,
      c.hold_until as commission_hold_until
    from public.orders o
    left join public.commissions c on c.order_id = o.id
    where (p_source is null or p_source = '' or (p_source = 'direct' and o.affiliate_code is null) or (p_source = 'ctv' and o.affiliate_code is not null))
      and (p_status is null or p_status = '' or o.status = p_status)
      and (p_from is null or o.created_at >= p_from)
      and (p_to is null or o.created_at <= p_to)
      and (
        p_search is null or p_search = ''
        or o.order_code ilike '%' || p_search || '%'
        or o.customer_name ilike '%' || p_search || '%'
        or o.phone ilike '%' || p_search || '%'
        or coalesce(o.affiliate_code, '') ilike '%' || p_search || '%'
      )
    order by o.created_at desc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object(
    'items', v_rows,
    'total', v_total,
    'page', greatest(coalesce(p_page, 1), 1),
    'page_size', v_limit
  );
end;
$$;

revoke all on function public.admin_list_orders(text, text, text, timestamptz, timestamptz, int, int) from public, anon;
grant execute on function public.admin_list_orders(text, text, text, timestamptz, timestamptz, int, int) to authenticated;

-- RPC admin_settlement_summary: đối soát công nợ theo CTV tính trực tiếp từ bảng commissions
create or replace function public.admin_settlement_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rows jsonb;
begin
  if not public.is_staff_or_admin() then
    raise exception 'Không có quyền xem đối soát';
  end if;

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows
  from (
    select
      a.id as affiliate_id,
      a.code,
      a.full_name,
      a.phone,
      coalesce(sum(c.amount) filter (where c.status = 'holding'), 0) as holding_amount,
      count(c.id) filter (where c.status = 'holding') as holding_count,
      coalesce(array_agg(c.id) filter (where c.status = 'holding'), '{}') as holding_ids,
      coalesce(sum(c.amount) filter (where c.status = 'available'), 0) as available_amount,
      count(c.id) filter (where c.status = 'available') as available_count,
      coalesce(array_agg(c.id) filter (where c.status = 'available'), '{}') as available_ids,
      coalesce(sum(c.amount) filter (where c.status = 'paid'), 0) as paid_amount,
      coalesce((select sum(l.balance_impact) from public.commission_ledger l where l.affiliate_id = a.id), 0) as net_available_balance
    from public.affiliates a
    join public.commissions c on c.affiliate_id = a.id
    group by a.id, a.code, a.full_name, a.phone
    order by coalesce(sum(c.amount) filter (where c.status = 'available'), 0) desc, a.code asc
  ) t;

  return v_rows;
end;
$$;

revoke all on function public.admin_settlement_summary() from public, anon;
grant execute on function public.admin_settlement_summary() to authenticated;

-- 10. Index tối ưu hiệu năng (V18 / P2-7)
create index if not exists idx_orders_status_created on public.orders(status, created_at desc);
create index if not exists idx_orders_comm_status on public.orders(commission_status);
create index if not exists idx_leads_affiliate_code on public.leads(affiliate_code);
create index if not exists idx_payouts_paid_at on public.commission_payouts(paid_at desc);

-- [MIGRATION: 20261125_005_p1_payout_requests_profile_clicks.sql]
-- ============================================================================
-- P1-1, P1-2, P1-3, P1-5, P1-6, P1-7, P1-8, P1-9
-- Ngân hàng CTV, Yêu cầu rút tiền, Click tracking, Chi tiết đơn/CTV,
-- CRUD Sản phẩm/Coupon/Quy tắc HH, Nhật ký hoạt động (Audit Logs)
-- Thứ tự chạy: 005 (sau 004)
-- Idempotent: Có
-- ============================================================================

-- Helper: lấy affiliate_id của user đang đăng nhập (SECURITY DEFINER để dùng an toàn trong RLS)
create or replace function public.current_affiliate_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.affiliates where user_id = auth.uid() limit 1;
$$;

revoke all on function public.current_affiliate_id() from public, anon;
grant execute on function public.current_affiliate_id() to authenticated;

-- 1. Bảng tài khoản ngân hàng CTV (P1-2, Q5: cần admin xác minh trước khi chi trả)
create table if not exists public.affiliate_bank_accounts (
  id uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null unique references public.affiliates(id) on delete cascade,
  bank_name text not null,
  account_number text not null,
  account_holder text not null,
  branch text,
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  verified_at timestamptz,
  verified_by uuid references auth.users(id),
  reject_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.affiliate_bank_accounts enable row level security;

drop policy if exists "ctv_read_own_bank" on public.affiliate_bank_accounts;
create policy "ctv_read_own_bank"
  on public.affiliate_bank_accounts for select
  to authenticated
  using (affiliate_id = public.current_affiliate_id() or public.has_permission('affiliates') or public.has_permission('payouts'));

-- 2. Bảng yêu cầu rút tiền (P1-1, Q5: tối đa 1 yêu cầu mở mỗi CTV)
create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates(id) on delete restrict,
  amount bigint not null check (amount > 0),
  status text not null default 'requested' check (status in ('requested', 'approved', 'rejected', 'paid')),
  bank_snapshot jsonb not null default '{}'::jsonb,
  note text,
  reject_reason text,
  payout_id uuid references public.commission_payouts(id),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);

create unique index if not exists idx_payout_requests_one_open
  on public.payout_requests (affiliate_id)
  where status in ('requested', 'approved');

create index if not exists idx_payout_requests_status
  on public.payout_requests (status, requested_at desc);

alter table public.payout_requests enable row level security;

drop policy if exists "ctv_read_own_payout_requests" on public.payout_requests;
create policy "ctv_read_own_payout_requests"
  on public.payout_requests for select
  to authenticated
  using (affiliate_id = public.current_affiliate_id() or public.has_permission('payouts'));

-- 3. Bảng theo dõi lượt click link giới thiệu (P1-3, C7, C8)
create table if not exists public.referral_clicks (
  id uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates(id) on delete cascade,
  affiliate_code text not null,
  landing_path text,
  session_id text,
  created_at timestamptz not null default now()
);

create index if not exists idx_referral_clicks_aff_created
  on public.referral_clicks (affiliate_id, created_at desc);

create index if not exists idx_referral_clicks_dedupe
  on public.referral_clicks (affiliate_code, session_id, created_at desc);

alter table public.referral_clicks enable row level security;

drop policy if exists "read_referral_clicks_own_or_admin" on public.referral_clicks;
create policy "read_referral_clicks_own_or_admin"
  on public.referral_clicks for select
  to authenticated
  using (affiliate_id = public.current_affiliate_id() or public.has_permission('affiliates'));

-- 4. RPC track_click (P1-3 — dedupe 5 phút theo session_id + affiliate_code)
create or replace function public.track_click(
  p_affiliate_code text,
  p_landing_path text default '/',
  p_session_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(trim(coalesce(p_affiliate_code, '')));
  v_sess text := left(trim(coalesce(p_session_id, '')), 120);
  v_aff_id uuid;
  v_recent int := 0;
begin
  if v_code = '' then
    return jsonb_build_object('tracked', false);
  end if;

  select id into v_aff_id
  from public.affiliates
  where code = v_code and status = 'active'
  limit 1;

  if v_aff_id is null then
    return jsonb_build_object('tracked', false);
  end if;

  if v_sess <> '' then
    select count(*) into v_recent
    from public.referral_clicks
    where affiliate_code = v_code
      and session_id = v_sess
      and created_at >= now() - interval '5 minutes';

    if v_recent > 0 then
      return jsonb_build_object('tracked', false, 'deduped', true);
    end if;
  end if;

  insert into public.referral_clicks (affiliate_id, affiliate_code, landing_path, session_id)
  values (v_aff_id, v_code, left(coalesce(p_landing_path, '/'), 300), nullif(v_sess, ''));

  return jsonb_build_object('tracked', true);
end;
$$;

revoke all on function public.track_click(text, text, text) from public;
grant execute on function public.track_click(text, text, text) to anon, authenticated;

-- 5. RPC Hồ sơ & Ngân hàng CTV (P1-2)
create or replace function public.ctv_get_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff record;
  v_bank record;
  v_settings jsonb;
begin
  select * into v_aff from public.affiliates where user_id = auth.uid();
  if not found then
    raise exception 'Không tìm thấy hồ sơ CTV';
  end if;

  select * into v_bank from public.affiliate_bank_accounts where affiliate_id = v_aff.id;

  select jsonb_object_agg(key, value) into v_settings
  from public.app_settings
  where key in ('min_payout_amount', 'commission_hold_days', 'payout_weekday', 'tax_withholding_rate', 'tax_threshold_per_payment');

  return jsonb_build_object(
    'affiliate', jsonb_build_object(
      'id', v_aff.id,
      'code', v_aff.code,
      'full_name', v_aff.full_name,
      'email', v_aff.email,
      'phone', v_aff.phone,
      'zalo', v_aff.zalo,
      'area', v_aff.area,
      'job_type', v_aff.job_type,
      'commission_rate', v_aff.commission_rate,
      'status', v_aff.status,
      'reject_reason', v_aff.reject_reason,
      'role', v_aff.role
    ),
    'bank', case when v_bank.id is not null then jsonb_build_object(
      'bank_name', v_bank.bank_name,
      'account_number', v_bank.account_number,
      'account_holder', v_bank.account_holder,
      'branch', v_bank.branch,
      'status', v_bank.status,
      'verified_at', v_bank.verified_at,
      'reject_reason', v_bank.reject_reason
    ) else null end,
    'settings', coalesce(v_settings, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.ctv_get_profile() from public;
grant execute on function public.ctv_get_profile() to authenticated;

create or replace function public.ctv_update_profile(
  p_full_name text,
  p_phone text,
  p_zalo text default null,
  p_area text default null,
  p_job_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff record;
begin
  select * into v_aff from public.affiliates where user_id = auth.uid();
  if not found then
    raise exception 'Không tìm thấy hồ sơ CTV';
  end if;

  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Họ tên phải có ít nhất 2 ký tự';
  end if;

  update public.affiliates
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      zalo = nullif(trim(coalesce(p_zalo, '')), ''),
      area = nullif(trim(coalesce(p_area, '')), ''),
      job_type = nullif(trim(coalesce(p_job_type, '')), ''),
      updated_at = now()
  where id = v_aff.id;

  perform public.write_audit_log(
    'ctv_update_profile', 'affiliates', v_aff.id::text,
    jsonb_build_object('full_name', v_aff.full_name, 'phone', v_aff.phone),
    jsonb_build_object('full_name', trim(p_full_name), 'phone', trim(coalesce(p_phone, '')))
  );

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.ctv_update_profile(text, text, text, text, text) from public;
grant execute on function public.ctv_update_profile(text, text, text, text, text) to authenticated;

create or replace function public.ctv_update_bank_account(
  p_bank_name text,
  p_account_number text,
  p_account_holder text,
  p_branch text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff_id uuid := public.current_affiliate_id();
begin
  if v_aff_id is null then
    raise exception 'Không tìm thấy hồ sơ CTV';
  end if;

  if length(trim(coalesce(p_bank_name, ''))) < 2
     or length(regexp_replace(coalesce(p_account_number, ''), '[^0-9A-Za-z]', '', 'g')) < 6
     or length(trim(coalesce(p_account_holder, ''))) < 2 then
    raise exception 'Vui lòng nhập đầy đủ Tên ngân hàng, Số tài khoản và Tên chủ tài khoản';
  end if;

  insert into public.affiliate_bank_accounts (
    affiliate_id, bank_name, account_number, account_holder, branch,
    status, verified_at, verified_by, reject_reason, updated_at
  )
  values (
    v_aff_id,
    trim(p_bank_name),
    regexp_replace(trim(p_account_number), '\s+', '', 'g'),
    upper(trim(p_account_holder)),
    nullif(trim(coalesce(p_branch, '')), ''),
    'pending', null, null, null, now()
  )
  on conflict (affiliate_id) do update
  set bank_name = excluded.bank_name,
      account_number = excluded.account_number,
      account_holder = excluded.account_holder,
      branch = excluded.branch,
      status = 'pending',
      verified_at = null,
      verified_by = null,
      reject_reason = null,
      updated_at = now();

  perform public.write_audit_log(
    'ctv_update_bank_account', 'affiliate_bank_accounts', v_aff_id::text,
    null,
    jsonb_build_object('bank_name', trim(p_bank_name), 'account_holder', upper(trim(p_account_holder)), 'status', 'pending')
  );

  return jsonb_build_object('ok', true, 'status', 'pending');
end;
$$;

revoke all on function public.ctv_update_bank_account(text, text, text, text) from public;
grant execute on function public.ctv_update_bank_account(text, text, text, text) to authenticated;

create or replace function public.admin_verify_bank_account(
  p_affiliate_id uuid,
  p_status text,
  p_reject_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bank record;
begin
  if not (public.has_permission('affiliates') or public.has_permission('payouts')) then
    raise exception 'Không có quyền xác minh tài khoản ngân hàng';
  end if;

  if p_status not in ('verified', 'rejected') then
    raise exception 'Trạng thái xác minh không hợp lệ';
  end if;

  if p_status = 'rejected' and length(trim(coalesce(p_reject_reason, ''))) < 3 then
    raise exception 'Vui lòng nhập lý do từ chối tài khoản ngân hàng';
  end if;

  select * into v_bank from public.affiliate_bank_accounts where affiliate_id = p_affiliate_id;
  if not found then
    raise exception 'CTV chưa cập nhật tài khoản ngân hàng';
  end if;

  update public.affiliate_bank_accounts
  set status = p_status,
      verified_at = case when p_status = 'verified' then now() else null end,
      verified_by = auth.uid(),
      reject_reason = case when p_status = 'rejected' then trim(p_reject_reason) else null end,
      updated_at = now()
  where affiliate_id = p_affiliate_id;

  perform public.write_audit_log(
    'admin_verify_bank_account', 'affiliate_bank_accounts', p_affiliate_id::text,
    jsonb_build_object('status', v_bank.status),
    jsonb_build_object('status', p_status, 'reject_reason', p_reject_reason)
  );

  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;

revoke all on function public.admin_verify_bank_account(uuid, text, text) from public;
grant execute on function public.admin_verify_bank_account(uuid, text, text) to authenticated;

-- 6. RPC Yêu cầu rút tiền cho CTV & duyệt/chi trả cho Admin (P1-1)
create or replace function public.ctv_request_payout(
  p_amount bigint,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff record;
  v_bank record;
  v_min_payout bigint := 200000;
  v_available bigint := 0;
  v_open_count int := 0;
  v_req_id uuid;
begin
  select * into v_aff from public.affiliates where user_id = auth.uid();
  if not found or v_aff.status <> 'active' then
    raise exception 'Tài khoản CTV chưa được kích hoạt';
  end if;

  select * into v_bank from public.affiliate_bank_accounts where affiliate_id = v_aff.id;
  if not found or v_bank.status <> 'verified' then
    raise exception 'Tài khoản ngân hàng chưa được Admin xác minh. Vui lòng cập nhật ở mục Hồ sơ & Ngân hàng.';
  end if;

  select count(*) into v_open_count
  from public.payout_requests
  where affiliate_id = v_aff.id and status in ('requested', 'approved');

  if v_open_count > 0 then
    raise exception 'Bạn đang có một yêu cầu rút tiền chưa xử lý xong.';
  end if;

  select coalesce((value)::text::bigint, 200000) into v_min_payout
  from public.app_settings where key = 'min_payout_amount';

  if coalesce(p_amount, 0) < v_min_payout then
    raise exception 'Số tiền rút tối thiểu là % đ', v_min_payout;
  end if;

  select coalesce(sum(balance_impact), 0) into v_available
  from public.commission_ledger
  where affiliate_id = v_aff.id;

  if p_amount > v_available then
    raise exception 'Số dư khả dụng (%) không đủ cho yêu cầu rút tiền này', v_available;
  end if;

  insert into public.payout_requests (
    affiliate_id, amount, status, bank_snapshot, note
  )
  values (
    v_aff.id,
    p_amount,
    'requested',
    jsonb_build_object(
      'bank_name', v_bank.bank_name,
      'account_number', v_bank.account_number,
      'account_holder', v_bank.account_holder,
      'branch', v_bank.branch
    ),
    nullif(trim(coalesce(p_note, '')), '')
  )
  returning id into v_req_id;

  perform public.write_audit_log(
    'ctv_request_payout', 'payout_requests', v_req_id::text,
    null,
    jsonb_build_object('affiliate_code', v_aff.code, 'amount', p_amount)
  );

  return jsonb_build_object('id', v_req_id, 'status', 'requested', 'amount', p_amount);
end;
$$;

revoke all on function public.ctv_request_payout(bigint, text) from public;
grant execute on function public.ctv_request_payout(bigint, text) to authenticated;

create or replace function public.ctv_list_payout_requests()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff_id uuid := public.current_affiliate_id();
  v_items jsonb;
begin
  if v_aff_id is null then
    raise exception 'Không tìm thấy hồ sơ CTV';
  end if;

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_items
  from (
    select id, amount, status, bank_snapshot, note, reject_reason, payout_id, requested_at, reviewed_at
    from public.payout_requests
    where affiliate_id = v_aff_id
    order by requested_at desc
    limit 50
  ) t;

  return v_items;
end;
$$;

revoke all on function public.ctv_list_payout_requests() from public;
grant execute on function public.ctv_list_payout_requests() to authenticated;

create or replace function public.admin_list_payout_requests(
  p_status text default 'all',
  p_page int default 1,
  p_page_size int default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offset int := greatest(0, (coalesce(p_page, 1) - 1) * least(100, greatest(1, coalesce(p_page_size, 20))));
  v_limit int := least(100, greatest(1, coalesce(p_page_size, 20)));
  v_total bigint;
  v_items jsonb;
begin
  if not public.has_permission('payouts') then
    raise exception 'Không có quyền xem yêu cầu rút tiền';
  end if;

  select count(*) into v_total
  from public.payout_requests pr
  where (p_status is null or p_status = 'all' or pr.status = p_status);

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_items
  from (
    select
      pr.id, pr.affiliate_id, a.code as affiliate_code, a.full_name as affiliate_name, a.phone as affiliate_phone,
      pr.amount, pr.status, pr.bank_snapshot, pr.note, pr.reject_reason, pr.payout_id, pr.requested_at, pr.reviewed_at
    from public.payout_requests pr
    join public.affiliates a on a.id = pr.affiliate_id
    where (p_status is null or p_status = 'all' or pr.status = p_status)
    order by pr.requested_at desc
    offset v_offset limit v_limit
  ) t;

  return jsonb_build_object('total', v_total, 'items', v_items);
end;
$$;

revoke all on function public.admin_list_payout_requests(text, int, int) from public;
grant execute on function public.admin_list_payout_requests(text, int, int) to authenticated;

create or replace function public.admin_review_payout_request(
  p_request_id uuid,
  p_action text,
  p_transaction_ref text default null,
  p_reject_reason text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_req record;
  v_comm_ids uuid[];
  v_pay_result jsonb;
begin
  if not public.has_permission('payouts') then
    raise exception 'Không có quyền xử lý yêu cầu rút tiền';
  end if;

  select * into v_req from public.payout_requests where id = p_request_id for update;
  if not found then
    raise exception 'Không tìm thấy yêu cầu rút tiền';
  end if;

  if p_action = 'approve' then
    if v_req.status <> 'requested' then
      raise exception 'Chỉ có thể duyệt yêu cầu đang chờ';
    end if;
    update public.payout_requests
    set status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
    where id = p_request_id;

    perform public.write_audit_log('admin_approve_payout_request', 'payout_requests', p_request_id::text,
      jsonb_build_object('status', v_req.status), jsonb_build_object('status', 'approved'));
    return jsonb_build_object('ok', true, 'status', 'approved');

  elsif p_action = 'reject' then
    if v_req.status not in ('requested', 'approved') then
      raise exception 'Không thể từ chối yêu cầu ở trạng thái hiện tại';
    end if;
    if length(trim(coalesce(p_reject_reason, ''))) < 3 then
      raise exception 'Vui lòng nhập lý do từ chối yêu cầu rút tiền';
    end if;
    update public.payout_requests
    set status = 'rejected', reject_reason = trim(p_reject_reason), reviewed_at = now(), reviewed_by = auth.uid()
    where id = p_request_id;

    perform public.write_audit_log('admin_reject_payout_request', 'payout_requests', p_request_id::text,
      jsonb_build_object('status', v_req.status), jsonb_build_object('status', 'rejected', 'reason', trim(p_reject_reason)));
    return jsonb_build_object('ok', true, 'status', 'rejected');

  elsif p_action = 'pay' then
    if v_req.status not in ('requested', 'approved') then
      raise exception 'Yêu cầu rút tiền đã được xử lý trước đó';
    end if;
    select array_agg(id) into v_comm_ids
    from public.commissions
    where affiliate_id = v_req.affiliate_id and status = 'available';

    if v_comm_ids is null or array_length(v_comm_ids, 1) = 0 then
      raise exception 'Không có hoa hồng ở trạng thái khả dụng để chi trả';
    end if;

    v_pay_result := public.admin_pay_commissions(
      v_req.affiliate_id,
      v_comm_ids,
      p_transaction_ref,
      coalesce(nullif(trim(coalesce(p_note, '')), ''), 'Chi trả theo yêu cầu rút tiền #' || left(p_request_id::text, 8)),
      'payout_req:' || p_request_id::text
    );
    update public.payout_requests
    set status = 'paid',
        payout_id = (v_pay_result->>'payout_id')::uuid,
        reviewed_at = now(),
        reviewed_by = auth.uid()
    where id = p_request_id;

    return v_pay_result;
  else
    raise exception 'Hành động không hợp lệ (chỉ nhận approve, reject, pay)';
  end if;
end;
$$;

revoke all on function public.admin_review_payout_request(uuid, text, text, text, text) from public;
grant execute on function public.admin_review_payout_request(uuid, text, text, text, text) to authenticated;

-- 7. Cập nhật ctv_overview để trả thêm clicks_count, conversion_rate, locked_payout_amount, bank_status
create or replace function public.ctv_overview()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff record;
  v_total_orders bigint := 0;
  v_pending bigint := 0;
  v_holding bigint := 0;
  v_available bigint := 0;
  v_paid bigint := 0;
  v_clicks bigint := 0;
  v_locked bigint := 0;
  v_bank_status text := 'none';
  v_conv numeric := 0;
begin
  select * into v_aff from public.affiliates where user_id = auth.uid();
  if not found then
    raise exception 'Không tìm thấy hồ sơ CTV';
  end if;

  select count(*) into v_total_orders
  from public.orders where affiliate_id = v_aff.id and status <> 'cancelled';

  select count(*) into v_clicks
  from public.referral_clicks where affiliate_id = v_aff.id;

  select coalesce(sum(amount), 0) into v_pending
  from public.commissions where affiliate_id = v_aff.id and status = 'pending';

  select coalesce(sum(amount), 0) into v_holding
  from public.commissions where affiliate_id = v_aff.id and status = 'holding';

  select coalesce(sum(balance_impact), 0) into v_available
  from public.commission_ledger
  where affiliate_id = v_aff.id;

  select coalesce(sum(net_amount), 0) into v_paid
  from public.commission_payouts where affiliate_id = v_aff.id;

  select coalesce(sum(amount), 0) into v_locked
  from public.payout_requests where affiliate_id = v_aff.id and status in ('requested', 'approved');

  select coalesce(status, 'none') into v_bank_status
  from public.affiliate_bank_accounts where affiliate_id = v_aff.id;

  if v_clicks > 0 then
    v_conv := round((v_total_orders::numeric / v_clicks::numeric) * 100, 1);
  end if;

  return jsonb_build_object(
    'total_orders', v_total_orders,
    'clicks_count', v_clicks,
    'conversion_rate', v_conv,
    'pending_commission', v_pending,
    'holding_commission', v_holding,
    'available_commission', v_available,
    'locked_payout_amount', v_locked,
    'withdrawable_commission', greatest(0, v_available - v_locked),
    'paid_commission', v_paid,
    'bank_status', coalesce(v_bank_status, 'none'),
    'commission_rate', v_aff.commission_rate,
    'status', v_aff.status,
    'reject_reason', v_aff.reject_reason
  );
end;
$$;

revoke all on function public.ctv_overview() from public;
grant execute on function public.ctv_overview() to authenticated;

-- 8. Chi tiết đơn hàng & cập nhật trạng thái thanh toán (P1-5)
create or replace function public.admin_get_order_detail(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order jsonb;
  v_items jsonb;
  v_comm jsonb;
  v_logs jsonb;
begin
  if not public.has_permission('orders') then
    raise exception 'Không có quyền xem chi tiết đơn hàng';
  end if;

  select row_to_json(o)::jsonb into v_order
  from public.orders o where o.id = p_order_id;
  if v_order is null then
    raise exception 'Không tìm thấy đơn hàng';
  end if;

  select coalesce(jsonb_agg(row_to_json(oi)), '[]'::jsonb) into v_items
  from public.order_items oi where oi.order_id = p_order_id;

  select coalesce(jsonb_agg(row_to_json(c)), '[]'::jsonb) into v_comm
  from public.commissions c where c.order_id = p_order_id;

  select coalesce(jsonb_agg(row_to_json(l)), '[]'::jsonb) into v_logs
  from (
    select id, actor_role, action, old_data, new_data, reason, created_at
    from public.audit_logs
    where record_id = p_order_id::text
    order by created_at desc
    limit 20
  ) l;

  return jsonb_build_object(
    'order', v_order,
    'order_items', v_items,
    'commissions', v_comm,
    'audit_logs', v_logs
  );
end;
$$;

revoke all on function public.admin_get_order_detail(uuid) from public;
grant execute on function public.admin_get_order_detail(uuid) to authenticated;

create or replace function public.admin_set_payment_status(
  p_order_id uuid,
  p_payment_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old text;
begin
  if not public.has_permission('orders') then
    raise exception 'Không có quyền cập nhật trạng thái thanh toán';
  end if;

  if p_payment_status not in ('unpaid', 'paid', 'refunded') then
    raise exception 'Trạng thái thanh toán không hợp lệ';
  end if;

  select payment_status into v_old from public.orders where id = p_order_id;
  if not found then
    raise exception 'Không tìm thấy đơn hàng';
  end if;

  update public.orders
  set payment_status = p_payment_status, updated_at = now(), updated_by = auth.uid()
  where id = p_order_id;

  perform public.write_audit_log(
    'admin_set_payment_status', 'orders', p_order_id::text,
    jsonb_build_object('payment_status', v_old),
    jsonb_build_object('payment_status', p_payment_status)
  );

  return jsonb_build_object('ok', true, 'payment_status', p_payment_status);
end;
$$;

revoke all on function public.admin_set_payment_status(uuid, text) from public;
grant execute on function public.admin_set_payment_status(uuid, text) to authenticated;

-- 9. Chi tiết CTV cho Admin (P1-6)
create or replace function public.admin_get_affiliate_detail(p_affiliate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_aff jsonb;
  v_bank jsonb;
  v_stats jsonb;
begin
  if not public.has_permission('affiliates') then
    raise exception 'Không có quyền xem hồ sơ CTV';
  end if;

  select row_to_json(a)::jsonb into v_aff
  from public.affiliates a where a.id = p_affiliate_id;
  if v_aff is null then
    raise exception 'Không tìm thấy CTV';
  end if;

  select row_to_json(b)::jsonb into v_bank
  from public.affiliate_bank_accounts b where b.affiliate_id = p_affiliate_id;

  select jsonb_build_object(
    'total_orders', (select count(*) from public.orders where affiliate_id = p_affiliate_id and status <> 'cancelled'),
    'total_revenue', (select coalesce(sum(total_amount), 0) from public.orders where affiliate_id = p_affiliate_id and status = 'completed'),
    'clicks_count', (select count(*) from public.referral_clicks where affiliate_id = p_affiliate_id),
    'available_balance', (
      select coalesce(sum(balance_impact), 0) from public.commission_ledger
      where affiliate_id = p_affiliate_id
    ),
    'paid_total', (select coalesce(sum(net_amount), 0) from public.commission_payouts where affiliate_id = p_affiliate_id)
  ) into v_stats;

  return jsonb_build_object(
    'affiliate', v_aff,
    'bank', v_bank,
    'stats', v_stats
  );
end;
$$;

revoke all on function public.admin_get_affiliate_detail(uuid) from public;
grant execute on function public.admin_get_affiliate_detail(uuid) to authenticated;

-- 10. RLS quản trị Sản phẩm, Danh mục, Mã giảm giá, Quy tắc HH, Cài đặt (P1-7)
drop policy if exists "admin_manage_categories" on public.product_categories;
create policy "admin_manage_categories"
  on public.product_categories for all
  to authenticated
  using (public.has_permission('products'))
  with check (public.has_permission('products'));

drop policy if exists "admin_manage_products" on public.products;
create policy "admin_manage_products"
  on public.products for all
  to authenticated
  using (public.has_permission('products'))
  with check (public.has_permission('products'));

drop policy if exists "admin_manage_coupons" on public.coupons;
create policy "admin_manage_coupons"
  on public.coupons for all
  to authenticated
  using (public.has_permission('coupons'))
  with check (public.has_permission('coupons'));

drop policy if exists "admin_manage_commission_rules" on public.commission_rules;
create policy "admin_manage_commission_rules"
  on public.commission_rules for all
  to authenticated
  using (public.has_permission('products') or public.is_admin())
  with check (public.has_permission('products') or public.is_admin());

-- 11. RPC đọc Nhật ký hoạt động (P1-9)
create or replace function public.admin_list_audit_logs(
  p_entity_type text default 'all',
  p_search text default null,
  p_page int default 1,
  p_page_size int default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offset int := greatest(0, (coalesce(p_page, 1) - 1) * least(100, greatest(1, coalesce(p_page_size, 30))));
  v_limit int := least(100, greatest(1, coalesce(p_page_size, 30)));
  v_q text := nullif(trim(coalesce(p_search, '')), '');
  v_total bigint;
  v_items jsonb;
begin
  if not public.is_admin() then
    raise exception 'Chỉ Admin/Develop được xem nhật ký hoạt động';
  end if;

  select count(*) into v_total
  from public.audit_logs l
  where (p_entity_type is null or p_entity_type = 'all' or l.table_name = p_entity_type)
    and (v_q is null or l.action ilike '%' || v_q || '%' or l.record_id ilike '%' || v_q || '%');

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_items
  from (
    select
      l.id,
      l.actor_id as actor_user_id,
      l.actor_role,
      l.action,
      l.table_name as entity_type,
      l.record_id as entity_id,
      l.old_data,
      l.new_data,
      l.reason,
      l.created_at
    from public.audit_logs l
    where (p_entity_type is null or p_entity_type = 'all' or l.table_name = p_entity_type)
      and (v_q is null or l.action ilike '%' || v_q || '%' or l.record_id ilike '%' || v_q || '%')
    order by l.created_at desc
    offset v_offset limit v_limit
  ) t;

  return jsonb_build_object('total', v_total, 'items', v_items);
end;
$$;

revoke all on function public.admin_list_audit_logs(text, text, int, int) from public;
grant execute on function public.admin_list_audit_logs(text, text, int, int) to authenticated;

-- ============================================================================
-- ROLLBACK (ghi chú — chỉ chạy khi cần hoàn tác migration 005):
--   drop function if exists public.admin_list_audit_logs(text, text, int, int);
--   drop function if exists public.admin_get_affiliate_detail(uuid);
--   drop function if exists public.admin_set_payment_status(uuid, text);
--   drop function if exists public.admin_get_order_detail(uuid);
--   drop function if exists public.admin_review_payout_request(uuid, text, text, text, text);
--   drop function if exists public.admin_list_payout_requests(text, int, int);
--   drop function if exists public.ctv_list_payout_requests();
--   drop function if exists public.ctv_request_payout(bigint, text);
--   drop function if exists public.admin_verify_bank_account(uuid, text, text);
--   drop function if exists public.ctv_update_bank_account(text, text, text, text);
--   drop function if exists public.ctv_update_profile(text, text, text, text, text);
--   drop function if exists public.ctv_get_profile();
--   drop function if exists public.track_click(text, text, text);
--   drop table if exists public.referral_clicks;
--   drop table if exists public.payout_requests;
--   drop table if exists public.affiliate_bank_accounts;
-- ============================================================================

-- [MIGRATION: 20261125_006_p2_customers_reports.sql]
-- ============================================================================
-- P2-1, P2-3, P2-5: Báo cáo Dashboard, Quản lý Khách hàng & Reload Schema Cache
-- Thứ tự chạy: 006 (sau 005)
-- Idempotent: Có
-- ============================================================================

-- 1. Bảng Khách hàng gộp theo số điện thoại chuẩn hóa (P2-5, A17)
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  phone text not null unique,
  full_name text not null,
  address text,
  note text,
  total_orders int not null default 0,
  total_spent bigint not null default 0,
  last_order_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_customers_last_order on public.customers (last_order_at desc);

alter table public.customers enable row level security;

drop policy if exists "admin_read_customers" on public.customers;
create policy "admin_read_customers"
  on public.customers for select
  to authenticated
  using (public.has_permission('orders') or public.is_admin());

-- Backfill khách hàng từ đơn hàng hiện có (idempotent)
insert into public.customers (phone, full_name, address, total_orders, total_spent, last_order_at)
select
  regexp_replace(coalesce(o.phone, ''), '[^0-9]', '', 'g') as phone,
  (array_agg(o.customer_name order by o.created_at desc))[1] as full_name,
  (array_agg(o.address order by o.created_at desc))[1] as address,
  count(*) filter (where o.status <> 'cancelled')::int as total_orders,
  coalesce(sum(o.total_amount) filter (where o.status = 'completed'), 0)::bigint as total_spent,
  max(o.created_at) as last_order_at
from public.orders o
where length(regexp_replace(coalesce(o.phone, ''), '[^0-9]', '', 'g')) >= 9
group by regexp_replace(coalesce(o.phone, ''), '[^0-9]', '', 'g')
on conflict (phone) do update
set full_name = excluded.full_name,
    address = coalesce(excluded.address, public.customers.address),
    total_orders = excluded.total_orders,
    total_spent = excluded.total_spent,
    last_order_at = excluded.last_order_at,
    updated_at = now();

-- Trigger đồng bộ khách hàng khi có đơn mới hoặc đổi trạng thái đơn
create or replace function public.sync_customer_from_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := regexp_replace(coalesce(new.phone, ''), '[^0-9]', '', 'g');
  v_cnt int;
  v_spent bigint;
  v_last timestamptz;
begin
  if length(v_phone) < 9 then
    return new;
  end if;

  select
    count(*) filter (where status <> 'cancelled')::int,
    coalesce(sum(total_amount) filter (where status = 'completed'), 0)::bigint,
    max(created_at)
  into v_cnt, v_spent, v_last
  from public.orders
  where regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') = v_phone;

  insert into public.customers (phone, full_name, address, total_orders, total_spent, last_order_at)
  values (v_phone, new.customer_name, new.address, coalesce(v_cnt, 0), coalesce(v_spent, 0), v_last)
  on conflict (phone) do update
  set full_name = excluded.full_name,
      address = coalesce(excluded.address, public.customers.address),
      total_orders = excluded.total_orders,
      total_spent = excluded.total_spent,
      last_order_at = excluded.last_order_at,
      updated_at = now();

  return new;
end;
$$;

drop trigger if exists trg_sync_customer_from_order on public.orders;
create trigger trg_sync_customer_from_order
after insert or update of status, total_amount on public.orders
for each row execute function public.sync_customer_from_order();

-- RPC danh sách khách hàng & cập nhật ghi chú (P2-5)
create or replace function public.admin_list_customers(
  p_search text default null,
  p_page int default 1,
  p_page_size int default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_offset int := greatest(0, (coalesce(p_page, 1) - 1) * least(100, greatest(1, coalesce(p_page_size, 20))));
  v_limit int := least(100, greatest(1, coalesce(p_page_size, 20)));
  v_q text := nullif(trim(coalesce(p_search, '')), '');
  v_total bigint;
  v_items jsonb;
begin
  if not public.has_permission('orders') then
    raise exception 'Không có quyền xem danh sách khách hàng';
  end if;

  select count(*) into v_total
  from public.customers c
  where (v_q is null or c.full_name ilike '%' || v_q || '%' or c.phone ilike '%' || v_q || '%' or coalesce(c.address, '') ilike '%' || v_q || '%');

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_items
  from (
    select id, phone, full_name, address, note, total_orders, total_spent, last_order_at, created_at
    from public.customers c
    where (v_q is null or c.full_name ilike '%' || v_q || '%' or c.phone ilike '%' || v_q || '%' or coalesce(c.address, '') ilike '%' || v_q || '%')
    order by last_order_at desc nulls last
    offset v_offset limit v_limit
  ) t;

  return jsonb_build_object('total', v_total, 'items', v_items);
end;
$$;

revoke all on function public.admin_list_customers(text, int, int) from public;
grant execute on function public.admin_list_customers(text, int, int) to authenticated;

create or replace function public.admin_update_customer_note(
  p_customer_id uuid,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('orders') then
    raise exception 'Không có quyền cập nhật ghi chú khách hàng';
  end if;

  update public.customers
  set note = nullif(trim(coalesce(p_note, '')), ''), updated_at = now()
  where id = p_customer_id;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_update_customer_note(uuid, text) from public;
grant execute on function public.admin_update_customer_note(uuid, text) to authenticated;

-- 2. Báo cáo Dashboard Admin theo khoảng ngày (P2-3, A18, A19, A20)
create or replace function public.admin_reports(
  p_from timestamptz default (now() - interval '30 days'),
  p_to timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from timestamptz := coalesce(p_from, now() - interval '30 days');
  v_to timestamptz := coalesce(p_to, now());
  v_summary jsonb;
  v_daily jsonb;
  v_top_ctv jsonb;
  v_top_products jsonb;
begin
  if not public.is_staff_or_admin() then
    raise exception 'Không có quyền xem báo cáo';
  end if;

  select jsonb_build_object(
    'total_orders', count(*),
    'completed_orders', count(*) filter (where status = 'completed'),
    'cancelled_orders', count(*) filter (where status = 'cancelled'),
    'returned_orders', count(*) filter (where status = 'returned'),
    'cancel_rate', case when count(*) > 0 then round(((count(*) filter (where status in ('cancelled', 'returned')))::numeric / count(*)::numeric) * 100, 1) else 0 end,
    'gross_revenue', coalesce(sum(total_amount) filter (where status <> 'cancelled'), 0),
    'completed_revenue', coalesce(sum(total_amount) filter (where status = 'completed'), 0),
    'total_commission', coalesce(sum(commission_amount) filter (where status not in ('cancelled', 'returned')), 0)
  ) into v_summary
  from public.orders
  where created_at >= v_from and created_at <= v_to;

  select coalesce(jsonb_agg(row_to_json(d)), '[]'::jsonb) into v_daily
  from (
    select
      to_char(date_trunc('day', created_at at time zone 'Asia/Ho_Chi_Minh'), 'YYYY-MM-DD') as day,
      count(*) filter (where status <> 'cancelled') as orders,
      coalesce(sum(total_amount) filter (where status <> 'cancelled'), 0) as revenue
    from public.orders
    where created_at >= v_from and created_at <= v_to
    group by 1
    order by 1 asc
  ) d;

  select coalesce(jsonb_agg(row_to_json(c)), '[]'::jsonb) into v_top_ctv
  from (
    select
      a.code,
      a.full_name,
      count(o.id) filter (where o.status <> 'cancelled') as orders,
      coalesce(sum(o.total_amount) filter (where o.status = 'completed'), 0) as completed_revenue,
      coalesce(sum(o.commission_amount) filter (where o.status not in ('cancelled', 'returned')), 0) as total_commission
    from public.orders o
    join public.affiliates a on a.id = o.affiliate_id
    where o.created_at >= v_from and o.created_at <= v_to
    group by a.id, a.code, a.full_name
    order by completed_revenue desc, orders desc
    limit 10
  ) c;

  select coalesce(jsonb_agg(row_to_json(p)), '[]'::jsonb) into v_top_products
  from (
    select
      oi.product_name,
      sum(oi.quantity)::bigint as qty,
      sum(oi.line_total)::bigint as revenue
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where o.created_at >= v_from and o.created_at <= v_to
      and o.status <> 'cancelled'
    group by oi.product_name
    order by revenue desc
    limit 10
  ) p;

  return jsonb_build_object(
    'summary', v_summary,
    'daily', v_daily,
    'top_affiliates', v_top_ctv,
    'top_products', v_top_products
  );
end;
$$;

revoke all on function public.admin_reports(timestamptz, timestamptz) from public;
grant execute on function public.admin_reports(timestamptz, timestamptz) to authenticated;

-- Làm mới schema cache của PostgREST ngay sau khi chạy migration
notify pgrst, 'reload schema';

-- ============================================================================
-- ROLLBACK (ghi chú — chỉ chạy khi cần hoàn tác migration 006):
--   drop function if exists public.admin_reports(timestamptz, timestamptz);
--   drop function if exists public.admin_update_customer_note(uuid, text);
--   drop function if exists public.admin_list_customers(text, int, int);
--   drop trigger if exists trg_sync_customer_from_order on public.orders;
--   drop function if exists public.sync_customer_from_order();
--   drop table if exists public.customers;
-- ============================================================================


-- ============================================================================
-- MIGRATION 007 (20261125_007_p0_permissions_catalog_audit.sql)
-- ============================================================================
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
-- ============================================================
-- MIGRATION 008: RPC đọc cho Admin (leads / affiliates / payouts) + giá catalog public
-- Mục tiêu:
--   (A) admin.vue không còn truy cập trực tiếp bảng leads, affiliates, commission_payouts
--       và không còn giới hạn cứng 150 dòng -> phân trang server-side, có lọc/tìm kiếm.
--   (B) Đổi trạng thái lead đi qua RPC có ghi audit log (trước đây UPDATE trực tiếp, không audit).
--   (C) Trang chi tiết sản phẩm lấy giá từ bảng products (nguồn sự thật của create_order),
--       tránh lệch giữa giá hiển thị (MAT_PRICING hard-code) và giá server tính.
--
-- Chạy SAU migration 007. An toàn khi chạy lại (idempotent).
--
-- ROLLBACK (chạy thủ công nếu cần):
-- drop function if exists public.admin_list_leads(text, text, int, int);
-- drop function if exists public.admin_update_lead_status(uuid, text, text);
-- drop function if exists public.admin_list_affiliates(text, text, int, int);
-- drop function if exists public.admin_list_payouts(text, timestamptz, timestamptz, int, int);
-- drop function if exists public.get_catalog_prices();
-- (Quyền ghi trực tiếp trên leads/commission_payouts đã bị thu hồi: grant lại thủ công nếu thật sự cần.)
-- ============================================================

-- ------------------------------------------------------------
-- 1. Thu hồi ghi trực tiếp trên leads & commission_payouts
--    (mọi thay đổi phải đi qua RPC security definer có audit)
-- ------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'leads'
      and cmd in ('INSERT', 'UPDATE', 'DELETE')
  loop
    execute format('drop policy if exists %I on public.leads', r.policyname);
  end loop;
end;
$$;

revoke insert, update, delete on public.leads from anon, authenticated;
revoke insert, update, delete on public.commission_payouts from anon, authenticated;

-- ------------------------------------------------------------
-- 2. RPC: danh sách lead (phân trang, lọc trạng thái, tìm kiếm)
-- ------------------------------------------------------------
create or replace function public.admin_list_leads(
  p_status text default null,
  p_search text default null,
  p_page int default 1,
  p_page_size int default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_page int := greatest(1, coalesce(p_page, 1));
  v_offset int := (greatest(1, coalesce(p_page, 1)) - 1) * least(100, greatest(1, coalesce(p_page_size, 25)));
  v_status text := nullif(trim(coalesce(p_status, '')), '');
  v_search text := lower(trim(coalesce(p_search, '')));
  v_total bigint;
  v_items jsonb;
begin
  if auth.uid() is null or not public.is_staff_or_admin() then
    raise exception 'Bạn không có quyền xem yêu cầu tư vấn';
  end if;

  select count(*) into v_total
  from public.leads l
  where (v_status is null or l.status = v_status)
    and (
      v_search = ''
      or position(v_search in lower(l.customer_name)) > 0
      or position(v_search in coalesce(l.phone, '')) > 0
      or position(v_search in lower(coalesce(l.vehicle, ''))) > 0
      or position(v_search in lower(coalesce(l.affiliate_code, ''))) > 0
    );

  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc, t.id), '[]'::jsonb) into v_items
  from (
    select l.id, l.customer_name, l.phone, l.vehicle, l.message, l.affiliate_code, l.status, l.created_at
    from public.leads l
    where (v_status is null or l.status = v_status)
      and (
        v_search = ''
        or position(v_search in lower(l.customer_name)) > 0
        or position(v_search in coalesce(l.phone, '')) > 0
        or position(v_search in lower(coalesce(l.vehicle, ''))) > 0
        or position(v_search in lower(coalesce(l.affiliate_code, ''))) > 0
      )
    order by l.created_at desc, l.id
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_limit);
end;
$$;

revoke all on function public.admin_list_leads(text, text, int, int) from public;
grant execute on function public.admin_list_leads(text, text, int, int) to authenticated;

-- ------------------------------------------------------------
-- 3. RPC: đổi trạng thái lead (có audit)
-- ------------------------------------------------------------
create or replace function public.admin_update_lead_status(
  p_lead_id uuid,
  p_status text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old public.leads;
  v_new public.leads;
begin
  if auth.uid() is null or not public.is_staff_or_admin() then
    raise exception 'Bạn không có quyền cập nhật yêu cầu tư vấn';
  end if;

  if p_status is null or p_status not in ('new', 'contacted', 'closed') then
    raise exception 'Trạng thái yêu cầu tư vấn không hợp lệ';
  end if;

  select * into v_old from public.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Không tìm thấy yêu cầu tư vấn';
  end if;

  if v_old.status = p_status then
    return to_jsonb(v_old);
  end if;

  update public.leads set status = p_status where id = p_lead_id returning * into v_new;

  perform public.write_audit_log(
    'admin_update_lead_status', 'leads', p_lead_id::text,
    jsonb_build_object('status', v_old.status),
    jsonb_build_object('status', v_new.status),
    p_reason
  );

  return to_jsonb(v_new);
end;
$$;

revoke all on function public.admin_update_lead_status(uuid, text, text) from public;
grant execute on function public.admin_update_lead_status(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- 4. RPC: danh sách CTV / tài khoản (phân trang, lọc trạng thái, tìm kiếm)
-- ------------------------------------------------------------
create or replace function public.admin_list_affiliates(
  p_status text default null,
  p_search text default null,
  p_page int default 1,
  p_page_size int default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_page int := greatest(1, coalesce(p_page, 1));
  v_offset int := (greatest(1, coalesce(p_page, 1)) - 1) * least(100, greatest(1, coalesce(p_page_size, 25)));
  v_status text := nullif(trim(coalesce(p_status, '')), '');
  v_search text := lower(trim(coalesce(p_search, '')));
  v_total bigint;
  v_items jsonb;
begin
  if auth.uid() is null or not public.has_permission('affiliates') then
    raise exception 'Bạn không có quyền xem danh sách cộng tác viên';
  end if;

  select count(*) into v_total
  from public.affiliates a
  where (v_status is null or a.status = v_status)
    and (
      v_search = ''
      or position(v_search in lower(a.code)) > 0
      or position(v_search in lower(a.full_name)) > 0
      or position(v_search in lower(a.email)) > 0
      or position(v_search in coalesce(a.phone, '')) > 0
    );

  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc, t.id), '[]'::jsonb) into v_items
  from (
    select a.id, a.user_id, a.code, a.full_name, a.email, a.phone, a.zalo, a.area, a.job_type,
           a.role, a.commission_rate, a.status, a.created_at, a.approved_at, a.reject_reason
    from public.affiliates a
    where (v_status is null or a.status = v_status)
      and (
        v_search = ''
        or position(v_search in lower(a.code)) > 0
        or position(v_search in lower(a.full_name)) > 0
        or position(v_search in lower(a.email)) > 0
        or position(v_search in coalesce(a.phone, '')) > 0
      )
    order by a.created_at desc, a.id
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_limit);
end;
$$;

revoke all on function public.admin_list_affiliates(text, text, int, int) from public;
grant execute on function public.admin_list_affiliates(text, text, int, int) to authenticated;

-- ------------------------------------------------------------
-- 5. RPC: lịch sử chi trả hoa hồng (phân trang, lọc ngày, tìm kiếm)
-- ------------------------------------------------------------
create or replace function public.admin_list_payouts(
  p_search text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_page int default 1,
  p_page_size int default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit int := least(100, greatest(1, coalesce(p_page_size, 25)));
  v_page int := greatest(1, coalesce(p_page, 1));
  v_offset int := (greatest(1, coalesce(p_page, 1)) - 1) * least(100, greatest(1, coalesce(p_page_size, 25)));
  v_search text := lower(trim(coalesce(p_search, '')));
  v_total bigint;
  v_items jsonb;
begin
  if auth.uid() is null or not public.has_permission('payouts') then
    raise exception 'Bạn không có quyền xem lịch sử chi trả';
  end if;

  select count(*) into v_total
  from public.commission_payouts p
  where (p_from is null or p.paid_at >= p_from)
    and (p_to is null or p.paid_at <= p_to)
    and (
      v_search = ''
      or position(v_search in lower(p.affiliate_code)) > 0
      or position(v_search in lower(coalesce(p.transaction_ref, ''))) > 0
    );

  select coalesce(jsonb_agg(to_jsonb(t) order by t.paid_at desc, t.id), '[]'::jsonb) into v_items
  from (
    select p.id, p.affiliate_id, p.affiliate_code, p.amount, p.order_count, p.note, p.paid_at,
           p.gross_amount, p.tax_amount, p.net_amount, p.transaction_ref
    from public.commission_payouts p
    where (p_from is null or p.paid_at >= p_from)
      and (p_to is null or p.paid_at <= p_to)
      and (
        v_search = ''
        or position(v_search in lower(p.affiliate_code)) > 0
        or position(v_search in lower(coalesce(p.transaction_ref, ''))) > 0
      )
    order by p.paid_at desc, p.id
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object('items', v_items, 'total', v_total, 'page', v_page, 'page_size', v_limit);
end;
$$;

revoke all on function public.admin_list_payouts(text, timestamptz, timestamptz, int, int) from public;
grant execute on function public.admin_list_payouts(text, timestamptz, timestamptz, int, int) to authenticated;

-- ------------------------------------------------------------
-- 6. RPC public: bảng giá catalog (chỉ sản phẩm đang bán, chỉ cột cần hiển thị)
--    Cùng nguồn dữ liệu với create_order => giá hiển thị = giá server tính.
-- ------------------------------------------------------------
create or replace function public.get_catalog_prices()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'sku', p.sku,
        'name', p.name,
        'product_type', p.product_type,
        'base_price', p.base_price,
        'image_url', p.image_url
      )
      order by p.product_type, p.base_price, p.sku
    ),
    '[]'::jsonb
  )
  from public.products p
  where p.is_active = true;
$$;

revoke all on function public.get_catalog_prices() from public;
grant execute on function public.get_catalog_prices() to anon, authenticated;

