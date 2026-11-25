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
