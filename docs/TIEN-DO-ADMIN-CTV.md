# TIẾN ĐỘ TRIỂN KHAI CẢI TIẾN ADMIN & CTV (`d:\thamoto`)

> Nguồn sự thật: `docs/KE-HOACH-CAI-TIEN-ADMIN-CTV.md` & `docs/QUYET-DINH-Q1-Q6.md`  
> Hướng dẫn chạy SQL & kiểm thử T01–T43: `docs/HUONG-DAN-MIGRATION-VA-TEST.md`

---

## Tổng quan Task List

### Giai đoạn P0 — Bảo mật & Toàn vẹn tiền/hoa hồng (Ưu tiên cao nhất)
| Mã | Hạng mục | Giải quyết | File ảnh hưởng | Trạng thái |
|---|---|---|---|---|
| P0-8 | Truy vấn rà soát dữ liệu hiện có (chỉ đọc) | V01, V05 | `supabase/migrations/20261125_000_p0_8_audit_existing_data.sql` | ✅ Xong |
| P0-2 | Siết quyền bảng `affiliates`, RPC `admin_update_affiliate`, trigger chặn leo thang quyền, hardening `develop_set_account_role` | V02, V10 | `supabase/migrations/20261125_001_p0_settings_audit_security.sql`, `app/pages/admin.vue` | ✅ Xong |
| P0-7 | Bảng `audit_logs` (append-only) + `app_settings` + `updated_at/updated_by` trên `orders` | V09 | `supabase/migrations/20261125_001_p0_settings_audit_security.sql` | ✅ Xong |
| P0-1 | RPC `create_order`, `create_lead`, `validate_coupon`, `validate_affiliate_code`; bảng sản phẩm/coupon/quy tắc HH; bỏ anon direct insert | V01, V07, V08, V12, V14 | `supabase/migrations/20261125_002_p0_catalog_coupons_create_order.sql`, `app/pages/thanh-toan.vue`, `gio-hang.vue`, `lien-he.vue` | ✅ Xong |
| P0-3 | Che PII khách hàng cho CTV ở tầng DB (`ctv_list_orders`, `ctv_list_leads`), thu hồi `SELECT` trực tiếp của CTV | V03 | `supabase/migrations/20261125_003_p0_ctv_pii_masking.sql`, `app/pages/ctv.vue` | ✅ Xong |
| P0-4 | Sổ cái `commission_ledger` (append-only + clawback) + `commissions` (`pending → holding → available → paid / reversed`) + `admin_set_order_status` + backfill | V04, V13 | `supabase/migrations/20261125_004_p0_ledger_payouts_kpis.sql`, `app/pages/admin.vue`, `ctv.vue` | ✅ Xong |
| P0-5 | Chi trả nguyên tử & idempotent (`admin_pay_commissions`), `payout_items`, bất biến `commission_payouts`, `gross/tax/net` | V05 | `supabase/migrations/20261125_004_p0_ledger_payouts_kpis.sql`, `app/pages/admin.vue` | ✅ Xong |
| P0-6 | KPI & công nợ tính ở DB (`ctv_overview`, `admin_overview`, `admin_settlement_summary`, `admin_list_orders` phân trang server) | V06, V13, V16 | `supabase/migrations/20261125_004_p0_ledger_payouts_kpis.sql`, `app/pages/admin.vue`, `ctv.vue` | ✅ Xong |

