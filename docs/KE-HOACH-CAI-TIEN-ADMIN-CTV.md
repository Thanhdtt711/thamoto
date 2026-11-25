# KẾ HOẠCH CẢI TIẾN HỆ THỐNG ADMIN & CỘNG TÁC VIÊN (CTV)

> Dự án: `d:\thamoto` — Trung Thành Auto (Nuxt 4 + Supabase)
> Trạng thái: **BẢN KẾ HOẠCH — CHƯA CÓ DÒNG CODE NÀO ĐƯỢC SỬA.** Chờ anh/chị duyệt.
> Cách trích dẫn: `file:dòng`. Mọi nhận xét dưới đây dựa trên code đã đọc, không suy đoán.

---

## 0. Phạm vi đã đọc & giới hạn

**Đã đọc kỹ:** `supabase/schema.sql` (toàn bộ), `app/pages/admin.vue`, `app/pages/ctv.vue`, `app/pages/cong-tac-vien.vue`, `app/pages/thanh-toan.vue`, `app/pages/gio-hang.vue`, `app/pages/lien-he.vue` (phần submit), `app/composables/useAffiliate.ts`, `useCart.ts`, `useSupabase.ts`, `shared/utils/vehicles.ts` (phần giá), `nuxt.config.ts`, `package.json`, `.env.example`, `docs/order-integration.md`.

**Chỉ tìm kiếm (grep), chưa đọc từng dòng:** các file legacy trong `src/` (`admin.html`, `ctv.html`, `thanh-toan.html`, `lien-he.html`, `assets/js/*`).

**Giới hạn cần biết:**
- Không có quyền vào project Supabase thật. Phần RLS/trigger/function dựa trên `supabase/schema.sql`. **Cần xác nhận DB đang chạy khớp file này** (xem câu hỏi Q10).
- Thư mục `server/` rỗng: dự án **không có backend riêng**. Trình duyệt gọi thẳng Supabase, nên toàn bộ bảo mật dồn vào RLS.
- Không tìm thấy khóa bí mật nào bị lộ trong repo (đã tìm `service_role`, `sb_secret`, chuỗi JWT).
- Không có `v-html` / `innerHTML` trong `app/` nên rủi ro XSS thấp. Vue tự escape nội dung.

---

## 1. Tóm tắt hiện trạng

### 1.1 Điểm mạnh
- Có đủ khung: đăng ký CTV → duyệt → link/mã giới thiệu → đơn gắn mã → hoa hồng → đối soát → ghi nhận chi trả.
- Hoa hồng được tính **ở DB bằng trigger** (`schema.sql:77-115`), lấy tỷ lệ của CTV tại thời điểm đặt đơn. Client không tự gửi được tỷ lệ/số tiền hoa hồng.
- RLS đã bật cho cả 4 bảng; CTV chỉ đọc được đơn/chi trả có mã của mình (`schema.sql:273-283, 319-329`). CTV bị khóa/chờ duyệt không đọc được dữ liệu vì `current_affiliate_code()` yêu cầu `status='active'` (`schema.sql:223-234`).
- Trigger tạo hồ sơ CTV khi đăng ký (`schema.sql:118-157`) cố định `role='ctv'`, `status='pending'`, nên người dùng không tự phong quyền qua metadata.
- Tách vai trò `ctv / admin / develop`; chỉ `develop` được tạo tài khoản và đổi vai trò qua RPC (`schema.sql:191-221`).
- UI có responsive (bảng desktop / thẻ mobile), nút ≥ 44px, trạng thái tài khoản CTV (chờ duyệt/khóa/hủy), trang tạo link theo hãng/dòng xe.

### 1.2 Điểm yếu chính
1. **Đơn hàng do trình duyệt tự khai toàn bộ** (giá, trạng thái, trạng thái hoa hồng) và DB tin hết → có thể làm giả đơn/hoa hồng (V01).
2. **Admin tự nâng quyền lên Develop được** bằng update trực tiếp bảng `affiliates` (V02).
3. **CTV đọc được SĐT/địa chỉ đầy đủ của khách** qua API; việc "che SĐT" chỉ ở giao diện (V03).
4. **Hủy/hoàn đơn không thu hồi hoa hồng**; không có sổ cái hoa hồng (V04).
5. **Chi trả hoa hồng không nguyên tử, không chống bấm đúp**, tính trên danh sách bị cắt 300 đơn (V05, V06).
6. Thiếu hẳn: yêu cầu rút tiền, hồ sơ/ngân hàng/đổi mật khẩu CTV, click & tỷ lệ chuyển đổi, chi tiết đơn, xuất báo cáo, audit log, quản lý sản phẩm/kho/mã giảm giá/khách hàng.

### 1.3 Mức đạt chuẩn ước tính

Cách tính: mỗi hạng mục ở bảng mục 2 được ✅ = 1 điểm, ⚠️ = 0,5 điểm, ❌ = 0 điểm, chia cho tổng số hạng mục.

| Phần | Điểm | % chức năng |
|---|---|---|
| CTV (14 hạng mục) | 5,5 / 14 | **≈ 39%** |
| Admin (22 hạng mục) | 6,5 / 22 | **≈ 30%** |
| **Tổng chức năng** | 12 / 36 | **≈ 33%** |
| An toàn & toàn vẹn tiền (đánh giá định tính) | — | **≈ 20%** (có 5 lỗi 🔴) |

**Kết luận: CHƯA đạt chuẩn một web bán hàng có hệ thống CTV.** Đây là bản demo chạy được luồng cơ bản. **Chưa nên vận hành thật với tiền hoa hồng thật** khi chưa xong nhóm P0.

---

## 2. Khảo sát & bảng đối chiếu chức năng

### 2.1 Kiến trúc & bản đồ file

| Lớp | Công nghệ / file | Ghi chú |
|---|---|---|
| Framework | Nuxt 4, Vue 3, Tailwind (`package.json`) | Build = `nuxt build`. Không có backend riêng (`server/` rỗng). |
| DB + Auth | Supabase (Postgres, Auth, RLS) — `supabase/schema.sql` | Dán tay vào SQL Editor, **chưa có migration có phiên bản**. |
| Client DB | `app/composables/useSupabase.ts` | Dùng khóa `anon` ở trình duyệt. |
| Giá & sản phẩm | `shared/utils/vehicles.ts:190-213` (`MAT_PRICING`, `calculateMatPrice`) | **Hard-code** trong code, chưa có bảng sản phẩm. |
| Mã giảm giá | `app/pages/gio-hang.vue:16-19` | **Hard-code ở client** (`THAMOTO2026`, `VIP10`). |
| Gắn CTV | `app/composables/useAffiliate.ts`, `app/layouts/default.vue:8-13` | `?ref=`/`?ctv=` → `localStorage` 30 ngày. |
| Đặt hàng | `app/pages/thanh-toan.vue:64-107` | Insert thẳng vào `orders`. |
| Tư vấn (lead) | `app/pages/lien-he.vue:44-50` | Insert thẳng vào `leads` kèm mã CTV. |
| Đăng ký CTV | `app/pages/cong-tac-vien.vue:27-76` | `auth.signUp` + metadata. |
| Cổng CTV | `app/pages/ctv.vue` | 2 tab: Đơn hàng, Chi trả + tạo link. |
| Cổng Admin | `app/pages/admin.vue` | 4 tab: Đơn hàng, CTV, Đối soát, Tư vấn. |
| Phân quyền | `schema.sql:160-188, 223-234, 236-342` | `is_admin()`, `is_develop()`, `current_affiliate_code()`, RLS. |
| Code legacy | `src/*.html`, `src/assets/js/*` | Bản cũ (Vite) trùng logic. `nuxt.config.ts:38-50` redirect `.html` sang route Nuxt. |

