# PROMPT GIAO VIỆC CHO ANTIGRAVITY – Nâng cấp Admin & CTV (Affiliate)

> Cách dùng: copy toàn bộ phần nằm giữa hai dòng `=== BẮT ĐẦU PROMPT ===` và `=== KẾT THÚC PROMPT ===` rồi dán cho Antigravity. Workspace phải là `d:\thamoto`.

=== BẮT ĐẦU PROMPT ===

## VAI TRÒ

Bạn là Senior Full-stack Engineer (Nuxt 4 / Vue 3 / Supabase / PostgreSQL). Nhiệm vụ: **triển khai toàn bộ kế hoạch cải tiến hệ thống Admin và Cộng tác viên (CTV)** của dự án `d:\thamoto` (website bán thảm lót sàn ô tô, nội dung 100% tiếng Việt).

## BƯỚC 0 – ĐỌC TRƯỚC KHI LÀM (bắt buộc)

Đọc theo thứ tự, không bỏ qua:

1. `AGENTS.md` – quy tắc nền của project (design system, quy tắc code, những điều KHÔNG làm).
2. `docs/KE-HOACH-CAI-TIEN-ADMIN-CTV.md` – **kế hoạch chính, nguồn sự thật duy nhất** cho việc phải làm. Gồm: checklist C1–C14 và A1–A22, lỗi V01–V20, các giai đoạn P0–P3, đề xuất DB/API (mục 5), test case T01–T43 (mục 6), câu hỏi mở Q1–Q14 (mục 7), giả định (mục 8), thứ tự khuyến nghị (mục 9).
3. `docs/QUYET-DINH-Q1-Q6.md` – **quyết định đã chốt** cho Q1–Q6 (cách tính hoa hồng, thời gian giữ, clawback, attribution, rút tiền, kiến trúc). Nếu mâu thuẫn với mục 7 của kế hoạch thì **theo file này**. Mọi con số phải đọc từ bảng `app_settings`, không hard-code.
4. Code hiện tại liên quan:
   - `supabase/schema.sql` (schema, RLS, trigger `calc_order_commission`)
   - `app/pages/admin.vue`, `app/pages/ctv.vue`, `app/pages/cong-tac-vien.vue`
   - `app/pages/thanh-toan.vue`, `app/pages/gio-hang.vue`, `app/pages/lien-he.vue`
   - `app/composables/useAffiliate.ts`, `useCart.ts`, `useSupabase.ts`, `useToast.ts`
   - `shared/utils/vehicles.ts`, `nuxt.config.ts`, `package.json`, `.env.example`, `docs/order-integration.md`

Xác nhận lại các dòng/line trong kế hoạch còn đúng với code hiện tại trước khi sửa (code có thể đã đổi).

## BỐI CẢNH KỸ THUẬT

- Nuxt 4 + Vue 3 + Tailwind. **Không có backend** (`server/` đang rỗng): trình duyệt gọi Supabase trực tiếp bằng anon key, toàn bộ bảo mật dựa vào RLS.
- Thư mục `src/` là code Vite legacy. **Không sửa, không xóa** `src/`. Chỉ làm trong `app/`, `shared/`, `server/` (nếu cần), `supabase/`, `docs/`.
- `AGENTS.md` mô tả stack Vite, nhưng code thực tế đã chuyển sang Nuxt trong `app/`. Với phần Admin/CTV, **theo code Nuxt hiện tại**; vẫn giữ nguyên design system (màu, typography, bo góc, responsive, tiếng Việt, tiền tệ dạng `1.500.000 đ`).

## RÀNG BUỘC CỨNG (vi phạm = làm lại)

