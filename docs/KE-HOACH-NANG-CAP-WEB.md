# KẾ HOẠCH NÂNG CẤP WEB – TRUNG THÀNH AUTO (`d:\thamoto`)

> Tài liệu **chỉ đánh giá và đề xuất**, chưa sửa code/DB nào.
> Số dòng trích dẫn tính tại thời điểm rà soát (25/11/2026), có thể lệch nhẹ nếu file đã đổi.
> Ký hiệu: 🔴 nghiêm trọng · 🟡 trung bình · 🟢 nhẹ. Effort: S (< 1 ngày) · M (1–3 ngày) · L (> 3 ngày).

---

## 0. Phạm vi & giới hạn của đợt rà soát

- **Đã đọc**: `nuxt.config.ts`, `package.json`, `.gitignore`, các page khách (`thanh-toan.vue`, `gio-hang.vue`, `index.vue`, `chi-tiet.vue`, `lien-he.vue`…), `admin.vue`, `ctv.vue`, composables, middleware, `supabase/schema.sql` (RPC/RLS/grant), 10 file migration, Edge Function `notify-order`, `tests/*`, `public/sitemap.xml`, `robots.txt`, `scripts/prerender.cjs`.
- **Chưa kiểm chứng được** (cần bạn xác nhận hoặc chạy thử): cấu hình thật trên Supabase Dashboard (Auth, Database Webhook gọi `notify-order`, rate limit), cấu hình Vercel, dữ liệu thật trong DB, kết quả chạy `tests/sql/verify-business-rules.sql` trên DB thật.
- Không đọc nội dung `.env` (chỉ xác nhận `.env` đã nằm trong `.gitignore`, dòng 20–22).

---

## 1. Khảo sát hiện trạng

### 1.1 Tech stack & triển khai

| Hạng mục | Hiện trạng | Bằng chứng |
|---|---|---|
| Framework | Nuxt 4 + Vue 3 + Tailwind (module `@nuxtjs/tailwindcss`) | `package.json`, `nuxt.config.ts:5` |
| Backend | **Không có API Nitro** (`server/` rỗng). Toàn bộ logic nằm ở Supabase: RLS + RPC `security definer` + 1 Edge Function | `server/` rỗng; `supabase/schema.sql` |
| DB | Postgres (Supabase), schema + 10 migration | `supabase/migrations/20261125_000…008` |
| Auth | Supabase Auth; phân quyền bằng `affiliates.role` (`ctv`/`staff`/`admin`/`develop`) | `schema.sql` (`is_admin`, `has_permission`…) |
| Thông báo | Edge Function Telegram (`order_created`, `payout_*`) | `supabase/functions/notify-order/index.ts` |
| Deploy | Suy ra Vercel (sitemap `thamoto.vercel.app`, `.vercel/` trong `.gitignore`) – **cần xác nhận** | `public/sitemap.xml:4`, `.gitignore:16` |
| Test | `node --test` cho bản TS mô phỏng luật nghiệp vụ + 1 file SQL chạy tay | `tests/commerce-rules.test.ts` (450 dòng), `tests/sql/verify-business-rules.sql` (154 dòng) |
| Code cũ | `src/` (Vite cũ), `scripts/prerender.cjs`, `vite.config.js` vẫn còn song song với `app/` | cây thư mục |
| Thư viện | `@supabase/supabase-js`, `lucide-vue-next`, `nuxt`, `vue`, `vue-router` – gọn | `package.json` |

### 1.2 Tính năng hiện có theo nhóm