### Giai đoạn P1 — Chức năng cốt lõi còn thiếu
| Mã | Hạng mục | Giải quyết | File ảnh hưởng | Trạng thái |
|---|---|---|---|---|
| P1-1 | Yêu cầu rút tiền (`payout_requests`, 1 yêu cầu mở/CTV, Admin duyệt/từ chối/chi trả) | C2, C10, A12, V15 | `20261125_005_*.sql`, `app/pages/ctv.vue`, `app/pages/admin.vue` | ✅ Xong |
| P1-2 | Hồ sơ CTV, ngân hàng (`affiliate_bank_accounts` cần xác minh), đổi/quên mật khẩu, mật khẩu ≥ 8 ký tự, đọc mã DB sau đăng ký | C11, C12, C13, V11, V15 | `20261125_005_*.sql`, `app/pages/ctv.vue`, `cong-tac-vien.vue` | ✅ Xong |
| P1-3 | Click tracking (`referral_clicks`, `track_click` dedupe 5 phút) & tỷ lệ chuyển đổi | C7, C8, V15 | `20261125_005_*.sql`, `app/composables/useAffiliate.ts`, `app/pages/ctv.vue` | ✅ Xong |
| P1-4 | Quy tắc attribution đầy đủ (cookie + localStorage, TTL 30 ngày, last-click, manual override, self-referral = 0 HH) | V08 | `20261125_002_*.sql`, `app/composables/useAffiliate.ts`, `app/pages/thanh-toan.vue` | ✅ Xong |
| P1-5 | Chi tiết đơn hàng (modal hiển thị `order_items`, khách, `payment_status`, lịch sử audit, lý do hủy/hoàn) | A2, A3, A4, V12 | `20261125_005_*.sql`, `app/components/admin/OrderDetailModal.vue`, `admin.vue` | ✅ Xong |
| P1-6 | Quản lý CTV chi tiết (hồ sơ + ngân hàng + xác minh ngân hàng + khóa kèm lý do + xác nhận đổi %) | A6, A7, A8 | `20261125_005_*.sql`, `app/components/admin/AffiliateDetailModal.vue`, `admin.vue` | ✅ Xong |
| P1-7 | Quản trị Sản phẩm, Mã giảm giá, Quy tắc hoa hồng, Cài đặt hệ thống trong Admin | A9, A13, A14, A16, V14 | `20261125_005_*.sql`, `app/components/admin/CatalogTab.vue`, `admin.vue` | ✅ Xong |
| P1-8 | Phân quyền nhân viên (`staff` + `permissions` JSONB kiểm tra ở DB + route middleware UX) | A21, V10 | `20261125_001_*.sql`, `app/middleware/auth-admin.ts`, `auth-ctv.ts` | ✅ Xong |
| P1-9 | Tab Nhật ký hoạt động (`audit_logs`) trong Admin có lọc & phân trang | A22, V09 | `20261125_005_*.sql`, `app/components/admin/AuditLogsTab.vue`, `admin.vue` | ✅ Xong |
| P1-10 | Mẫu Edge Function thông báo Telegram (`supabase/functions/notify-order/index.ts`) + cập nhật `.env.example` (chỉ tên biến) | V20 | `supabase/functions/notify-order/index.ts`, `.env.example`, `docs/HUONG-DAN-MIGRATION-VA-TEST.md` | ✅ Xong |

