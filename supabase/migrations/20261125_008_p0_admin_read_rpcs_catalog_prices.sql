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