| Nhóm | Tính năng | File chính |
|---|---|---|
| **Khách** | Trang chủ, lọc hãng/dòng/năm, bán chạy, ảnh lắp đặt | `app/pages/index.vue`, `shared/utils/vehicles.ts` |
| | Danh sách dòng xe theo hãng | `app/pages/san-pham/index.vue` |
| | Chọn đời xe/chất liệu/màu/ưu đãi, giá động (lấy giá từ DB qua `get_catalog_prices`) | `app/pages/chi-tiet.vue` |
| | Giỏ hàng (localStorage), mã giảm giá (`validate_coupon`) | `app/composables/useCart.ts`, `app/pages/gio-hang.vue`, `CartDrawer.vue` |
| | Thanh toán COD / VietQR, nhập mã CTV (`validate_affiliate_code`), tạo đơn (`create_order`) | `app/pages/thanh-toan.vue` |
| | Liên hệ/đặt đo xe (`create_lead`), giới thiệu, tin tức | `lien-he.vue`, `gioi-thieu.vue`, `tin-tuc/*` |
| | Đăng ký CTV | `app/pages/cong-tac-vien.vue` |
| **Admin** | Tổng quan, đơn hàng (đổi trạng thái, thanh toán), CTV, lead, chi trả hoa hồng, yêu cầu rút tiền, đối soát | `app/pages/admin.vue` |
| | Catalog (sản phẩm, coupon, quy tắc hoa hồng, cài đặt), khách hàng, báo cáo, nhật ký audit | `app/components/admin/*Tab.vue` |
| | Chi tiết đơn / chi tiết CTV | `OrderDetailModal.vue`, `AffiliateDetailModal.vue` |
| **CTV** | Hồ sơ, tài khoản ngân hàng, đơn/lead (che PII), sổ cái hoa hồng, yêu cầu rút tiền, link giới thiệu, đo click | `app/pages/ctv.vue`, `useAffiliate.ts` |
| **Hệ thống** | Ledger hoa hồng (`holding → available → paid`), reversal khi hủy/hoàn, audit append-only, trừ/hoàn tồn kho bằng trigger | `schema.sql` (~1720–2220, 3677–3760) |

---

## 2. Tóm tắt hiện trạng

**Điểm mạnh**
- Nền tảng tiền/hoa hồng **làm đúng hướng**: giá, giảm giá, hoa hồng đều do server tính (`create_order`, `schema.sql:1112–1385`), client không quyết định số tiền.
- Ghi trực tiếp `orders`/`leads` đã bị gỡ; CTV chỉ đọc qua RPC che PII; có audit log, idempotency khi chi trả, trừ/hoàn tồn kho bằng trigger.
- Có bộ test luật nghiệp vụ (450 dòng) + test SQL transactional.
- Giao diện gọn, đa số ảnh WebP có `width/height`, có `aria-label`, `role="alert"`.

**Điểm yếu**
- **Thanh toán & vận chuyển gần như chưa có** (QR tĩnh, không đối soát; phí ship cố định "Miễn phí").
- **SEO mới ở mức cơ bản**: không OG/JSON-LD/canonical, sitemap tĩnh dùng URL `.html` cũ.
- Chưa có tra cứu đơn cho khách; testimonial/best-seller hardcode.
- Chống spam đơn chỉ theo SĐT → có thể bị rút cạn tồn kho bằng đơn giả.
- Code cũ (`src/`, prerender) song song gây nợ kỹ thuật; `admin.vue` 1.375 dòng, `ctv.vue` 1.008 dòng.

**Điểm tổng thể: 6,0 / 10** (trung bình 9 nhóm) – lõi nghiệp vụ tốt, thiếu mảng thương mại điện tử "ngoài rìa" (thanh toán, vận chuyển, SEO, tra cứu).

---

## 3. Bảng chấm điểm 9 nhóm

| # | Nhóm | Điểm | Lý do chính (bằng chứng) |
|---|---|---|---|
| 1 | UX mua hàng & chuyển đổi | **6/10** | Luồng rõ (YMM → chi tiết → giỏ → thanh toán), giá động từ DB. Thiếu: tra cứu đơn, hiển thị tồn kho, review thật (`index.vue:50–55` hardcode), giá giỏ lấy từ client |
| 2 | Thanh toán & vận chuyển | **3/10** | QR là ảnh mock + STK hardcode (`thanh-toan.vue:327–335`); nút "ĐÃ CHUYỂN KHOẢN" tạo đơn không xác minh (`:340`); phí ship cố định (`:298`); chỉ COD/VietQR (`schema.sql:1174`) |
| 3 | SEO & marketing | **4/10** | Có `useSeoMeta` mỗi trang; không OG/JSON-LD/canonical/sitemap động; sitemap URL `.html` (`sitemap.xml:10,16`); chưa có GA/Pixel |
| 4 | CTV & hoa hồng | **8/10** | Ledger, holding, reversal, thuế TNCN, payout request, chống tự giới thiệu (`schema.sql:1296–1299`), PII mask. Thiếu: hoàn coupon, một số báo cáo CTV |
| 5 | Admin & vận hành | **7/10** | Đủ tab, phân trang RPC, audit, catalog RPC. Thiếu: nhập mã vận đơn, in phiếu, tồn kho cảnh báo; file quá lớn |
| 6 | Bảo mật | **7/10** | RLS bật, `revoke … from public`, secrets không commit. Lỗi: `notify-order` fail-open (`index.ts:23`), không captcha, không security headers |
| 7 | Toàn vẹn dữ liệu | **7/10** | Server-side pricing, trigger tồn kho, idempotent payout. Lỗi: `used_count` coupon không hoàn khi hủy (`schema.sql:1279`), hai migration cùng prefix `007` |
| 8 | Hiệu năng & chất lượng code | **5/10** | Gọn dependency, ảnh WebP; nhưng Google Font chặn render (`nuxt.config.ts:31`), code Vite cũ song song, file 1k+ dòng, test không chạy trên SQL thật, chưa thấy CI |
| 9 | UI & mobile | **7/10** | Mobile-first, nút ≥44px, `aria-label`. Vài ảnh hero/lightbox thiếu `loading`/alt chưa đồng đều (`gioi-thieu.vue:41` thiếu `alt`) |

