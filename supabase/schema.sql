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