1. **Không đổi tên, không xóa, không di chuyển** file/route/component đang có. Chỉ thêm file mới khi thật sự cần, đúng thư mục.
2. **Không chạy lệnh phá hoại** (xóa thư mục, `git reset --hard`, `DROP TABLE`/`TRUNCATE`/`DELETE` không điều kiện trên dữ liệu thật, ghi đè `node_modules`...). Cần thì hỏi.
3. **Không commit secret.** Không đưa `service_role`/`sb_secret` vào code client hoặc file được commit. Chỉ dùng qua biến môi trường server-side, và cập nhật `.env.example` (chỉ tên biến, không giá trị thật).
4. **Không sửa nội dung chữ tiếng Việt hiện có** của giao diện, trừ chỗ kế hoạch yêu cầu. Chữ mới phải là tiếng Việt.
5. **Không xóa chức năng đang chạy** để làm cho gọn.
6. **Không cài thư viện nặng** hoặc đổi bundler/stack. Cần thêm gì nhỏ thì nêu lý do.
7. Mọi thay đổi DB phải là **migration SQL mới, idempotent, có phần rollback ghi chú**, đặt trong `supabase/migrations/` (đặt tên theo thời gian, ví dụ `20261125_001_xxx.sql`). Cập nhật `supabase/schema.sql` để phản ánh trạng thái cuối. Bạn **không có quyền truy cập Supabase thật**, nên chỉ viết file SQL, không giả định đã chạy; ghi rõ hướng dẫn chạy trong `docs/`.
8. Giao diện: HTML ngữ nghĩa, `aria-label` cho nút icon, `:focus-visible` rõ, nút mobile tối thiểu 44×44px, **không tràn ngang ở 390px**, đúng breakpoint 768/1024/1280.
9. Không để `console.log` thừa. Logic giá/hoa hồng tính **ở một nơi duy nhất (phía DB/RPC)**, client chỉ hiển thị.
10. Gặp điểm mơ hồ ảnh hưởng lớn (dữ liệu, URL, logic tiền) mà kế hoạch chưa trả lời: **dùng giả định mặc định ở mục 8 của kế hoạch, ghi rõ vào báo cáo**. Chỉ dừng hỏi khi giả định đó có thể gây mất dữ liệu hoặc sai tiền không đảo ngược được.

## NHIỆM VỤ

Thực hiện **toàn bộ** các hạng mục P0 → P1 → P2 → P3 trong mục 4 của `docs/KE-HOACH-CAI-TIEN-ADMIN-CTV.md`, theo thứ tự ở mục 9. Thứ tự P0 khuyến nghị:

`P0-8 → (P0-2 ‖ P0-7) → P0-1 → P0-3 → P0-4 → P0-5 → P0-6`

Mục tiêu then chốt cần đạt (đối chiếu với V01–V06 🔴):

| Lỗi | Kết quả phải đạt |
|---|---|
| V01 | Đặt đơn không còn `with check (true)` tự do. Server/DB tự tính giá, tổng tiền, mã giảm giá; ép `status`, `commission_status` về giá trị khởi tạo; client không quyết định được hoa hồng. |
| V02 | Admin không thể tự sửa `role` hay cột nhạy cảm tùy ý (giới hạn cột/RPC). Không còn đường leo thang quyền. |
| V03 | CTV không đọc được PII khách hàng. Che số điện thoại/địa chỉ **ở cấp DB** (view/RPC chỉ trả cột cho phép), không chỉ ở UI. |
| V04 | Có sổ cái hoa hồng (commission ledger). Hủy/hoàn đơn tự động thu hồi (reversal) hoa hồng. |
| V05 | Chi trả hoa hồng atomic, idempotent, bản ghi payout bất biến (immutable); có audit log. |
| V06 | Phân trang/lọc phía server; KPI tính bằng SQL/RPC, bỏ giới hạn 300/200 đơn. |

Sau đó hoàn thành các lỗi 🟡 (V07–V16), 🟢 (V17–V20) và các mục ❌/⚠️ còn lại trong checklist C1–C14, A1–A22 (hồ sơ/ngân hàng/đổi mật khẩu CTV, theo dõi click, yêu cầu rút tiền, xuất CSV, audit log, tỷ lệ theo CTV/sản phẩm, duyệt/khóa CTV, quản lý sản phẩm/kho/mã giảm giá/khách hàng, dashboard, phân quyền...) đúng phạm vi mà kế hoạch mô tả.

## QUY TRÌNH LÀM VIỆC

