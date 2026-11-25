# HƯỚNG DẪN CHẠY MIGRATION, CẤU HÌNH & KIỂM THỬ T01–T43

> **Lưu ý quan trọng:** Agent không có quyền truy cập trực tiếp Supabase production của bạn. Toàn bộ thay đổi CSDL đã được viết dưới dạng **migration SQL idempotent** (chạy lại không lỗi) kèm ghi chú rollback ở cuối mỗi file.

---

## 1. Thứ tự chạy Migration trên Supabase SQL Editor

Chạy **đúng thứ tự** từ `000` đến `008` trong **Supabase Dashboard → SQL Editor**:

| Thứ tự | File migration | Nội dung chính | Điều kiện tiên quyết |
|---|---|---|---|
| 0 (Chỉ đọc) | `supabase/migrations/20261125_000_p0_8_audit_existing_data.sql` | Rà soát dữ liệu cũ (đơn bất thường, hoa hồng lệch, CTV trùng mã) | Chạy **trước** khi sửa schema; không ghi dữ liệu |
| 1 | `supabase/migrations/20261125_001_p0_settings_audit_security.sql` | `app_settings`, `audit_logs` bất biến, khóa leo thang quyền `affiliates`, `staff` + `permissions`, `admin_update_affiliate`, `develop_set_account_role` | Đã có schema nền (`affiliates`, `orders`, `leads`, `commission_payouts`) |
| 2 | `supabase/migrations/20261125_002_p0_catalog_coupons_create_order.sql` | `product_categories`, `products`, `coupons`, `commission_rules`, `order_items`, bỏ anon direct INSERT, RPC `create_order` / `create_lead` / `validate_coupon` / `validate_affiliate_code` | Sau `001` |
| 3 | `supabase/migrations/20261125_003_p0_ctv_pii_masking.sql` | Che PII khách hàng ở DB (`mask_customer_name`), thu hồi SELECT trực tiếp của CTV trên `orders`/`leads`, RPC `ctv_list_orders` / `ctv_list_leads` | Sau `002` |
| 4 | `supabase/migrations/20261125_004_p0_ledger_payouts_kpis.sql` | `commissions`, sổ cái `commission_ledger` (append-only + clawback), `payout_items`, bất biến `commission_payouts`, backfill dữ liệu cũ, `admin_set_order_status`, `admin_pay_commissions`, `ctv_overview`, `admin_overview`, `admin_list_orders`, `admin_settlement_summary` | Sau `003` |
| 5 | `supabase/migrations/20261125_005_p1_payout_requests_profile_clicks.sql` | `affiliate_bank_accounts`, `payout_requests`, `referral_clicks`, `track_click`, hồ sơ & ngân hàng CTV, duyệt/chi trả yêu cầu rút tiền, chi tiết đơn/CTV, RLS CRUD sản phẩm/coupon/quy tắc HH, `admin_list_audit_logs` | Sau `004` |
| 6 | `supabase/migrations/20261125_006_p2_customers_reports.sql` | `customers` + backfill & trigger đồng bộ, lọc khoảng ngày `admin_list_orders`, báo cáo Dashboard `admin_reports` | Sau `005` |
| 7a | `supabase/migrations/20261125_007_p0_permissions_catalog_audit.sql` | Chuẩn hóa quyền `staff` & audit catalog | Sau `006` |
| 7b | `supabase/migrations/20261125_007_p2_stock_sync.sql` | Trigger tự trừ tồn kho khi đặt đơn và hoàn 1 lần khi hủy/hoàn (`NULL` = không giới hạn) | Sau `007a` |
| 8 | `supabase/migrations/20261125_008_p0_admin_read_rpcs_catalog_prices.sql` | RPC đọc phân trang cho Admin (`leads`, `affiliates`, `payouts`) & `get_catalog_prices()` | Sau `007b` |
| 9 | `supabase/migrations/20261125_009_web_upgrade_p0_p1.sql` | Hoàn `used_count` coupon khi hủy, `expire_stale_orders`, `payment_events` + `system_mark_paid`, `admin_update_shipping`, `track_order`, `get_storefront_config`, `in_stock` trên `get_catalog_prices` | Sau `008` |
| 7 | `supabase/migrations/20261125_007_p0_permissions_catalog_audit.sql` | Đồng bộ tên quyền staff (`orders`, `payouts`, `affiliates`, `products`, `coupons`; tên cũ tự ánh xạ), trigger whitelist `permissions`, thu hồi ghi trực tiếp lên `products`/`coupons`/`commission_rules`/`app_settings`, RPC có audit: `admin_save_product`, `admin_save_coupon`, `admin_save_commission_rule` (không xóa cứng), `admin_update_setting` (kiểm tra khoảng giá trị) | Sau `006` |
| 8 | `supabase/migrations/20261125_008_p0_admin_read_rpcs_catalog_prices.sql` | Thu hồi ghi trực tiếp lên `leads`/`commission_payouts`; RPC có phân trang: `admin_list_leads`, `admin_list_affiliates`, `admin_list_payouts`; RPC có audit: `admin_update_lead_status`; RPC công khai `get_catalog_prices` (giá từ bảng `products`, cùng nguồn với `create_order`) | Sau `007` |

