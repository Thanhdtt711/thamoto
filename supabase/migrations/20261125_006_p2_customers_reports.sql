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
