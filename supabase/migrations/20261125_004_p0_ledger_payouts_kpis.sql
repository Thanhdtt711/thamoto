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