### 2.2 Checklist — Trang CTV

| # | Chức năng chuẩn | TT | File / dòng | Ghi chú |
|---|---|---|---|---|
| C1 | Tổng quan: tổng đơn, doanh thu, hoa hồng chờ duyệt/đã duyệt/đã trả | ⚠️ | `ctv.vue:73-80, 255-272` | Có đủ 3 trạng thái nhưng tính ở client trên tối đa 200 đơn (`ctv.vue:95`). "Tổng đơn" đếm cả đơn hủy. |
| C2 | Số dư có thể rút | ⚠️ | `ctv.vue:266` | Chỉ cộng `pending + approved` gộp chung. Không có khái niệm số dư khả dụng, không trừ khoản đã yêu cầu. |
| C3 | Danh sách đơn qua link/mã: mã đơn, ngày, trạng thái, giá trị, hoa hồng | ⚠️ | `ctv.vue:317-400` | Đủ cột nhưng không phân trang (limit 200), không tìm kiếm, chỉ lọc trạng thái. |
| C4 | Che thông tin khách (tên rút gọn, ẩn SĐT/email/địa chỉ) | ⚠️ | `ctv.vue:65, 351-352` | Chỉ che SĐT ở UI. Tên hiện đầy đủ. API vẫn trả `select('*')` gồm SĐT/địa chỉ/ghi chú (**V03**). |
| C5 | Link giới thiệu | ✅ | `ctv.vue:26-41, 275-295`; `useAffiliate.ts:60-65` | Tạo link theo trang chủ/hãng/dòng xe + nút sao chép. |
| C6 | Mã giới thiệu | ✅ | `ctv.vue:233`; `schema.sql:137-143` | Mã hiển thị trên header portal. |
| C7 | Thống kê lượt click | ❌ | — | Không có bảng/click tracking nào. |
| C8 | Tỷ lệ chuyển đổi | ❌ | — | Phụ thuộc C7. |
| C9 | Lịch sử hoa hồng / chi trả | ⚠️ | `ctv.vue:402-468`; `schema.sql:59-67` | Có danh sách chi trả (ngày, số đơn, số tiền, ghi chú). Không biết khoản chi trả gồm những đơn nào (payout không liên kết đơn). |
| C10 | Yêu cầu rút tiền (trạng thái, ngày, số tiền) | ❌ | `ctv.vue:410` | Chỉ có nút nhắn Zalo. Không có bảng/luồng yêu cầu. |
| C11 | Hồ sơ cá nhân | ❌ | — | Không xem/sửa hồ sơ; policy `affiliates` không cho CTV tự update (`schema.sql:243-264`). |
| C12 | Thông tin ngân hàng | ❌ | `schema.sql:9-23` | Bảng `affiliates` không có cột ngân hàng. |
| C13 | Đổi mật khẩu / quên mật khẩu | ❌ | — | Không có `updateUser`/`resetPasswordForEmail` trong `app/`. |
| C14 | Trạng thái tài khoản (chờ duyệt/hoạt động/khóa) | ✅ | `ctv.vue:82-91, 212-224` | Có màn hình theo trạng thái. Chưa hiện lý do từ chối/khóa. |

### 2.3 Checklist — Trang Admin

| # | Chức năng chuẩn | TT | File / dòng | Ghi chú |
|---|---|---|---|---|
| A1 | Xem/lọc/tìm tất cả đơn | ⚠️ | `admin.vue:98-110, 154, 476-566` | Lọc nguồn/trạng thái/từ khóa ở client trên **300 đơn mới nhất**. Không phân trang, không lọc theo ngày. |
| A2 | Đổi trạng thái đơn | ⚠️ | `admin.vue:165-173, 528, 559` | Dropdown đổi tùy ý, **không có luồng hợp lệ**, không lý do, không lưu lịch sử. |
| A3 | Xem chi tiết đơn | ❌ | — | Chỉ có `items_summary`; `items` (jsonb) không được hiển thị. |
| A4 | Hoàn/hủy đơn (xử lý hoa hồng kèm theo) | ⚠️ | `admin.vue:165-173, 132` | Có trạng thái "Đã hủy" nhưng **không hoàn/thu hồi hoa hồng** (**V04**). Không có trạng thái hoàn trả. |
| A5 | Xuất báo cáo | ❌ | — | Không có CSV/Excel. |
| A6 | Duyệt / từ chối / khóa CTV | ✅ | `admin.vue:175-183, 628-630` | Đổi `status` qua dropdown. Thiếu lý do và thông báo cho CTV. |
| A7 | Xem hồ sơ CTV | ⚠️ | `admin.vue:594-632` | Có tên/SĐT/email/nghề/khu vực/hiệu suất. Không có trang chi tiết, không có ngân hàng. |
| A8 | Cấu hình tỷ lệ hoa hồng theo CTV | ✅ | `admin.vue:185-194`; `schema.sql:20` | Giới hạn 0–50%. Đổi tức thì (không xác nhận), không lưu lịch sử. |
| A9 | Cấu hình hoa hồng theo sản phẩm | ❌ | — | Chỉ có tỷ lệ theo CTV; trigger tính trên cả `total_amount` (`schema.sql:96`). |
| A10 | Duyệt hoa hồng | ⚠️ | `admin.vue:210-219` | Duyệt gộp theo CTV các đơn `completed`+`pending`. Không kiểm tra lại trạng thái ở DB, không chống bấm đúp. |
| A11 | Hoàn hoa hồng khi đơn hủy/hoàn | ❌ | — | Không có (**V04**). |
| A12 | Duyệt yêu cầu rút / đánh dấu đã thanh toán | ⚠️ | `admin.vue:221-242` | Chỉ có "Xác nhận thanh toán" chủ động, không có hàng đợi yêu cầu rút. Ghi nhận không nguyên tử (**V05**). |
| A13 | Quản lý sản phẩm | ❌ | `shared/utils/vehicles.ts:190-200` | Sản phẩm/giá hard-code trong code. |
| A14 | Quản lý danh mục | ❌ | `shared/utils/vehicles.ts:38+` | Hãng/dòng xe hard-code. |
| A15 | Tồn kho | ❌ | — | Không có. |
| A16 | Khuyến mãi / mã giảm giá | ❌ | `gio-hang.vue:16-19` | Mã hard-code ở client, server không kiểm. |
| A17 | Khách hàng | ❌ | — | Không có bảng khách; thông tin khách nằm lẫn trong từng đơn. |
| A18 | Dashboard doanh thu & đơn | ⚠️ | `admin.vue:85-96, 433-454` | 4 thẻ KPI, tính trên 300 đơn. Không lọc thời gian, không biểu đồ. |
| A19 | Top CTV | ⚠️ | `admin.vue:116-123, 621` | Có đơn/doanh số từng CTV nhưng không xếp hạng. |
| A20 | Top sản phẩm | ❌ | — | Không có. |
| A21 | Phân quyền admin / nhân viên | ⚠️ | `schema.sql:19, 160-188` | Chỉ 3 vai trò cứng; chưa có quyền chi tiết/nhân viên. Guard trang chỉ ở client (`admin.vue:292-310`). |
| A22 | Nhật ký hoạt động (audit log) | ❌ | — | Không có bảng/trigger nào. |
| (+) | Quản lý yêu cầu tư vấn (lead) | ✅ | `admin.vue:244-249, 746-767` | Ngoài chuẩn nhưng đã có. |

