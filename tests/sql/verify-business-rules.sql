-- ============================================================================
-- BỘ KIỂM THỬ TỰ ĐỘNG 5 FOCUS AREAS TRÊN SUPABASE POSTGRES (TRANSACTIONAL)
-- Chạy trong Supabase Dashboard -> SQL Editor.
-- Toàn bộ chạy trong BEGIN ... ROLLBACK nên KHÔNG để lại dữ liệu rác!
-- ============================================================================

begin;

do $$
declare
  v_admin_uid uuid := gen_random_uuid();
  v_ctv_a_uid uuid := gen_random_uuid();
  v_ctv_b_uid uuid := gen_random_uuid();
  v_ctv_a_id uuid;
  v_ctv_b_id uuid;
  v_order_res jsonb;
  v_order_id uuid;
  v_self_order jsonb;
  v_ctv_b_orders jsonb;
  v_stock_before int;
  v_stock_after_create int;
  v_stock_after_cancel int;
  v_err text;
begin
  -- Tạo 3 auth user giả trong transaction
  insert into auth.users (id, email, aud, role, created_at, updated_at)
  values
    (v_admin_uid, 'test-admin@thamoto.local', 'authenticated', 'authenticated', now(), now()),
    (v_ctv_a_uid, 'test-ctv-a@thamoto.local', 'authenticated', 'authenticated', now(), now()),
    (v_ctv_b_uid, 'test-ctv-b@thamoto.local', 'authenticated', 'authenticated', now(), now());

  -- Bật cờ trusted_rpc CHỈ trong bước setup fixture test, sau đó tắt ngay trước khi chạy assert
  perform set_config('app.trusted_rpc', 'develop_rpc', true);

  insert into public.affiliates (user_id, code, full_name, email, phone, role, status, commission_rate)
  values (v_admin_uid, 'TADMIN01', 'Test Admin', 'test-admin@thamoto.local', '0900000111', 'admin', 'active', 0)
  on conflict (user_id) do update
  set code = excluded.code, full_name = excluded.full_name, phone = excluded.phone,
      role = excluded.role, status = excluded.status, commission_rate = excluded.commission_rate;

  insert into public.affiliates (user_id, code, full_name, email, phone, role, status, commission_rate)
  values (v_ctv_a_uid, 'TCTVA01', 'CTV Alpha', 'test-ctv-a@thamoto.local', '0911222333', 'ctv', 'active', 10)
  on conflict (user_id) do update
  set code = excluded.code, full_name = excluded.full_name, phone = excluded.phone,
      role = excluded.role, status = excluded.status, commission_rate = excluded.commission_rate
  returning id into v_ctv_a_id;

  insert into public.affiliates (user_id, code, full_name, email, phone, role, status, commission_rate)
  values (v_ctv_b_uid, 'TCTVB01', 'CTV Beta', 'test-ctv-b@thamoto.local', '0944555666', 'ctv', 'active', 10)
  on conflict (user_id) do update
  set code = excluded.code, full_name = excluded.full_name, phone = excluded.phone,
      role = excluded.role, status = excluded.status, commission_rate = excluded.commission_rate
  returning id into v_ctv_b_id;

  perform set_config('app.trusted_rpc', '', true);

  -- Đặt tồn kho thử nghiệm cho MAT-TPE = 10
  update public.products set stock_qty = 10 where sku = 'MAT-TPE';
  select stock_qty into v_stock_before from public.products where sku = 'MAT-TPE';

  -- [AREA 1 & 2] Đặt đơn với mã CTV hợp lệ + mã giảm giá GIAM5
  v_order_res := public.create_order(
    p_customer_name => 'Nguyễn Văn Khách',
    p_phone => '0988777666',
    p_address => '123 Yên Lãng, Hà Nội',
    p_payment_method => 'COD',
    p_coupon_code => 'GIAM5',
    p_affiliate_code => 'TCTVA01',
    p_ref_source => 'link',
    p_items => jsonb_build_array(jsonb_build_object(
      'name', 'Thảm Nhựa TPE Toyota Fortuner',
      'material', 'Thảm Nhựa TPE Đúc Khuôn',
      'quantity', 2,
      'price', 1
    ))
  );
  v_order_id := (v_order_res->>'order_id')::uuid;
  assert (v_order_res->>'total_amount')::bigint > 1000000, 'FAIL: Server phải tính giá theo DB, không lấy price=1 từ client';
  assert (select commission_amount from public.orders where id = v_order_id) > 0, 'FAIL: Đơn hợp lệ của TCTVA01 phải có hoa hồng > 0';

  -- [AREA 4] Kiểm tra tồn kho giảm sau khi đặt (nếu đã chạy migration 007)
  select stock_qty into v_stock_after_create from public.products where sku = 'MAT-TPE';
  if exists (select 1 from pg_trigger where tgname = 'trg_deduct_stock_on_order_item') then
    assert v_stock_after_create = v_stock_before - 2, 'FAIL: Tồn kho phải giảm đúng 2 sau khi đặt đơn';
  end if;

  -- [AREA 2] Self-referral: CTV tự mua bằng SĐT của chính mình -> commission = 0
  v_self_order := public.create_order(
    p_customer_name => 'CTV Alpha',
    p_phone => '0911222333',
    p_address => 'Hà Nội',
    p_payment_method => 'COD',
    p_affiliate_code => 'TCTVA01',
    p_ref_source => 'link',
    p_items => jsonb_build_array(jsonb_build_object(
      'name', 'Thảm 6D Cao Cấp',
      'material', 'Thảm 6D Cao Cấp',
      'quantity', 1
    ))
  );
  assert (select commission_amount from public.orders where id = (v_self_order->>'order_id')::uuid) = 0, 'FAIL: Self-referral phải có hoa hồng = 0';

  -- [AREA 3] Giả lập JWT là CTV B: không được thấy đơn của CTV A và không được gọi API Admin
  perform set_config('request.jwt.claim.sub', v_ctv_b_uid::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  v_ctv_b_orders := public.ctv_list_orders(null, null, 1, 20);
  assert (v_ctv_b_orders->>'total')::int = 0, 'FAIL: CTV B không được thấy đơn của CTV A';

  begin
    perform public.admin_overview(null, null);
    raise exception 'FAIL: CTV B không được phép gọi admin_overview';
  exception when others then
    v_err := sqlerrm;
    assert v_err not like 'FAIL:%', v_err;
  end;

  -- [AREA 3] Giả lập JWT là CTV A: phải thấy đơn của mình NHƯNG đã che PII
  perform set_config('request.jwt.claim.sub', v_ctv_a_uid::text, true);
  v_ctv_b_orders := public.ctv_list_orders(null, null, 1, 20);
  assert (v_ctv_b_orders->>'total')::int >= 1, 'FAIL: CTV A phải thấy đơn của mình';
  assert not ((v_ctv_b_orders->'items'->0) ? 'phone'), 'FAIL: CTV không được thấy cột phone';
  assert not ((v_ctv_b_orders->'items'->0) ? 'address'), 'FAIL: CTV không được thấy cột address';

  -- [AREA 4 & 5] Giả lập JWT là Admin: đổi trạng thái hợp lệ, chặn đổi ngược, hủy hoàn tồn kho & ghi audit log
  perform set_config('request.jwt.claim.sub', v_admin_uid::text, true);
  perform public.admin_set_order_status(v_order_id, 'confirmed', null, null);
  perform public.admin_set_order_status(v_order_id, 'cancelled', 'Khách đổi ý', null);

  if exists (select 1 from pg_trigger where tgname = 'trg_restore_stock_on_order_cancel') then
    select stock_qty into v_stock_after_cancel from public.products where sku = 'MAT-TPE';
    assert v_stock_after_cancel = v_stock_before, 'FAIL: Tồn kho phải hoàn lại đúng ban đầu khi hủy đơn';
  end if;

  begin
    perform public.admin_set_order_status(v_order_id, 'completed', null, null);
    raise exception 'FAIL: Không được phép chuyển từ cancelled sang completed';
  exception when others then
    v_err := sqlerrm;
    assert v_err not like 'FAIL:%', v_err;
  end;

  -- [AREA 5] Admin khóa CTV B -> kiểm tra đổi trạng thái + có audit_logs
  perform public.admin_update_affiliate(v_ctv_b_id, 'suspended', null, 'Kiểm thử khóa CTV');
  assert exists (
    select 1 from public.audit_logs
    where table_name = 'affiliates' and record_id = v_ctv_b_id::text and action = 'admin_update_affiliate'
  ), 'FAIL: Khóa CTV phải ghi audit_logs';

  raise notice 'ALL 5 FOCUS AREAS PASSED SUCCESSFULLY!';
end $$;

rollback;
