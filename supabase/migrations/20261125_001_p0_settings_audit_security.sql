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