---

## 3. Danh sách vấn đề phát hiện

### 🔴 Nghiêm trọng

| ID | Vấn đề | File liên quan | Hậu quả |
|---|---|---|---|
| **V01** | **Đơn hàng tin hoàn toàn dữ liệu client.** Policy `Anyone can place orders ... with check (true)` cho phép khách ẩn danh insert mọi cột. Trigger chỉ ghi đè `affiliate_code/commission_rate/commission_amount` (`schema.sql:86-105`), **không ép** `status='new'`, `commission_status='pending'`. `total_amount` do client tính (`thanh-toan.vue:83`); giá và mã giảm giá cũng ở client (`gio-hang.vue:16-37`, `vehicles.ts:190-213`). | `schema.sql:26-44, 77-115, 267-271`; `thanh-toan.vue:75-87`; `gio-hang.vue:16-37` | Bất kỳ ai gọi REST API đều có thể: tạo đơn `status='completed'` / `commission_status='paid'`; đặt `total_amount` tùy ý (hoa hồng tính theo số này); gán mã CTV bất kỳ; tự đặt đơn bằng mã của mình (không có chống tự giới thiệu); spam hàng loạt vì không có rate-limit/captcha. |
| **V02** | **Admin leo thang lên Develop.** Policy `Admins can update affiliates` cho `is_admin()` (gồm cả `admin`) update **mọi cột** (`schema.sql:259-264`). Chặn đổi vai trò chỉ nằm ở UI (`admin.vue:598`) và RPC `develop_set_account_role` (`schema.sql:191-221`). Gọi `update affiliates set role='develop'` trực tiếp là đi vòng qua RPC. | `schema.sql:259-264`; `admin.vue:175-194` | Một admin bị lộ/độc hại có toàn quyền: tạo tài khoản, đổi vai trò, sửa `user_id/email/code` của CTV khác. Vai trò develop mất ý nghĩa. |
| **V03** | **Lộ thông tin khách cho CTV.** CTV gọi `from('orders').select('*')` (`ctv.vue:95`) và policy cho đọc **toàn bộ cột** đơn của mình (`schema.sql:273-283`). Che SĐT chỉ ở UI (`ctv.vue:65, 352`), tên khách hiện đầy đủ (`ctv.vue:351`). Địa chỉ, ghi chú, `items` vẫn nằm trong response. Với `leads`, policy cũng cho CTV đọc đủ cột (`schema.sql:299-309`). | `ctv.vue:65, 95, 351-352`; `schema.sql:273-283, 299-309` | CTV đọc được SĐT/địa chỉ/ghi chú của khách qua API → rủi ro CTV tự chốt đơn riêng (vòng qua shop), lộ dữ liệu cá nhân (Nghị định 13/2023). |
| **V04** | **Hủy/hoàn đơn không thu hồi hoa hồng; không có sổ cái.** `updateOrderStatus` chỉ đổi `status` (`admin.vue:165-173`). Sau khi hoa hồng đã `approved/paid`, đổi đơn sang `cancelled` thì: đối soát **bỏ qua** đơn đó (`admin.vue:132`), khoản đã trả biến mất khỏi "Đã thanh toán" nhưng tiền thật đã chi. Không có số âm/bù trừ. Trạng thái đơn đổi tự do (kể cả `completed → new`). | `admin.vue:125-149, 165-173`; `schema.sql:41-42` | Chi hoa hồng cho đơn hủy/hoàn mà không phát hiện; số liệu công nợ sai lệch. |
| **V05** | **Chi trả hoa hồng không nguyên tử, không chống trùng.** `payCommission` (`admin.vue:221-242`) chạy 2 lệnh riêng: update `orders` → insert `commission_payouts`; lỗi giữa chừng thì lệch. Không khóa nút khi đang xử lý → bấm đúp tạo 2 bản ghi payout. `update ... in('id', ids)` không kiểm tra lại trạng thái hiện tại ở DB. Số tiền lấy từ state client (có thể cũ). `created_by` do client gửi (`admin.vue:235`). `commission_payouts` không liên kết với đơn (`schema.sql:59-67`). Policy cho phép **update** payout (`schema.sql:337-342`) nên sửa được số tiền đã chi. **Hai nguồn sự thật**: `orders.commission_status='paid'` và `commission_payouts.amount`. | `admin.vue:210-242`; `schema.sql:59-67, 331-342` | Chi trùng/sai tiền, lệch sổ sách, không truy vết được khoản chi cho những đơn nào, có thể sửa lịch sử chi trả. |
| **V06** | **Số liệu tiền tính trên dữ liệu bị cắt.** Admin tải tối đa 300 đơn/150 lead/150 payout (`admin.vue:154-157`); CTV tối đa 200 đơn/100 payout (`ctv.vue:95-96`). Toàn bộ KPI, đối soát, "hoa hồng chờ trả" tính ở client trên danh sách này. Lỗi tải bị nuốt, trả mảng rỗng (`admin.vue:153-162`, `ctv.vue:94-99`). | `admin.vue:85-96, 125-163`; `ctv.vue:73-80, 94-99` | Vượt 300/200 đơn là KPI và công nợ **sai âm thầm**; admin có thể duyệt/chi thiếu hoặc bỏ sót. Lỗi mạng hiện "Chưa có đơn" gây hiểu nhầm. |

### 🟡 Trung bình