### Giai đoạn P2 — UX, Báo cáo, Hiệu năng, Khách hàng
| Mã | Hạng mục | Giải quyết | File ảnh hưởng | Trạng thái |
|---|---|---|---|---|
| P2-1 | Phân trang + lọc khoảng ngày phía server cho Đơn hàng, Khách hàng, Audit | A1, C3, V16 | `20261125_006_*.sql`, `admin.vue`, `ctv.vue` | ✅ Xong |
| P2-2 | Xuất CSV chuẩn UTF-8 BOM + chống CSV formula injection | A5, C9 | `app/utils/exportCsv.ts`, `admin.vue`, `ctv.vue` | ✅ Xong |
| P2-3 | Dashboard Báo cáo Admin (lọc khoảng ngày, biểu đồ doanh thu ngày, Top CTV, Top sản phẩm, tỷ lệ hủy) | A18, A19, A20 | `20261125_006_*.sql`, `app/components/admin/ReportsTab.vue` | ✅ Xong |
| P2-4 | Loading/Error/Empty state + sửa V19 + khóa nút chống bấm đúp (`busyKey`) | V16, V19 | `app/pages/admin.vue`, `app/pages/ctv.vue` | ✅ Xong |
| P2-5 | Quản lý Khách hàng (`customers` gộp theo SĐT, lịch sử mua, ghi chú chăm sóc) | A17 | `20261125_006_*.sql`, `app/components/admin/CustomersTab.vue` | ✅ Xong |
| P2-6 | Tồn kho (`products.stock_qty` tùy chọn theo Q8 — chỉnh được trong Admin, mặc định không chặn bán) | A15 | `20261125_002_*.sql`, `app/components/admin/CatalogTab.vue` | ✅ Xong |
| P2-7 | Tối ưu index & bỏ `upper()` trong RLS | V18 | `20261125_001_*.sql`, `20261125_004_*.sql`, `20261125_005_*.sql` | ✅ Xong |
| P2-8 | Chuẩn hóa `supabase/migrations/` + đồng bộ `supabase/schema.sql` + tài liệu chạy & test T01–T43 | V20 | `supabase/schema.sql`, `docs/HUONG-DAN-MIGRATION-VA-TEST.md` | ✅ Xong |
| P2-9 | Giữ nguyên `src/` (code Vite legacy) theo ràng buộc cứng không xóa/sửa `src/` | V17 | Ghi chú trong báo cáo | ✅ Xong (giữ nguyên) |

### Bản vá sau kiểm tra (migration 007)
- [x] Đồng bộ tên quyền staff về `orders`, `payouts`, `affiliates`, `products`, `coupons`. Tên cũ (`manage_orders`, `approve_commissions`, `pay_commissions`, `manage_affiliates`) tự ánh xạ qua `canonical_permission`. Trigger whitelist cho `affiliates.permissions`.
- [x] Catalog, mã giảm giá, quy tắc hoa hồng và cài đặt hệ thống chỉ ghi qua RPC `admin_save_product`, `admin_save_coupon`, `admin_save_commission_rule`, `admin_update_setting`. RPC kiểm tra quyền, kiểm tra khoảng giá trị và ghi `audit_logs`. Đã thu hồi INSERT/UPDATE/DELETE trực tiếp của anon và authenticated. Quy tắc hoa hồng không xóa cứng, chỉ vô hiệu hóa.
- [x] `CatalogTab.vue` gọi RPC và dùng đúng tên cột schema (`min_order_amount`, `max_discount_amount`, `rate`).
- [x] Migration 008: `admin.vue` đọc `leads`/`affiliates`/`commission_payouts` qua RPC có phân trang (`admin_list_leads`, `admin_list_affiliates`, `admin_list_payouts`), đổi trạng thái lead qua `admin_update_lead_status` (có audit). Đã bỏ giới hạn 150 dòng; thêm lọc trạng thái lead và CTV phía server.
- [x] `chi-tiet.vue` lấy giá chất liệu/ưu đãi từ RPC `get_catalog_prices`; `MAT_PRICING` chỉ còn là dự phòng. Nút thêm giỏ bị khóa trong lúc tải giá.
- [ ] Chưa chạy trên Supabase thật: cần chạy migration 007, 008 và test T01–T25 trước khi lên production.
- [ ] Còn tồn tại: `MAT_PRICING` vẫn được dùng ở `shared/utils/vehicles.ts` (màu sắc, dữ liệu dự phòng). Chưa có ảnh chụp 390/768/1440px.

### Giai đoạn P3 — Kiến trúc sẵn sàng mở rộng
| Mã | Hạng mục | Trạng thái |
|---|---|---|
| P3-1..P3-8 | Đã thiết kế sẵn `app_settings` (`commission_hold_days`, `tax_withholding_rate`, `tax_threshold_per_payment`), hàm `release_matured_commissions()` kèm hướng dẫn `pg_cron`, cấu trúc `commission_rules` đa tầng, `payout_requests` & Edge Function mẫu | ✅ Sẵn sàng mở rộng |
