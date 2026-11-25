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