**Tổng: 54/90 = 6,0/10**

---

## 4. Danh sách vấn đề phát hiện

| ID | Mô tả | File / dòng | Mức | Hậu quả |
|---|---|---|---|---|
| I-01 | Edge Function `notify-order` **bỏ qua xác thực** nếu chưa đặt `NOTIFY_WEBHOOK_SECRET` (`expectedSecret && …`) | `supabase/functions/notify-order/index.ts:21–25` | 🔴 | Ai biết URL cũng gửi được thông báo giả vào Telegram nội bộ; lộ/giả mạo dữ liệu đơn |
| I-02 | Chống spam đơn chỉ theo SĐT (5 đơn/10 phút), không captcha/IP; mỗi đơn **trừ tồn kho ngay** khi insert `order_items` | `schema.sql:1181–1187`, trigger `3680–3715` | 🔴 | Đổi SĐT liên tục → rút cạn `stock_qty`, hết hàng ảo, rác đơn |
| I-03 | `coupons.used_count` tăng khi tạo đơn nhưng **không hoàn khi hủy/hoàn** (grep `used_count` chỉ có ở 831, 1048, 1279) | `schema.sql:1279`, `1927+` | 🟡 | Mã giảm giá cạn lượt vì đơn hủy → mất doanh thu khuyến mãi |
| I-04 | VietQR: STK hardcode, ảnh QR tĩnh, nội dung CK `TT {SĐT}` (không phải mã đơn); modal hiện **trước** khi có đơn; bấm "ĐÃ CHUYỂN KHOẢN" là tạo đơn, không đối soát | `thanh-toan.vue:327–340`, `:170–173` | 🔴 | Không biết ai đã trả; đối soát thủ công, sai/ thiếu tiền khó truy vết |
| I-05 | Phí vận chuyển cố định "Miễn phí", DB không có cột phí ship | `thanh-toan.vue:298`; `create_order` không có shipping | 🟡 | Lỗ phí ship xa; không điều chỉnh được theo vùng/đơn |
| I-06 | Giá trong giỏ lưu ở localStorage, hiển thị tổng tạm tính từ giá cũ; server tính lại nên **số trên màn hình thành công có thể khác** lúc thanh toán | `useCart.ts:29,42`; `thanh-toan.vue:64`, `:127` | 🟡 | Khách bất ngờ về giá, mất niềm tin/hủy đơn |
| I-07 | SEO: không có og/twitter/canonical/JSON-LD; sitemap tĩnh, URL `.html` kiểu cũ trong khi route Nuxt không còn `.html` (chỉ redirect) | `nuxt.config.ts:16–50`, `public/sitemap.xml:10,16` | 🟡 | Index kém, share mạng xã hội không có ảnh/tiêu đề; sitemap dẫn tới URL redirect |
| I-08 | Các trang riêng tư (`/admin`, `/ctv`, `/gio-hang`, `/thanh-toan`) chưa chặn index trong `robots.txt` | `public/robots.txt:1–4` | 🟡 | Google lập chỉ mục trang đăng nhập/giỏ hàng |
| I-09 | Middleware `auth-admin` không chặn gì, chỉ làm mới session; kiểm tra role ở client sau khi `select affiliates` | `app/middleware/auth-admin.ts:7–9`, `admin.vue:448` | 🟢 | Chấp nhận được vì bảo mật thật ở RLS/RPC; chỉ ảnh hưởng UX (tải thừa JS admin) |
| I-10 | Hai migration cùng prefix `007` (`007_p0_permissions_catalog_audit`, `007_p2_stock_sync`); tài liệu hướng dẫn chỉ nhắc một | `supabase/migrations/`, `docs/HUONG-DAN-MIGRATION-VA-TEST.md` | 🟡 | Dễ chạy sót/sai thứ tự khi dựng DB mới |
| I-11 | Best-seller và testimonial **hardcode** trong code, giá tay `1500000`… có thể lệch DB | `app/pages/index.vue:43–48`, `:50–55` | 🟡 | Giá trang chủ ≠ giá thật; review "ảo" ảnh hưởng uy tín |
| I-12 | Không có trang tra cứu trạng thái đơn cho khách; khách chỉ biết mã đơn ở màn hình thành công | không có route | 🟡 | Tăng cuộc gọi/Zalo hỏi đơn, giảm tin tưởng |
| I-13 | Không hiển thị tồn kho ở frontend (`stock_qty` chỉ xuất hiện ở `CatalogTab.vue`); đặt hết hàng chỉ báo lỗi ở bước cuối | `CatalogTab.vue:14,57,75`; trigger `schema.sql:3693` | 🟡 | Khách đi hết luồng mới biết hết hàng |
| I-14 | Mã đơn dự phòng sinh ngẫu nhiên ở client khi chưa cấu hình Supabase, vẫn hiện "Đặt hàng thành công" | `thanh-toan.vue:96`, `:101` | 🟢 | Chỉ xảy ra lỗi cấu hình, nhưng có thể gây hiểu lầm đã đặt đơn thật |
| I-15 | Không có security headers (CSP, X-Frame-Options, Referrer-Policy…) | `nuxt.config.ts` (chỉ `routeRules` redirect) | 🟡 | Rủi ro clickjacking/XSS lan rộng |
| I-16 | Google Fonts nạp bằng `<link rel=stylesheet>` chặn render | `nuxt.config.ts:29–31` | 🟢 | LCP chậm trên mobile |
| I-17 | Code cũ song song: `src/*.html`, `scripts/prerender.cjs` (bảng sản phẩm tĩnh `:43–56`, preconnect CDN Tailwind `:22–25`), `vite.config.js` | `src/`, `scripts/prerender.cjs` | 🟢 | Nhầm lẫn, dữ liệu cũ lệch giá, nợ bảo trì |
| I-18 | `admin.vue` 1.375 dòng, `ctv.vue` 1.008 dòng trong một file | `app/pages/admin.vue`, `ctv.vue` | 🟢 | Khó sửa, dễ regress |
| I-19 | Test luật nghiệp vụ chạy trên **bản TS mô phỏng** (`shared/utils/commerce-rules.ts`), không chạy trên RPC thật; test SQL chạy tay; chưa thấy CI | `tests/commerce-rules.test.ts:3–18`, `tests/sql/…` | 🟡 | SQL đổi nhưng TS không đổi → test vẫn xanh nhưng sai |
| I-20 | Telegram dùng `parse_mode: 'Markdown'` với dữ liệu khách nhập (tên/địa chỉ) | `notify-order/index.ts:76` | 🟢 | Ký tự đặc biệt làm Telegram từ chối tin (mất thông báo đơn) |
| I-21 | Chưa thấy cấu hình Database Webhook/trigger gọi `notify-order` trong SQL (grep `notify-order` trong `schema.sql` = 0) | `schema.sql` | 🟡 | Có thể thông báo đơn chưa hoạt động — **cần xác nhận trên Dashboard** |

