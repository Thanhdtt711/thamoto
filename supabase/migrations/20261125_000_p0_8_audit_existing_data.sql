-- ============================================================
-- P0-8: TRUY VẤN RÀ SOÁT DỮ LIỆU HIỆN CÓ (CHỈ ĐỌC - KHÔNG SỬA DB)
-- Chạy trong Supabase Dashboard -> SQL Editor trước khi chạy các migration P0
-- Thứ tự: 000 (chạy đầu tiên để chụp hiện trạng)
-- Rollback: Không cần (chỉ là câu lệnh SELECT)
-- ============================================================

-- 1. Kiểm tra đơn hàng có trạng thái / giá trị bất thường
select
  id, order_code, status, commission_status, total_amount,
  affiliate_code, commission_rate, commission_amount, created_at
from public.orders
where total_amount <= 0
   or total_amount > 50000000
   or (status = 'new' and commission_status <> 'pending')
   or (status = 'cancelled' and commission_status in ('approved', 'paid'))
order by created_at desc;

-- 2. Kiểm tra đơn gắn mã CTV không tồn tại hoặc CTV không còn hoạt động
select
  o.id, o.order_code, o.affiliate_code, o.total_amount, o.commission_amount,
  a.status as affiliate_status, a.role as affiliate_role
from public.orders o
left join public.affiliates a on upper(a.code) = upper(o.affiliate_code)
where o.affiliate_code is not null
  and (a.id is null or a.status <> 'active')
order by o.created_at desc;

-- 3. Kiểm tra nghi ngờ CTV tự đặt đơn bằng mã của chính mình (trùng SĐT)
select
  o.id, o.order_code, o.customer_name, o.phone as order_phone,
  o.affiliate_code, a.full_name as affiliate_name, a.phone as affiliate_phone,
  o.total_amount, o.commission_amount, o.status, o.commission_status
from public.orders o
join public.affiliates a on upper(a.code) = upper(o.affiliate_code)
where regexp_replace(coalesce(o.phone, ''), '\D', '', 'g')
    = regexp_replace(coalesce(a.phone, ''), '\D', '', 'g')
order by o.created_at desc;

-- 4. Đối chiếu tổng hoa hồng đã đánh dấu paid trên orders vs tổng commission_payouts
with order_paid as (
  select upper(affiliate_code) as code,
         count(*) as paid_order_count,
         coalesce(sum(commission_amount), 0) as paid_from_orders
  from public.orders
  where affiliate_code is not null and commission_status = 'paid'
  group by upper(affiliate_code)
),
payout_sum as (
  select upper(affiliate_code) as code,
         count(*) as payout_batches,
         coalesce(sum(order_count), 0) as payout_order_count,
         coalesce(sum(amount), 0) as paid_from_payouts
  from public.commission_payouts
  group by upper(affiliate_code)
)
select
  coalesce(o.code, p.code) as affiliate_code,
  coalesce(o.paid_order_count, 0) as orders_paid_cnt,
  coalesce(p.payout_order_count, 0) as payouts_order_cnt,
  coalesce(o.paid_from_orders, 0) as orders_paid_sum,
  coalesce(p.paid_from_payouts, 0) as payouts_sum,
  coalesce(o.paid_from_orders, 0) - coalesce(p.paid_from_payouts, 0) as diff
from order_paid o
full outer join payout_sum p on o.code = p.code
order by abs(coalesce(o.paid_from_orders, 0) - coalesce(p.paid_from_payouts, 0)) desc;