| ID | Vấn đề | File liên quan | Hậu quả |
|---|---|---|---|
| V07 | **Mã đơn do client sinh ngẫu nhiên 5 chữ số** (`TT-10000..99999`). Trùng mã → vi phạm `unique` → đơn thất bại; dễ đoán. | `thanh-toan.vue:68`; `schema.sql:28` | Mất đơn khi trùng; mã đơn đoán được. |
| V08 | **Attribution yếu.** Chỉ `localStorage` (không cookie/server), last-click ghi đè (`useAffiliate.ts:15-28`), khách gõ tay mã CTV (`thanh-toan.vue:202-204, 67`), không lưu thời điểm/nguồn click. Mã không tồn tại/không hoạt động vẫn được lưu vào `affiliate_code` với hoa hồng 0 (`schema.sql:94-99`) và vẫn bị đếm là "đơn qua CTV" (`admin.vue:86-87`). Không chặn tự giới thiệu. | `useAffiliate.ts`; `thanh-toan.vue`; `schema.sql:86-105` | Tranh chấp hoa hồng; số "đơn CTV" sai; lách bằng cách tự nhập mã. |
| V09 | **Không có audit log / lịch sử thay đổi.** `orders` không có `updated_at/updated_by`; đổi trạng thái đơn, % hoa hồng, trạng thái CTV, vai trò đều không để lại dấu vết. | `schema.sql:26-44`; `admin.vue:165-208` | Không điều tra được khi có sai sót/gian lận nội bộ. |
| V10 | **Guard Admin chỉ ở client, phân quyền thô.** Không có route middleware; kiểm tra quyền trong `onMounted` (`admin.vue:292-310`). Chỉ 3 vai trò, không có nhân viên/quyền theo chức năng. Develop có thể tự hạ quyền (UI chỉ chặn bằng `a.id !== currentAdmin.id`). | `admin.vue:292-310`; `schema.sql:19, 191-221` | Phụ thuộc 100% vào RLS (đang có lỗ hổng V02). Không giao được việc cho nhân viên mà không cấp quyền admin đầy đủ. |
| V11 | **Đăng ký & mật khẩu yếu.** Mật khẩu tối thiểu 6 ký tự (`cong-tac-vien.vue:45`, `admin.vue:817`); không captcha/rate-limit cho đăng ký, đặt đơn, lead. Mã CTV tự chọn có thể trùng từ nhạy cảm (vd `ADMIN`). Màn hình thành công hiện mã sinh ở client (`cong-tac-vien.vue:22-25, 70`), có thể **khác** mã DB nếu trigger đổi mã do trùng (`schema.sql:137-143`). | `cong-tac-vien.vue`; `schema.sql:131-143` | Brute-force/spam; CTV nhận sai mã → link không ghi nhận. |
| V12 | **Không có `payment_status`.** Nút "ĐÃ CHUYỂN KHOẢN" tạo đơn mà không xác minh tiền (`thanh-toan.vue:292`). Cột `payment_method` chỉ là nhãn. | `thanh-toan.vue:64-107, 292`; `schema.sql:33` | Hoa hồng có thể phát sinh trên đơn chưa thu tiền. |
| V13 | **Số liệu CTV và Admin không khớp.** CTV tính "chờ duyệt" trên mọi đơn không hủy (`ctv.vue:76`); Admin chỉ tính đơn `completed` (`admin.vue:140`). Nhãn "chờ duyệt / rút" gộp 2 trạng thái (`ctv.vue:266`). | `ctv.vue:73-80`; `admin.vue:125-149` | CTV thấy một số, admin trả theo số khác → khiếu nại. |
| V14 | **Thiếu quản trị dữ liệu gốc**: sản phẩm/giá/danh mục/mã giảm giá hard-code (`vehicles.ts`, `gio-hang.vue`); không có khách hàng, tồn kho. Đổi giá = sửa code + deploy; server không có cơ sở để kiểm giá (gốc rễ của V01). | `shared/utils/vehicles.ts`; `gio-hang.vue:16-19` | Không vận hành độc lập được; không thể xác thực giá phía server. |
| V15 | **Không có yêu cầu rút tiền, hồ sơ, ngân hàng, click tracking** (chi tiết ở checklist C7–C13). | `ctv.vue:410` | Quy trình rút tiền thủ công qua Zalo, khó đối soát. |
| V16 | **UX dữ liệu:** không phân trang/lọc server, không loading/error state khi tải, không xuất báo cáo, không chi tiết đơn. | `admin.vue:151-163, 476-566`; `ctv.vue:94-99` | Khó dùng khi dữ liệu lớn; lỗi tải khó nhận biết. |

### 🟢 Nhẹ

| ID | Vấn đề | File liên quan | Hậu quả |
|---|---|---|---|
| V17 | **Code trùng lặp 2 bản**: `src/*.html` + `src/assets/js/*` vẫn chứa logic admin/CTV/đặt hàng song song với `app/`. `nuxt.config.ts:38-50` redirect `.html` sang route Nuxt nên bản `src/` là code chết nhưng dễ bị sửa nhầm. `AGENTS.md` mô tả Vite/prerender, **không còn đúng** với Nuxt hiện tại. | `src/admin.html`, `src/ctv.html`, `src/thanh-toan.html`, `src/lien-he.html`, `AGENTS.md` | Dễ nhầm, bảo trì tốn kém. |
| V18 | **Chỉ mục & truy vấn:** index `idx_orders_affiliate_code` (`schema.sql:70`) không dùng được vì policy lọc theo `upper(affiliate_code)` (`schema.sql:281`). Thiếu index cho `orders.status`, `commission_status`, `leads.affiliate_code`, `commission_payouts.paid_at`. `affiliateStats()` lọc lại toàn bộ đơn mỗi lần render mỗi dòng (`admin.vue:116-123, 621, 652`). | `schema.sql:70-74, 281`; `admin.vue:116-123` | Chậm dần khi dữ liệu lớn. |
| V19 | **Lỗi nhỏ:** toast tạo tài khoản dùng `newAcc.role` sau khi form đã reset nên luôn hiện "ADMIN" (`admin.vue:281-283`). `updateLeadStatus` không tải lại (`admin.vue:244-249`). | `admin.vue` | Hiển thị sai thông báo. |
| V20 | **Vận hành:** chưa có thông báo (email/Telegram) khi có đơn mới, CTV mới, yêu cầu rút (`docs/order-integration.md` ghi rõ "Chưa triển khai"). Không có migration có phiên bản, không có tài liệu backup/restore. Lead gắn mã CTV nhưng CTV không thấy lead (`ctv.vue` chỉ 2 tab). | `docs/order-integration.md`; `supabase/schema.sql` | Admin dễ bỏ sót đơn/CTV mới; khó khôi phục sự cố. |

---

## 4. Kế hoạch cải tiến theo giai đoạn

Ký hiệu công sức: **S** ≤ 1 ngày · **M** 2–4 ngày · **L** 5+ ngày (ước lượng cho 1 dev).
Hướng kỹ thuật đề xuất: **giữ Supabase**, chuyển mọi thao tác nhạy cảm sang **RPC (function Postgres `security definer`) hoặc Edge Function**, thu hẹp RLS; chưa cần dựng backend Node riêng (xem Q6).

### P0 — Làm ngay: lỗi bảo mật & sai nghiệp vụ tiền/hoa hồng