---

## 5. Lộ trình theo giai đoạn

### P0 – Bảo mật & sai tiền / hoa hồng / tồn kho

| ID | Việc cần làm | File/module | Thay đổi DB | Effort | Lợi ích | Phụ thuộc |
|---|---|---|---|---|---|---|
| P0-1 | Chuyển `notify-order` sang **fail-closed**: thiếu `NOTIFY_WEBHOOK_SECRET` → trả 500/401; escape ký tự Telegram (hoặc bỏ `parse_mode`) | `supabase/functions/notify-order/index.ts` | Không | S | Chặn thông báo giả, không mất tin | – (I-01, I-20) |
| P0-2 | Chống đơn giả/rút kho: thêm Cloudflare Turnstile (hoặc hCaptcha) ở `thanh-toan`/`lien-he`; giới hạn thêm theo `customer_ip`/session; đặt **hạn giữ kho** cho đơn `new` quá N giờ chưa xác nhận (tự hủy + hoàn kho) | `thanh-toan.vue`, `lien-he.vue`, `create_order`, `create_lead` | Thêm cột `orders.client_fingerprint`, job/RPC `expire_stale_orders` | M | Bảo vệ tồn kho, giảm rác | Quyết định dùng captcha nào (Câu hỏi 3) |
| P0-3 | Hoàn `coupons.used_count` khi đơn `cancelled/returned` (trigger cạnh `restore_stock_on_order_cancel`); thêm giới hạn **1 lần/SĐT** nếu cần | `schema.sql` / migration mới | Trigger mới; có thể thêm bảng `coupon_redemptions(order_id, coupon_code, phone)` | S–M | Tránh mất lượt coupon oan | Xác nhận luật coupon (Câu hỏi 6) |
| P0-4 | Dọn thứ tự migration: đổi tên `007_p2_stock_sync` thành `009` (hoặc ghi rõ thứ tự) và cập nhật doc; xác nhận DB thật đã chạy đúng thứ tự | `supabase/migrations/`, `docs/HUONG-DAN-MIGRATION-VA-TEST.md` | Không (chỉ đổi tên/ghi chú) | S | Dựng DB mới không sai | Cần bạn đồng ý đổi tên (Câu hỏi 8) |
| P0-5 | Chạy `tests/sql/verify-business-rules.sql` trên DB thật, rà lại policy "Affiliates can insert own signup" (không cho tự đặt `role`/`status`/`commission_rate`) | `schema.sql:243–250`, trigger whitelist ở `007_p0_*` | Có thể vá trigger | S | Chốt không leo quyền | – |