1. **Lập Task List** từ kế hoạch (mỗi hạng mục P*-* là một task, ghi file sẽ sửa, DB đổi gì, ước lượng S/M/L, phụ thuộc). Lưu vào `docs/TIEN-DO-ADMIN-CTV.md` và cập nhật liên tục.
2. Làm **theo giai đoạn** P0 → P1 → P2 → P3. Hết mỗi giai đoạn phải:
   - Chạy `npm run build` (và `npm run dev` kiểm tra), sửa lỗi nếu có.
   - Chụp screenshot **390px, 768px, 1440px** cho các trang Admin/CTV bị ảnh hưởng, tự sửa lỗi layout rồi mới sang giai đoạn sau.
   - Đối chiếu test case T01–T43 liên quan: ghi rõ test nào đã tự kiểm được, test nào cần chạy trên Supabase thật (kèm câu lệnh/SQL để người dùng chạy).
   - Cập nhật `docs/TIEN-DO-ADMIN-CTV.md`.
3. **Không sang giai đoạn mới khi giai đoạn trước còn lỗi build hoặc lỗi layout.**
4. Nhớ tương thích ngược: dữ liệu `orders`/`affiliates`/`commission_payouts` hiện có phải được **backfill** trong migration (ví dụ tạo ledger từ hoa hồng cũ), không làm mất dữ liệu.
5. Mỗi migration: ghi chú rõ thứ tự chạy, điều kiện tiên quyết, cách rollback.

## TIÊU CHÍ HOÀN THÀNH (Definition of Done)

- [ ] Toàn bộ V01–V20 đã xử lý hoặc có ghi chú lý do hoãn trong `docs/TIEN-DO-ADMIN-CTV.md`.
- [ ] Không còn policy ghi tự do cho anon trên bảng nhạy cảm; không client nào tự tính hoặc tự ghi hoa hồng/giá.
- [ ] CTV chỉ thấy dữ liệu của chính mình và đã che PII ở DB.
- [ ] Mọi thao tác tiền (duyệt, hoàn, chi trả) đều có audit log và không sửa/xóa được sau khi ghi.
- [ ] `npm run build` không lỗi; không link/asset 404; không `console.log` thừa.
- [ ] Không tràn ngang ở 390px; nút mobile ≥ 44px; điều hướng bàn phím dùng được.
- [ ] Có migration SQL + hướng dẫn chạy + SQL kiểm thử cho T01–T43 phần cần Supabase thật.
- [ ] Không có file nào bị đổi tên/xóa/di chuyển; `src/` còn nguyên.

## CÁCH BÁO CÁO

Cuối mỗi giai đoạn, báo cáo ngắn bằng tiếng Việt:
- Đã làm gì (theo mã P*-*, V**).
- File thay đổi / file mới (kể cả migration).
- Điều còn dở và rủi ro.
- Giả định đã đặt ra (nêu số Q tương ứng).
- Việc người dùng cần tự làm (chạy migration, cấu hình biến môi trường, quyết định).

Cuối cùng: tổng kết toàn bộ + bảng đối chiếu V01–V20 và C1–C14, A1–A22 (✅/⚠️/❌ sau khi làm) + Walkthrough kèm screenshot 3 breakpoint cho từng trang Admin/CTV.

=== KẾT THÚC PROMPT ===

## Lưu ý cho người giao việc

- Các câu hỏi mở Q1–Q14 (mục 7 của kế hoạch) nên được bạn trả lời trước khi chạy, đặc biệt: Q1–Q6 (quy tắc hoa hồng, thời điểm chốt, chính sách hoàn đơn), Q10 (RPC `security definer` hay Edge Function), Q11 (xử lý mã legacy `src/` do `AGENTS.md` cấm xóa file). Nếu chưa trả lời, Antigravity sẽ dùng giả định mặc định ở mục 8.
- Antigravity không truy cập được Supabase thật của bạn: bạn cần tự chạy các file trong `supabase/migrations/` theo hướng dẫn nó viết, nên sao lưu DB trước.
- Nên cho chạy từng giai đoạn (P0 xong rồi duyệt) thay vì một lèo, vì P0 đụng đến tiền và quyền.