| Mã | Việc cần làm | Xử lý | File / module ảnh hưởng | Thay đổi DB | Công sức | Phụ thuộc |
|---|---|---|---|---|---|---|
| P0-1 | **Đặt đơn qua RPC `create_order`** thay vì insert trực tiếp: server tính lại giá từ bảng giá, xác thực mã giảm giá, ép `status='new'`, `commission_status='pending'`, sinh mã đơn không đoán được, kiểm tra mã CTV hợp lệ/hoạt động, chặn tự giới thiệu, giới hạn tần suất/captcha. Gỡ policy insert ẩn danh trên `orders`. | V01, V07, V08 | `thanh-toan.vue`, `gio-hang.vue`, `lien-he.vue` (cho lead), `schema.sql` | Thêm bảng giá tối thiểu (`products`/`price_rules` seed từ `vehicles.ts`), `coupons`; thêm cột `payment_status`, `subtotal`, `discount_amount`; sửa/bỏ policy insert | L | Bảng giá tối thiểu (làm trong P0-1) |
| P0-2 | **Siết quyền bảng `affiliates`**: bỏ update trực tiếp cho admin; thay bằng RPC `admin_update_affiliate` chỉ cho sửa `status`, `commission_rate`, ghi chú; `role/user_id/code/email` chỉ đổi qua RPC của develop; thêm trigger chặn đổi các cột này bằng đường khác. | V02, V10 | `schema.sql`, `admin.vue:175-208` | Trigger BEFORE UPDATE; sửa policy | S–M | Không |
| P0-3 | **Che PII cho CTV ở tầng DB**: thu hồi quyền `select` trực tiếp của CTV trên `orders`/`leads`; cung cấp RPC/view `ctv_orders` chỉ trả: mã đơn, ngày, trạng thái, giá trị, hoa hồng, tên rút gọn (vd "Nguyễn V.A"), tóm tắt sản phẩm **không** có địa chỉ/SĐT/email/ghi chú. | V03 | `schema.sql`, `ctv.vue:94-99, 345-398` | RPC/view mới; sửa policy `orders`/`leads` | M | Không |
| P0-4 | **Sổ cái hoa hồng + hoàn hoa hồng + luồng trạng thái đơn**: bảng `commissions` (1 dòng/đơn, trạng thái `pending/approved/paid/reversed`); RPC `admin_set_order_status` kiểm tra chuyển trạng thái hợp lệ; khi đơn `cancelled/returned`: hoa hồng chưa trả → `reversed`, đã trả → tạo khoản **âm (clawback)** trừ vào kỳ sau. Backfill từ dữ liệu hiện có. | V04, V13 | `admin.vue:125-242`, `ctv.vue:73-80`, `schema.sql` | Bảng `commissions`; thêm trạng thái đơn `returned`; trigger/RPC | L | P0-1 |
| P0-5 | **Chi trả nguyên tử & chống trùng**: RPC `admin_pay_commissions(ctv, commission_ids, note, idempotency_key)` làm trong 1 transaction, khóa dòng (`FOR UPDATE`), kiểm tra lại trạng thái, ghi `payout_items` liên kết hoa hồng↔payout, `created_by = auth.uid()` do DB gán. Payout **bất biến** (bỏ policy update). Nút UI khóa khi đang xử lý. Một nguồn sự thật = `commissions`. | V05 | `admin.vue:210-242`, `schema.sql:59-67, 331-342` | Bảng `payouts` mở rộng + `payout_items`; unique `idempotency_key`; bỏ policy update | M | P0-4 |
| P0-6 | **Công nợ/số dư tính ở DB, không cắt dữ liệu**: RPC tổng hợp `ctv_overview`, `admin_settlement_summary` (SUM theo trạng thái); danh sách có phân trang server; hiện lỗi tải rõ ràng thay vì "rỗng". | V06, V13 | `admin.vue:85-163`, `ctv.vue:73-100` | RPC tổng hợp; index | M | P0-4 |
| P0-7 | **Audit log tối thiểu ở DB**: bảng `audit_logs` + trigger ghi khi đổi `orders.status`, `affiliates(role/status/commission_rate)`, `commissions`, `payouts` (ai, lúc nào, giá trị cũ/mới). Thêm `updated_at/updated_by` cho `orders`. | V09 | `schema.sql` | Bảng `audit_logs`; cột mới trên `orders` | M | Không (làm song song P0-2) |
| P0-8 | **Rà soát dữ liệu đang có**: tìm đơn bất thường (status/commission_status lạ, tổng tiền = 0 hoặc quá lớn, mã CTV không tồn tại, đơn CTV tự đặt); đối chiếu `orders` với `commission_payouts`. | V01, V05 | Truy vấn SQL chỉ đọc, báo cáo kết quả | Không | S | Không |

**Thứ tự đề xuất:** P0-8 → (P0-2 ‖ P0-7) → P0-1 → P0-3 → P0-4 → P0-5 → P0-6.
P0-2/P0-3/P0-7 độc lập nên làm trước để chặn rủi ro nhanh nhất.

### P1 — Chức năng còn thiếu quan trọng

| Mã | Việc cần làm | File / module | Thay đổi DB | Công sức | Phụ thuộc |
|---|---|---|---|---|---|
| P1-1 | **Yêu cầu rút tiền**: CTV xem số dư khả dụng, gửi yêu cầu (hạn mức tối thiểu), xem trạng thái; Admin có hàng đợi duyệt/từ chối/đánh dấu đã chuyển, gắn vào `payouts`. | `ctv.vue`, `admin.vue` (tab mới), RPC mới | `payout_requests` | L | P0-5, P1-2 |
| P1-2 | **Hồ sơ CTV**: xem/sửa hồ sơ (whitelist cột), **thông tin ngân hàng** (admin xác minh), đổi mật khẩu, quên mật khẩu; tăng chuẩn mật khẩu (≥ 8). | `ctv.vue` (tab mới), `cong-tac-vien.vue` | Cột/bảng `affiliate_bank_accounts`; cột `approved_at/approved_by/reject_reason` | M | P0-2 |
| P1-3 | **Click tracking & tỷ lệ chuyển đổi**: ghi click khi vào bằng `?ref=` (RPC có chống spam/dedupe), gắn click vào đơn khi đặt; CTV xem click, đơn, tỷ lệ. | `useAffiliate.ts`, `default.vue`, `ctv.vue` | `referral_clicks`; cột `orders.ref_click_id`, `ref_source` | M–L | P0-1 |
| P1-4 | **Quy tắc attribution rõ ràng**: TTL cấu hình, first/last-click (theo Q4), lưu cả cookie + localStorage, mã nhập tay phải hợp lệ, chặn tự giới thiệu (so SĐT/email CTV), mã không hợp lệ **không** ghi nhận. | `useAffiliate.ts`, `thanh-toan.vue`, RPC `create_order` | Cột `orders.ref_source`, `attributed_at` | M | P0-1, P1-3 |
| P1-5 | **Chi tiết đơn & hoàn/hủy có lý do (Admin)**: màn chi tiết (items, khách, thanh toán, lịch sử trạng thái, ghi chú nội bộ); thêm `payment_status`, xác nhận thu tiền; trạng thái `returned/refunded`. | `admin.vue` (modal/trang chi tiết) | `order_status_history` (hoặc dùng audit); `orders.payment_status` | M | P0-4, P0-7 |
| P1-6 | **Quản lý CTV chi tiết (Admin)**: trang hồ sơ CTV (thống kê, đơn, hoa hồng, ngân hàng), duyệt/từ chối/khóa **kèm lý do**, xác nhận khi đổi % hoa hồng, lưu lịch sử % hoa hồng. | `admin.vue` | `affiliate_rate_history` hoặc audit | M | P0-2, P0-7 |
| P1-7 | **Quản lý sản phẩm, danh mục, mã giảm giá** trong DB thay hard-code; **hoa hồng theo sản phẩm** (`commission_rules`: ưu tiên rule CTV+sản phẩm → sản phẩm → CTV → mặc định). | `admin.vue` (tab mới), `chi-tiet.vue`, `gio-hang.vue`, `vehicles.ts` | `products`, `product_categories`, `coupons`, `commission_rules`, `order_items` | L | P0-1 |
| P1-8 | **Phân quyền nhân viên**: thêm vai trò `staff` + ma trận quyền (xem đơn, xử lý đơn, duyệt CTV, duyệt hoa hồng, chi trả...); route middleware chỉ để UX, quyền thật ở DB. | `admin.vue`, `schema.sql` | Cột `affiliates.permissions` hoặc bảng `roles/permissions` | M | P0-2 |
| P1-9 | **Màn hình Audit log (Admin)** có lọc theo người/đối tượng/thời gian. | `admin.vue` (tab mới) | Dùng `audit_logs` từ P0-7 | S | P0-7 |
| P1-10 | **Thông báo**: email/Telegram khi đơn mới, CTV mới, yêu cầu rút; email cho CTV khi được duyệt/từ chối/đã chi trả. | Edge Function / webhook | Bảng `notification_queue` (tùy chọn) | M | P1-1, P1-6 |