### P1 – Thiếu sót ảnh hưởng doanh thu trực tiếp

| ID | Việc cần làm | File/module | Thay đổi DB | Effort | Lợi ích | Phụ thuộc |
|---|---|---|---|---|---|---|
| P1-1a | **Tạo đơn trước, rồi mới hiện QR**: nội dung CK = mã đơn, số tiền = `total_amount` từ server; STK/ngân hàng đọc từ `app_settings` (không hardcode) | `thanh-toan.vue:327–340`, `app_settings` | Thêm key `bank_name`, `bank_account`, `bank_holder` | S–M | Đối soát được theo mã đơn | – (I-04) |
| P1-1b | Đối soát tự động: Edge Function nhận webhook cổng/ngân hàng (SePay, payOS… theo lựa chọn), khớp mã đơn → `payment_status='paid'` (idempotent) | `supabase/functions/payment-webhook` (mới), RPC `system_mark_paid` | Bảng `payment_events(id, provider, ref, order_id, amount, raw jsonb, created_at unique(provider,ref))`; cột `orders.payment_ref`, `paid_at` | M–L | Giảm đối soát tay, giảm sai sót | P1-1a, Câu hỏi 2 |
| P1-2 | Phí vận chuyển: `app_settings` (phí cơ bản, ngưỡng miễn phí, phí theo vùng đơn giản) → `create_order` cộng vào tổng, hiển thị ở checkout; admin nhập **mã vận đơn/đơn vị vận chuyển** (chưa tích hợp API) | `create_order`, `thanh-toan.vue`, `OrderDetailModal.vue` | `orders.shipping_fee`, `shipping_carrier`, `tracking_code`; settings `shipping_*` | M | Không lỗ ship, khách thấy rõ tổng | Câu hỏi 4 |
| P1-3 | Tra cứu đơn: trang `/tra-cuu-don` + RPC `track_order(p_order_code, p_phone)` (chỉ trả trạng thái, không PII đầy đủ) | `app/pages/tra-cuu-don.vue` (mới), `AppFooter/Header` | RPC mới, không cột mới | M | Giảm hỏi đáp, tăng tin tưởng | – |
| P1-4 | Làm mới giá giỏ hàng: ở `gio-hang`/`thanh-toan`, gọi lại `get_catalog_prices` (hoặc RPC `preview_order`) để cập nhật giá & báo thay đổi trước khi đặt | `useCart.ts`, `gio-hang.vue`, `thanh-toan.vue` | RPC `preview_order(items, coupon)` (tuỳ chọn) | M | Hết lệch giá hiển thị/thực tế | – (I-06) |
| P1-5 | Hiển thị tồn kho/“Hết hàng” ở `chi-tiet`; chặn thêm giỏ khi hết | `chi-tiet.vue`, `get_catalog_prices` | Thêm `in_stock bool` (không lộ số lượng) vào kết quả RPC | S–M | Không mất khách ở bước cuối | – (I-13) |
| P1-6 | SEO cơ bản: og/twitter mặc định + theo trang, canonical, JSON-LD (`Organization`, `Product`, `BreadcrumbList`, `Article`), sitemap động (module `@nuxtjs/sitemap` hoặc route), `robots.txt` chặn `/admin`,`/ctv`,`/gio-hang`,`/thanh-toan`; `noindex` cho các trang đó | `nuxt.config.ts`, `app/pages/*`, `public/robots.txt`, bỏ `public/sitemap.xml` tĩnh | Không | M | Index sạch, share đẹp, rich result | Thêm 1 module (nhẹ) cần bạn duyệt |
| P1-7 | Security headers (X-Frame-Options, X-Content-Type-Options, Referrer-Policy, CSP report-only trước) qua `routeRules.headers` | `nuxt.config.ts` | Không | S | Giảm clickjacking/XSS | – |