> **Sau migration 008:** `admin.vue` không còn `select` trực tiếp `leads`/`affiliates`/`commission_payouts`, không còn giới hạn 150 dòng (phân trang 25 dòng/trang, tối đa 100 dòng/lần gọi). Xuất CSV chi trả lặp qua các trang (tối đa 50 trang × 100 dòng). `chi-tiet.vue` lấy giá chất liệu và ưu đãi từ `get_catalog_prices`; `MAT_PRICING` chỉ là dữ liệu dự phòng khi chưa cấu hình Supabase hoặc RPC lỗi. Tên ưu đãi gửi vào giỏ trùng `products.name` để `create_order` tính đúng giá.

> **Sau migration 007:** `CatalogTab.vue` không còn ghi trực tiếp vào bảng; mọi thay đổi đều xuất hiện trong tab Nhật ký (`audit_logs`). Staff chỉ có `orders` sẽ không sửa được sản phẩm; quy tắc hoa hồng và cài đặt hệ thống chỉ Admin/Develop được đổi.

> **Rollback:** Mỗi file migration có sẵn đoạn `-- ROLLBACK` ở cuối file. Nếu cần hoàn tác, chạy theo thứ tự ngược (`006 → 005 → ... → 001`) và luôn backup DB trước khi rollback trên production.

---

## 2. Cấu hình vận hành sau khi chạy Migration

### 2.1. Lịch tự động mở khóa hoa hồng hết hạn Hold (`pg_cron`)
Trong Supabase Dashboard → Database → Extensions, bật `pg_cron` rồi chạy 1 lần trong SQL Editor:
```sql
select cron.schedule(
  'release-matured-commissions-daily',
  '0 2 * * *', -- 02:00 UTC (09:00 giờ VN) mỗi ngày
  $$ select public.release_matured_commissions(); $$
);
```
(Admin cũng có thể bấm nút **"Mở khóa đơn hết hạn Hold"** thủ công trong tab Đối soát bất cứ lúc nào.)

### 2.2. Triển khai Edge Function thông báo Telegram (P1-10 — tuỳ chọn)
```bash
supabase secrets set TELEGRAM_BOT_TOKEN="YOUR_BOT_TOKEN" TELEGRAM_CHAT_ID="YOUR_CHAT_ID" NOTIFY_WEBHOOK_SECRET="RANDOM_SECRET"
supabase functions deploy notify-order
```
Sau đó tạo Database Webhook trong Supabase Dashboard trỏ tới URL của `notify-order` với header `x-webhook-secret: RANDOM_SECRET` cho sự kiện `INSERT` trên `orders` và `payout_requests`.

### 2.3. Biến môi trường trên Vercel / môi trường chạy Nuxt
Đảm bảo chỉ cấu hình 2 biến public trên frontend (xem `.env.example`):
- `NUXT_PUBLIC_SUPABASE_URL`
- `NUXT_PUBLIC_SUPABASE_ANON_KEY`

---

## 3. Bộ câu lệnh SQL kiểm thử T01–T43 trên Supabase thật

### Nhóm Bảo mật & Toàn vẹn tiền (P0: T01–T25)