### P2 — UX, báo cáo, hiệu năng

| Mã | Việc cần làm | File / module | Thay đổi DB | Công sức | Phụ thuộc |
|---|---|---|---|---|---|
| P2-1 | Phân trang + lọc + tìm kiếm **phía server** cho đơn/CTV/lead/hoa hồng; lọc theo khoảng ngày. | `admin.vue`, `ctv.vue`, RPC | Index (xem mục 5.5) | M | P0-6 |
| P2-2 | **Xuất CSV/Excel**: đơn, hoa hồng, đối soát, chi trả (Admin); xuất lịch sử cho CTV. | `admin.vue`, `ctv.vue` | Không | M | P2-1 |
| P2-3 | **Dashboard Admin**: lọc thời gian, biểu đồ doanh thu/đơn, top CTV, top sản phẩm, tỷ lệ hủy. | `admin.vue` | RPC/view báo cáo | M | P0-6, P1-7 |
| P2-4 | Trạng thái loading/lỗi/rỗng thống nhất; toast; khóa nút khi xử lý; sửa lỗi nhỏ V19. | `admin.vue`, `ctv.vue` | Không | S | Không |
| P2-5 | **Khách hàng**: bảng khách (gộp theo SĐT), lịch sử mua, ghi chú. | `admin.vue` | `customers`, `orders.customer_id` | M | P0-1 |
| P2-6 | **Tồn kho** (nếu cần bán theo tồn): số lượng theo SKU, trừ khi tạo đơn, hoàn khi hủy. | RPC `create_order`, `admin.vue` | `inventory` | M | P1-7 (Q8) |
| P2-7 | Tối ưu index & truy vấn (bỏ `upper()` trong policy; bọc `(select ...)`), bỏ `affiliateStats()` lặp. | `schema.sql`, `admin.vue` | Index mới | S | P0-3 |
| P2-8 | **Migration có phiên bản** (`supabase/migrations/`) thay cho một file `schema.sql`; tài liệu backup/restore. | `supabase/` | Không | S | Không |
| P2-9 | Dọn code trùng `src/` (chỉ khi được phép) và cập nhật `AGENTS.md` theo kiến trúc Nuxt. | `src/*`, `AGENTS.md` | Không | S | Q11 |

### P3 — Nâng cao / tương lai

| Mã | Ý tưởng | Công sức |
|---|---|---|
| P3-1 | CTV đa cấp / bậc thang hoa hồng theo doanh số / thưởng đạt chỉ tiêu | L |
| P3-2 | Mã giảm giá riêng theo CTV (coupon-as-referral) | M |
| P3-3 | Xác nhận thanh toán VietQR tự động (webhook ngân hàng), thay nút "ĐÃ CHUYỂN KHOẢN" | L |
| P3-4 | Thời gian giữ hoa hồng (hold N ngày) tự động duyệt theo lịch | M |
| P3-5 | 2FA cho admin, giới hạn IP, captcha toàn site (Turnstile) | M |
| P3-6 | Báo cáo thuế/hợp đồng CTV, xuất chứng từ chi trả | M |
| P3-7 | Kiểm thử e2e tự động (Playwright) cho luồng tiền; CI chạy migration | L |
| P3-8 | Short-link & QR cho CTV, UTM, báo cáo theo chiến dịch | M |

---

## 5. Đề xuất thay đổi Database / API (chỉ mô tả)

### 5.1 Bảng mới

| Bảng | Mục đích | Cột chính |
|---|---|---|
| `products`, `product_categories` | Nguồn giá/sản phẩm phía server | id, tên, danh mục, giá cơ bản, active |
| `coupons` | Mã giảm giá quản lý ở server | code, loại (cố định/%), giá trị, hạn, giới hạn lượt, active |
| `order_items` | Chuẩn hóa mặt hàng | order_id, product_id, tên, cấu hình xe (hãng/dòng/năm), chất liệu, màu, đơn giá, số lượng |
| `commission_rules` | Hoa hồng theo CTV/sản phẩm | affiliate_id (null = mặc định), product_id (null = mọi sản phẩm), rate, hiệu lực từ–đến |
| `commissions` | **Sổ cái hoa hồng**, 1 dòng/đơn (hoặc /item) | order_id, affiliate_id, base_amount, rate, amount, status (`pending/approved/paid/reversed`), approved_at/by, reversed_reason, payout_id; khoản âm cho clawback |
| `payout_requests` | Yêu cầu rút tiền | affiliate_id, amount, status (`requested/approved/rejected/paid`), bank snapshot, lý do, thời điểm |
| `payouts`, `payout_items` | Chi trả bất biến + liên kết hoa hồng | payout: affiliate_id, amount, note, idempotency_key, created_by (DB gán); item: payout_id, commission_id |
| `affiliate_bank_accounts` | Ngân hàng của CTV | affiliate_id, ngân hàng, số tài khoản, chủ tài khoản, verified_by/at |
| `referral_clicks` | Click link giới thiệu | affiliate_id, thời điểm, landing path, session/fingerprint ẩn danh, ip_hash, user_agent |
| `audit_logs` | Nhật ký thay đổi | actor_id, hành động, bảng, record_id, giá trị cũ/mới (jsonb), thời điểm |
| `customers` (tùy chọn) | Khách hàng | tên, SĐT (unique), địa chỉ, ghi chú |
| `inventory` (tùy chọn) | Tồn kho | product_id/SKU, số lượng, ngưỡng cảnh báo |