### P2 – Chuyển đổi & giữ chân

| ID | Việc cần làm | File/module | DB | Effort | Lợi ích | Phụ thuộc |
|---|---|---|---|---|---|---|
| P2-1 | Best-seller lấy từ DB (`products.is_featured`/doanh số) thay hardcode; review thật có kiểm duyệt (bảng nhỏ) hoặc ẩn khối review mẫu | `index.vue:43–55`, admin Catalog | `products.is_best_seller`; bảng `reviews(order_id, rating, content, status)` | M | Giá đúng, uy tín thật | – (I-11) |
| P2-2 | Gắn GA4 + Meta Pixel với sự kiện `view_item`, `add_to_cart`, `begin_checkout`, `purchase` (giá trị từ server) | `app/plugins/analytics.client.ts` (mới) | Không | S–M | Đo được chuyển đổi/ROAS | Câu hỏi 7 |
| P2-3 | Thu lead sớm: nút Zalo/gọi cố định, bắt SĐT ở giỏ hàng trước khi sang thanh toán → `create_lead` để remarketing đơn bỏ dở | `gio-hang.vue`, `lien-he.vue` | `leads.source` (cart/contact) | S–M | Cứu đơn bỏ dở | – |
| P2-4 | Nâng coupon: giới hạn theo SĐT, mã tự điền theo link, mã cho khách quay lại | `validate_coupon`, `CatalogTab.vue` | `coupon_redemptions` | M | Tăng mua lại | P0-3 |
| P2-5 | Admin vận hành: cảnh báo tồn kho thấp, in phiếu đơn, xuất CSV đơn/khách theo bộ lọc | `admin.vue`, `ReportsTab.vue`, `CustomersTab.vue` | Không | M | Giảm thao tác tay | – |
| P2-6 | CI GitHub Actions: `npm test` + `npm run build` mỗi PR; đồng bộ test với SQL thật (xem mục 7) | `.github/workflows/ci.yml` (mới) | Không | S | Chặn lỗi trước khi lên | – (I-19) |
| P2-7 | Tự host font (hoặc `preload`) + tối ưu LCP | `nuxt.config.ts:29–31`, `public/fonts` | Không | S | LCP tốt hơn | – |

### P3 – Nâng cao (làm khi quy mô tăng)

| ID | Việc cần làm | Ghi chú phạm vi | Effort |
|---|---|---|---|
| P3-1 | Tích hợp API vận chuyển (GHN/GHTK): tạo vận đơn, webhook trạng thái | Chỉ cần khi gửi hàng tỉnh nhiều; hiện lắp tại nhà/nội thành thì chưa cần | L |
| P3-2 | Tài khoản khách (đăng nhập, lịch sử đơn, bảo hành) | Sau khi có tra cứu đơn (P1-3) | L |
| P3-3 | Tách `admin.vue`/`ctv.vue` thành component + composable; xoá dần `src/` & `prerender.cjs` (**cần bạn duyệt vì AGENTS.md cấm xoá**) | Làm khi ổn định, tránh làm sớm | L |
| P3-4 | Email/Zalo ZNS tự động (xác nhận đơn, nhắc lắp đặt) | Cần chi phí ZNS | M |
| P3-5 | Báo cáo nâng cao (LTV, tỉ lệ hủy theo CTV, cohort) | Dựa trên `admin_reports` hiện có | M |

> **Không đề xuất** (quá lớn so với quy mô): đa kho, đa tiền tệ, marketplace, app mobile native, hệ thống đề xuất AI.

---

## 6. Quick wins (< 1 ngày/việc)