```sql
-- T01 & T02: Anon KHÔNG thể INSERT trực tiếp vào orders/leads (phải báo lỗi RLS 42501)
set local role anon;
insert into public.orders (order_code, customer_name, customer_phone, total)
values ('FAKE01', 'Hacker', '0900000000', 1);
-- Kỳ vọng: ERROR: new row violates row-level security policy for table "orders"
reset role;

-- T03: Kiểm tra create_order tính giá & coupon ở server, ép status='new'
select public.create_order(
  'Nguyễn Test', '0912345678', 'Hà Nội', 'COD',
  jsonb_build_array(jsonb_build_object('sku', 'tpe-5-cho', 'name', 'Thảm TPE', 'quantity', 1, 'unit_price', 1)),
  'GIAM5', null, 'link', null, null
);
-- Kỳ vọng: total tính theo giá DB của SKU tpe-5-cho (không nhận unit_price=1 từ client), status='new'.

-- T05 & T06: Kiểm tra Admin KHÔNG thể tự nâng role lên develop
-- (Chạy dưới JWT của 1 tài khoản role='admin')
update public.affiliates set role = 'develop' where user_id = auth.uid();
-- Kỳ vọng: ERROR do trigger guard_affiliates_sensitive_columns và RLS đã bỏ update trực tiếp.

-- T07: Kiểm tra develop không thể tự hạ quyền của chính mình
select public.develop_set_account_role(auth.uid(), 'admin');
-- Kỳ vọng: ERROR: Không thể tự hạ quyền của chính mình.

-- T09 & T10: Kiểm tra CTV KHÔNG thể SELECT trực tiếp bảng orders/leads & chỉ thấy tên che qua RPC
-- (Chạy dưới JWT của 1 CTV active)
select * from public.orders limit 1;
-- Kỳ vọng: 0 dòng (bị RLS chặn).
select public.ctv_list_orders(null, null, 1, 10);
-- Kỳ vọng: customer_name_masked dạng "Nguyễn***", không có cột customer_phone / customer_address.

-- T13 & T14: Kiểm tra vòng đời hoa hồng & thu hồi (clawback) khi hoàn đơn
-- 1) Đổi đơn sang completed -> commissions.status = 'holding', hold_until = now() + 7 days
-- 2) Gọi admin_approve_commissions -> available
-- 3) Gọi admin_pay_commissions (idempotency_key='test-key-1') -> paid
-- 4) Gọi lại admin_pay_commissions với cùng idempotency_key='test-key-1' -> trả lại payout cũ, không tạo bản ghi thứ 2 (T17)
-- 5) Đổi đơn sang returned -> phát sinh dòng 'clawback' âm trong commission_ledger (T14)

-- T18: Kiểm tra tính bất biến của commission_payouts và audit_logs
update public.commission_payouts set amount = 0 where true;
delete from public.audit_logs where true;
-- Kỳ vọng: Cả 2 đều bị chặn bởi RLS / trigger bất biến.
```

### Nhóm Chức năng P1 & P2 (T26–T43)
- **T26–T28 (Rút tiền & Ngân hàng):** Đăng nhập `/ctv` → tab *Hồ sơ & Ngân hàng* cập nhật STK → vào `/admin` → tab *Cộng tác viên* → *Hồ sơ / Bank* → bấm *Xác minh ngân hàng* → quay lại `/ctv` tab *Rút tiền* gửi yêu cầu ≥ 200.000 đ → kiểm tra không gửi được yêu cầu thứ 2 khi yêu cầu đầu đang mở → Admin duyệt & chi trả trong tab *Đối soát & Rút tiền*.
- **T29–T30 (Click tracking & Attribution):** Mở `/?ref=CTV01` → kiểm tra bảng `referral_clicks` có 1 dòng; reload trong 5 phút không tăng thêm (dedupe); mở `/thanh-toan` thấy mã `CTV01` tự điền; đặt đơn bằng đúng SĐT/user của `CTV01` → kiểm tra `orders.self_referral = true` và `commission_amount = 0`.
- **T31–T34 (Đăng ký, Đổi/Quên mật khẩu):** Đăng ký ở `/cong-tac-vien` yêu cầu mật khẩu ≥ 8 ký tự và hiển thị đúng mã `code` đọc từ DB; đổi mật khẩu ở `/ctv` tab *Hồ sơ*; bấm *Quên mật khẩu?* ở màn login `/ctv`.
- **T35–T43 (Admin CRUD, Báo cáo, Khách hàng, CSV, Audit Log):** Kiểm tra các tab *Báo cáo* (chọn khoảng ngày), *Khách hàng* (lưu ghi chú), *Sản phẩm & KM* (thêm/sửa sản phẩm, tồn kho, mã giảm giá, quy tắc HH, `app_settings`), *Nhật ký (Audit)* (lọc theo đối tượng), và bấm nút *Xuất CSV* mở bằng Excel xác nhận tiếng Việt chuẩn UTF-8 BOM.