### 5.2 Sửa bảng hiện có

| Bảng | Thay đổi |
|---|---|
| `orders` | Thêm `payment_status`, `subtotal`, `discount_amount`, `shipping_fee`, `customer_id`, `ref_source`, `ref_click_id`, `attributed_at`, `updated_at`, `updated_by`; trạng thái thêm `returned`; **bỏ** quyền insert trực tiếp của anon; `commission_*` chuyển sang `commissions` (giữ cột cũ trong giai đoạn chuyển tiếp) |
| `affiliates` | Thêm `approved_at/by`, `reject_reason`, `permissions`/vai trò `staff`; trigger chặn đổi `role/user_id/code/email` ngoài RPC; siết policy update |
| `leads` | CTV chỉ đọc qua RPC đã che SĐT |
| `commission_payouts` | Bỏ policy update; liên kết với `payout_items`; `created_by` ép bằng `auth.uid()` |

### 5.3 RPC / API đề xuất

| Nhóm | RPC / Edge Function | Mô tả |
|---|---|---|
| Public | `create_order` | Tính lại giá, kiểm mã giảm giá & mã CTV, ép trạng thái, sinh mã đơn, ghi `ref_*`, chống spam |
| Public | `track_click` | Ghi click có dedupe/rate-limit |
| Public | `create_lead` | Gửi tư vấn, gắn CTV hợp lệ |
| CTV | `ctv_overview` | KPI (đơn, doanh thu, hoa hồng 3 trạng thái, số dư khả dụng, click, CR) |
| CTV | `ctv_list_orders(page, filter)` | Đơn đã che PII |
| CTV | `ctv_list_commissions`, `ctv_list_payouts` | Lịch sử hoa hồng/chi trả |
| CTV | `ctv_request_payout`, `ctv_update_profile`, `ctv_update_bank` | Rút tiền, hồ sơ, ngân hàng |
| Admin | `admin_list_orders(filter, page)`, `admin_get_order` | Danh sách/chi tiết có phân trang server |
| Admin | `admin_set_order_status(order, status, reason)` | Kiểm luồng trạng thái + xử lý hoa hồng |
| Admin | `admin_update_affiliate(id, fields, reason)` | Whitelist cột |
| Admin | `admin_approve_commissions(ids)`, `admin_pay_commissions(...)`, `admin_review_payout_request(...)` | Duyệt/chi trả trong transaction |
| Admin | `admin_reports(from, to)`, export | Dashboard, top CTV/sản phẩm, xuất file |
| Develop | `develop_set_account_role` (giữ, bổ sung audit) | Đổi vai trò |

### 5.4 Thay đổi RLS (nguyên tắc)
- `orders`/`leads`: anon **không** insert trực tiếp; CTV **không** select trực tiếp (đi qua RPC); admin/staff theo quyền.
- `affiliates`: người dùng chỉ đọc hồ sơ của mình; mọi update đi qua RPC/whitelist.
- `payouts`, `commissions`, `audit_logs`: **chỉ thêm**, không sửa/xóa qua API client.

### 5.5 Index đề xuất
`orders(status, created_at)`, `orders(affiliate_code)` (lưu chuẩn hóa chữ hoa, bỏ `upper()` trong policy), `commissions(affiliate_id, status)`, `payout_requests(affiliate_id, status)`, `referral_clicks(affiliate_id, created_at)`, `leads(affiliate_code)`, `audit_logs(record_id, created_at)`.

---

## 6. Danh sách test case sau cải tiến

### 6.1 Bảo mật & phân quyền
| ID | Kịch bản | Kết quả mong đợi |
|---|---|---|
| T01 | Anon gọi REST `insert` trực tiếp vào `orders` | Bị từ chối |
| T02 | Gọi `create_order` với `total_amount`/`status='completed'`/`commission_status='paid'` do client gửi | Bị bỏ qua; đơn ra `new/pending` với giá do server tính |
| T03 | Gửi giá âm/0, số lượng âm, mã giảm giá không tồn tại/hết hạn | Từ chối hoặc không áp dụng, có thông báo rõ |
| T04 | Admin (không phải develop) `update affiliates set role='develop'` trực tiếp | Bị từ chối |
| T05 | Admin sửa `user_id/email/code` của CTV khác | Bị từ chối |
| T06 | CTV A truy cập đơn/chi trả/hoa hồng của CTV B (đổi tham số, gọi REST) | 0 dòng / từ chối |
| T07 | CTV gọi RPC/API admin (đổi trạng thái đơn, duyệt hoa hồng, chi trả) | Bị từ chối |
| T08 | CTV gọi API lấy đơn: kiểm tra response | Không chứa SĐT/email/địa chỉ/ghi chú; tên đã rút gọn |
| T09 | CTV bị khóa/chờ duyệt gọi các API dữ liệu | 0 dòng / từ chối |
| T10 | Spam 50 đơn/lead trong 1 phút từ cùng nguồn | Bị giới hạn tần suất / captcha |
| T11 | Staff (không có quyền chi trả) gọi `admin_pay_commissions` | Bị từ chối |
| T12 | Develop tự hạ quyền chính mình / hạ develop cuối cùng | Bị chặn |

### 6.2 Tiền & hoa hồng
| ID | Kịch bản | Kết quả mong đợi |
|---|---|---|
| T13 | Đơn có mã CTV hợp lệ, có/không mã giảm giá | Hoa hồng = tỷ lệ × cơ sở tính (theo Q1), làm tròn nhất quán |
| T14 | Đổi % hoa hồng CTV sau khi đã có đơn | Đơn cũ giữ tỷ lệ cũ, đơn mới dùng tỷ lệ mới |
| T15 | Hoa hồng theo sản phẩm vs theo CTV (cùng đơn) | Áp đúng thứ tự ưu tiên của `commission_rules` |
| T16 | Hủy đơn khi hoa hồng đang `pending` | Hoa hồng → `reversed`, không vào công nợ |
| T17 | Hủy/hoàn đơn khi hoa hồng đã `approved` | `reversed`, không chi trả |
| T18 | Hủy/hoàn đơn khi hoa hồng đã `paid` | Phát sinh khoản **âm** bù trừ vào lần chi tiếp theo; hiển thị rõ cho CTV |
| T19 | Chuyển trạng thái đơn không hợp lệ (vd `completed → new`) | Bị từ chối |
| T20 | Duyệt hoa hồng 2 lần liên tiếp (bấm đúp / 2 admin cùng lúc) | Chỉ duyệt 1 lần, không nhân đôi |
| T21 | Chi trả 2 lần cùng `idempotency_key` / bấm đúp | Chỉ 1 payout |
| T22 | Chi trả gặp lỗi giữa chừng (giả lập) | Rollback toàn bộ, không lệch `commissions`/`payouts` |
| T23 | Chi trả bằng `commission_id` đã `paid` hoặc của CTV khác | Bị từ chối |
| T24 | Sửa/xóa bản ghi payout qua API | Bị từ chối (bất biến) |
| T25 | Có > 500 đơn: so KPI admin/CTV với `SUM` trực tiếp trong DB | Khớp tuyệt đối |
| T26 | Số dư CTV (hiển thị) = tổng `approved` − yêu cầu rút đang chờ | Khớp với số admin thấy |
| T27 | Yêu cầu rút vượt số dư / dưới hạn mức | Bị từ chối |
| T28 | Duyệt yêu cầu rút → đánh dấu đã chi | Trạng thái, số dư và lịch sử chi trả cập nhật đồng nhất cả 2 phía |