| # | Việc | File | Nguồn |
|---|---|---|---|
| 1 | Sửa `notify-order` fail-closed + bỏ/escape Markdown | `supabase/functions/notify-order/index.ts:21–25,76` | I-01, I-20 |
| 2 | `robots.txt`: `Disallow: /admin /ctv /gio-hang /thanh-toan` | `public/robots.txt` | I-08 |
| 3 | Thêm `useSeoMeta({ robots: 'noindex' })` cho 4 trang riêng tư | `admin.vue`, `ctv.vue`, `gio-hang.vue`, `thanh-toan.vue` | I-08 |
| 4 | og/twitter mặc định (title, description, image 1200×630) trong `app.head` | `nuxt.config.ts` | I-07 |
| 5 | Sửa URL sitemap bỏ `.html` (hoặc thay bằng sitemap động ở P1-6) | `public/sitemap.xml` | I-07 |
| 6 | Header bảo mật cơ bản (không CSP) qua `routeRules` | `nuxt.config.ts` | I-15 |
| 7 | Trigger hoàn `used_count` coupon khi hủy (SQL ~20 dòng) | migration mới | I-03 |
| 8 | Lấy STK/ngân hàng từ `app_settings` thay vì hardcode | `thanh-toan.vue:327–329` | I-04 |
| 9 | Thêm `alt` cho ảnh `gioi-thieu.vue:41`; thêm `loading="lazy"` cho ảnh dưới màn hình ở `index.vue:158,184` | các file trên | UI/perf |
| 10 | Ghi chú hai file `007` vào `docs/HUONG-DAN-MIGRATION-VA-TEST.md` và thứ tự chạy | docs | I-10 |

---

## 7. Đề xuất thay đổi DB / API (chỉ mô tả)

| Mục | Đề xuất | Mục đích |
|---|---|---|
| `orders` | Thêm `shipping_fee bigint default 0`, `shipping_carrier text`, `tracking_code text`, `payment_ref text`, `paid_at timestamptz`, `client_fingerprint text` | Phí ship, vận đơn, đối soát, chống spam |
| `payment_events` (mới) | `id, provider, provider_ref, order_id, amount, raw jsonb, created_at`, `unique(provider, provider_ref)` | Webhook idempotent |
| `coupon_redemptions` (mới) | `order_id, coupon_code, phone, created_at` + trigger hoàn khi hủy | Giới hạn theo SĐT, hoàn lượt |
| `reviews` (mới, P2) | `order_id, rating, content, status` | Review thật, kiểm duyệt |
| `app_settings` (key mới) | `bank_*`, `shipping_base_fee`, `free_ship_threshold`, `order_expire_hours` | Cấu hình không hardcode |
| `products` | `is_best_seller bool`; RPC `get_catalog_prices` thêm `in_stock` | Trang chủ động, chặn hết hàng |
| RPC mới | `track_order(code, phone)`, `preview_order(items, coupon)`, `system_mark_paid(order_code, amount, ref)` (chỉ gọi từ service role), `expire_stale_orders()` | Tra cứu, báo giá, thanh toán, dọn kho |
| `create_order` | Thêm: tính `shipping_fee`, nhận token captcha (xác minh ở edge function/gateway), trả `order_code` + `payment_instruction` | Một nguồn sự thật cho tiền |
| Edge Function mới | `payment-webhook`, (tuỳ chọn) `verify-captcha` | Đối soát + chống bot |
| Migration | Chuẩn hoá tên: `007_p2_stock_sync` → số mới; tạo thêm `009+` cho các thay đổi trên | Thứ tự rõ ràng |

---

## 8. Test case cần có (ưu tiên tiền → hoa hồng → quyền)

**A. Tiền & thanh toán**
- [ ] `create_order` bỏ qua giá client gửi lên; tổng = Σ(giá DB × SL) − coupon + phí ship (khi có).
- [ ] Coupon: hết hạn, hết lượt, dưới `min_order`, vượt `max_discount`; **hủy đơn hoàn `used_count`** (mới).
- [ ] Ship: dưới/trên ngưỡng miễn phí; làm tròn; không âm.
- [ ] Webhook thanh toán: gọi 2 lần cùng `provider_ref` → chỉ ghi nhận 1 lần; số tiền lệch → không đánh `paid`; mã đơn sai → bỏ qua.
- [ ] `admin_set_payment_status` bắt buộc quyền + ghi audit.

**B. Hoa hồng**
- [ ] Hoa hồng tính trên số tiền **sau** giảm giá phân bổ (đã có `1.2` trong `commerce-rules.test.ts`).
- [ ] Hủy/hoàn đơn trước/sau khi `available/paid` → reversal/clawback đúng.
- [ ] Tự giới thiệu (cùng user/SĐT/email) → hoa hồng = 0.
- [ ] `admin_pay_commissions` chạy 2 lần cùng `idempotency key` → chỉ trả 1 lần; thuế TNCN theo `app_settings`.
- [ ] Payout request vượt số dư khả dụng → từ chối.

**C. Tồn kho**
- [ ] Hai đơn đồng thời cho 1 sản phẩm còn 1 → chỉ 1 thành công (`for update` ở trigger).
- [ ] Hủy → hoàn kho 1 lần (`stock_restored`); hủy lần 2 không cộng thêm.
- [ ] `stock_qty IS NULL` = không giới hạn.

**D. Phân quyền / RLS**
- [ ] `anon` **không** `select` được `orders`, `leads`, `affiliates`, `commission_*`.
- [ ] CTV A không thấy đơn/lead/ledger của CTV B; PII đã che (`ctv_list_orders`).
- [ ] `staff` không gọi được `admin_pay_commissions`, `develop_set_account_role`, `admin_update_setting`.
- [ ] Người đăng ký CTV không tự đặt được `role='admin'`, `commission_rate`, `status='active'`.
- [ ] `notify-order` trả 401 khi thiếu/sai secret (kể cả khi chưa đặt biến môi trường).

**E. Chống lạm dụng**
- [ ] Đổi SĐT liên tục từ cùng IP/fingerprint bị chặn; đơn `new` quá hạn tự hủy và hoàn kho.

> Gợi ý kỹ thuật: ngoài `tests/commerce-rules.test.ts` (mô phỏng TS), cần **chạy `verify-business-rules.sql` trong CI** trên một Supabase/Postgres tạm để test phản ánh RPC thật.

---

## 9. Câu hỏi cần bạn xác nhận

| # | Câu hỏi | Ảnh hưởng tới |
|---|---|---|
| 1 | **Ngân sách/nhân lực**: làm một mình hay có thêm dev? Có ngân sách cho dịch vụ trả phí (captcha Pro, cổng thanh toán, ZNS)? | Toàn bộ lộ trình |
| 2 | **Thanh toán**: dùng chuyển khoản VietQR + dịch vụ đối soát (SePay/payOS/Casso) hay cổng thẻ (VNPay/MoMo)? Tài khoản nhận tiền là công ty hay cá nhân? | P1-1 |
| 3 | **Chống bot**: chấp nhận Cloudflare Turnstile (miễn phí) không? | P0-2 |
| 4 | **Vận chuyển/lắp đặt**: giao toàn quốc hay chủ yếu lắp tại nhà nội thành? Phí ship tính phẳng, theo vùng, hay miễn phí trên X đồng? Có dùng GHN/GHTK không? | P1-2, P3-1 |
| 5 | **Ưu tiên kinh doanh**: ưu tiên tăng đơn (SEO/quảng cáo) hay giảm vận hành tay (đối soát/ship)? | Thứ tự P1 |
| 6 | **Luật coupon**: 1 lần/SĐT? có cộng dồn với hoa hồng CTV? hoàn lượt khi hủy? | P0-3, P2-4 |
| 7 | **Marketing**: đã có GA4/Meta Pixel/Zalo OA? Có chạy quảng cáo Facebook/Google? | P2-2 |
| 8 | **Migration**: đồng ý đổi tên `007_p2_stock_sync` thành số mới? DB thật đã chạy file nào rồi? | P0-4 |
| 9 | **Hạ tầng**: đang deploy trên Vercel hay nền tảng khác? Có plan Supabase Pro (backup/PITR)? | P1-7, vận hành |
| 10 | **Code cũ** (`src/`, `prerender.cjs`): có cho phép lưu trữ/ngưng dùng không (hiện `AGENTS.md` cấm xoá)? | P3-3 |
| 11 | **Review/testimonial**: có ảnh & phản hồi khách thật để thay khối mẫu ở `index.vue:50–55` không? | P2-1 |

---

**Bạn muốn bắt đầu code từ giai đoạn nào (P0, P1, P2 hay P3) hoặc từ nhóm Quick wins?** Tôi sẽ chờ lệnh trước khi chỉnh bất kỳ file code nào.