### 6.3 Attribution & luồng
| ID | Kịch bản | Kết quả mong đợi |
|---|---|---|
| T29 | Vào bằng `?ref=CODE`, đặt đơn trong TTL | Đơn gắn đúng CTV; click được ghi nhận |
| T30 | Đặt đơn sau khi quá TTL | Không gắn CTV |
| T31 | Vào bằng 2 link CTV khác nhau liên tiếp | Theo quy tắc đã chốt (first/last-click) |
| T32 | Nhập tay mã không tồn tại / CTV bị khóa / chờ duyệt | Không ghi nhận, báo rõ cho khách |
| T33 | CTV tự đặt đơn bằng mã của mình (cùng SĐT/email) | Bị chặn hoặc không tính hoa hồng (theo Q13) |
| T34 | Đăng ký CTV với mã trùng/từ khóa cấm | Mã hiển thị trên màn hình thành công **bằng** mã trong DB |
| T35 | Click bot/lặp từ cùng nguồn | Dedupe/giới hạn; tỷ lệ chuyển đổi không bị thổi phồng |

### 6.4 Admin & UX
| ID | Kịch bản | Kết quả mong đợi |
|---|---|---|
| T36 | Duyệt/từ chối/khóa CTV kèm lý do | CTV nhận email; trạng thái hiển thị đúng; có dòng audit |
| T37 | Mọi thay đổi nhạy cảm (trạng thái đơn, % hoa hồng, vai trò, duyệt/chi trả) | Có bản ghi `audit_logs` đúng người/giá trị cũ-mới |
| T38 | Phân trang/tìm/lọc server với 10.000 đơn | Phản hồi < 1 giây, kết quả đúng |
| T39 | Xuất CSV/Excel theo bộ lọc | File khớp dữ liệu màn hình, tiếng Việt hiển thị đúng |
| T40 | Ngắt mạng/DB lỗi khi tải | Thấy thông báo lỗi + nút thử lại (không hiện "rỗng") |
| T41 | Đổi mật khẩu, quên mật khẩu, cập nhật ngân hàng (CTV) | Hoạt động; thay đổi ngân hàng cần admin xác minh trước khi chi |
| T42 | Responsive 390 / 768 / 1440px cho tab/modal mới | Không tràn ngang; nút ≥ 44px trên mobile |
| T43 | Điều hướng bàn phím & focus-visible ở các màn mới | Dùng được, tương phản đạt AA |

---

## 7. Câu hỏi cần anh/chị xác nhận trước khi code

| # | Câu hỏi | Gợi ý của tôi |
|---|---|---|
| Q1 | Hoa hồng tính trên giá trị nào: **sau mã giảm giá**, trước giảm giá, có trừ phí ship/lắp đặt không? Có tính theo từng sản phẩm không? | Sau giảm giá, không gồm ship |
| Q2 | Điều kiện hoa hồng đủ để chi: khi đơn `completed`, hay phải **giữ N ngày** (thời hạn đổi trả 1-1)? | Hold 7–14 ngày sau hoàn thành |
| Q3 | Đơn hoàn **sau khi đã chi** hoa hồng: trừ vào kỳ sau (clawback) hay yêu cầu CTV hoàn lại? | Trừ vào kỳ sau |
| Q4 | Attribution: **first-click hay last-click**? Giữ TTL 30 ngày? Có cho khách nhập tay mã CTV ở bước thanh toán không? | Last-click, 30 ngày, vẫn cho nhập nhưng phải hợp lệ |
| Q5 | Rút tiền: hạn mức tối thiểu, chu kỳ (tuần/tháng), có phí/khấu trừ thuế không? | Tối thiểu 200.000 đ, chi theo tuần |
| Q6 | Giữ kiến trúc **Supabase thuần (RPC + RLS)** hay thêm lớp server Nuxt (`server/api`) dùng service key? | Giữ Supabase + RPC/Edge Function, chưa cần Node riêng |
| Q7 | Vai trò **nhân viên**: cần những quyền nào (xử lý đơn, duyệt CTV, duyệt/chi hoa hồng, xem báo cáo...)? | Cần danh sách cụ thể |
| Q8 | Phạm vi quản lý **sản phẩm / tồn kho / khách hàng**: làm trong đợt này (P1-7, P2-5, P2-6) hay để sau? Catalog hiện hard-code ở `vehicles.ts`. | Làm P1-7 trước (cần cho P0-1); tồn kho để sau |
| Q9 | Có muốn **tự xác nhận thanh toán VietQR** (webhook ngân hàng) không, hay admin xác nhận tay? | Tay trước, tự động ở P3 |
| Q10 | DB production đã có **dữ liệu thật** chưa? Có thể gửi `schema` thực tế (dump) để so với `supabase/schema.sql`? Cho phép chạy migration/backfill? | Cần để đánh giá chính xác P0-8 |
| Q11 | Cho phép **xóa/lưu trữ thư mục `src/` legacy** và **cập nhật `AGENTS.md`** (đang mô tả Vite/prerender, không khớp Nuxt)? Hiện `AGENTS.md` cấm xóa file nên tôi không tự làm. | Đồng ý, làm ở P2-9 |
| Q12 | Kênh thông báo: **email (SMTP/Resend)**, **Telegram**, hay cả hai? Email nhận: `dothanh0711@gmail.com`? | Email + Telegram |
| Q13 | CTV **tự đặt đơn bằng mã của mình**: chặn hẳn, hay cho phép nhưng không tính hoa hồng? | Không tính hoa hồng |
| Q14 | Giai đoạn chuyển tiếp: cho phép **tạm ngưng nhận đơn** vài giờ khi đổi cách đặt đơn (P0-1), hay phải chạy song song? | Chạy song song có cờ tính năng |

---

## 8. Giả định đã đặt ra
- `supabase/schema.sql` phản ánh đúng DB đang chạy (cần xác nhận ở Q10).
- Dự án đang dùng bản Nuxt (`app/`); `src/` là bản cũ không còn được build (`package.json` → `nuxt build`, `nuxt.config.ts:38-50` redirect).
- Chưa có dữ liệu tiền thật quan trọng cần bảo toàn; nếu đã có, P0-8 phải làm đầu tiên.
- Ước lượng công sức tính cho 1 dev quen Nuxt + Supabase, chưa gồm thời gian anh/chị duyệt và kiểm thử trên môi trường thật.

---

> **Lưu ý theo `AGENTS.md`:** sau khi duyệt kế hoạch, mỗi giai đoạn sẽ chạy dev server, chụp screenshot 390/768/1440px, và chạy `npm run build` trước khi chuyển giai đoạn.
