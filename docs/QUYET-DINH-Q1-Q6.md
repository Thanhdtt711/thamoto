# QUYẾT ĐỊNH CHỐT Q1–Q6 – Hệ thống Admin & CTV

> Trả lời các câu hỏi Q1–Q6 ở mục 7 của [`KE-HOACH-CAI-TIEN-ADMIN-CTV.md`](KE-HOACH-CAI-TIEN-ADMIN-CTV.md).
> Đây là **quyết định mặc định đã chốt** để triển khai. Mọi giá trị số (tỷ lệ, số ngày, hạn mức) phải lưu trong bảng cấu hình `app_settings` (admin sửa được), **không hard-code** trong code hay SQL.
> Mục nào ghi "cần xác nhận" là phần phụ thuộc chính sách thực tế/pháp lý của shop, đã thiết kế sẵn để đổi mà không phải sửa code.

---

## Q1. Hoa hồng tính trên giá trị nào?

**Chốt:** tính trên **giá trị hàng hóa thực thu, sau giảm giá**, **không** gồm phí ship, phí lắp đặt, phí thu hộ.

| Hạng mục | Quy tắc |
|---|---|
| Cơ sở tính | `base = Σ (đơn giá × số lượng của từng dòng hàng) − phần mã giảm giá phân bổ cho dòng đó` |
| Phân bổ giảm giá | Mã giảm giá cấp đơn được **phân bổ theo tỷ lệ giá trị từng dòng**; dòng nào không đủ điều kiện hưởng hoa hồng thì loại khỏi `base` |
| Mức hoa hồng | Tính **theo từng dòng hàng** (order item). Thứ tự ưu tiên tỷ lệ: **(1) tỷ lệ riêng theo sản phẩm → (2) tỷ lệ riêng theo CTV → (3) tỷ lệ mặc định** trong `app_settings` |
| Làm tròn | Làm tròn **xuống** tới 1 đồng (số nguyên VND), cộng các dòng ra tổng hoa hồng đơn |
| Chốt tỷ lệ | **Snapshot** tỷ lệ và số tiền vào dòng hàng + sổ cái ngay khi tạo đơn. Đổi tỷ lệ sau này **không** ảnh hưởng đơn cũ |
| Tính ở đâu | **Duy nhất trong DB** (hàm/RPC tạo đơn). Client không gửi và không quyết định `commission_*` |
| Đơn tự đặt | Không tính hoa hồng (xem Q4) |

**Lý do:** tính trên giá sau giảm giá tránh shop trả hoa hồng cho phần tiền không thu được. Loại ship/lắp đặt vì không phải doanh thu hàng hóa và thường là chi phí hộ. Theo dòng hàng cho phép đặt tỷ lệ khác nhau theo sản phẩm sau này mà không đổi cấu trúc.

---

## Q2. Điều kiện để hoa hồng được phép chi

**Chốt:** hoa hồng chỉ được chi khi **đơn đã hoàn thành + hết thời gian giữ (hold) 7 ngày**. Giá trị hold cấu hình bằng `commission_hold_days`, mặc định `7`.

Vòng đời trạng thái hoa hồng (ghi trong sổ cái, không sửa đè):

```
pending ──(đơn completed)──► holding ──(hết hold_days)──► available ──(vào kỳ chi)──► paid
   │                            │                              │
   └────────── đơn hủy/hoàn ────┴──────────────────────────────┴──► reversed
```

| Trạng thái | Ý nghĩa | CTV thấy | Rút được |
|---|---|---|---|
| `pending` | Đơn mới, chưa hoàn thành | Có (ước tính) | Không |
| `holding` | Đơn hoàn thành, đang trong thời gian giữ | Có (kèm ngày dự kiến mở) | Không |
| `available` | Đủ điều kiện | Có | **Có** |
| `paid` | Đã chi | Có | Không |
| `reversed` | Bị thu hồi do hủy/hoàn | Có (kèm lý do) | Không |

- Chuyển `holding → available` do **job định kỳ** (pg_cron hoặc Edge Function chạy mỗi ngày), không dựa vào thao tác tay.
- Mốc tính hold = thời điểm đơn chuyển `completed` (đã giao thành công), lưu ở cột riêng, không dùng `created_at`.
- **Cần xác nhận:** nếu chính sách đổi trả của shop dài hơn 7 ngày thì chỉnh `commission_hold_days` bằng chính thời hạn đổi trả. Không cần sửa code.

**Lý do:** ngăn chi tiền rồi mới bị khách trả hàng, giảm phải truy thu (clawback) ở Q3.

---

## Q3. Đơn hoàn sau khi đã chi hoa hồng

**Chốt:** **thu hồi bằng bút toán âm (clawback) trừ vào kỳ chi tiếp theo.** Không bắt CTV chuyển tiền trả lại.

| Tình huống | Xử lý |
|---|---|
| Hủy/hoàn **trước** khi chi (`pending/holding/available`) | Ghi bút toán `reversal` triệt tiêu dòng hoa hồng. Số dư giảm tương ứng |
| Hoàn **sau** khi đã chi (`paid`) | Ghi bút toán `clawback` **âm** cùng số tiền. Số dư khả dụng của CTV bị giảm; **có thể âm** |
| Số dư âm | Kỳ sau tự bù trừ bằng hoa hồng mới. **Không** cho rút khi số dư khả dụng < hạn mức tối thiểu |
| CTV ngừng hoạt động mà còn số dư âm | Admin xử lý thủ công, ghi chú trong audit log. **Không** tự động đòi tiền |
| Hoàn một phần | Thu hồi **theo tỷ lệ** dòng hàng bị hoàn (tính lại bằng đúng tỷ lệ đã snapshot) |

Nguyên tắc sổ cái (bắt buộc):
- Sổ cái `commission_ledger` là **append-only**: không UPDATE, không DELETE (chặn bằng trigger + RLS). Sai sót sửa bằng **bút toán điều chỉnh** mới, kèm lý do và người thực hiện.
- Số dư = tổng các bút toán của CTV. Mọi con số hiển thị lấy từ sổ cái.
- Clawback gắn khóa tham chiếu tới dòng hoa hồng gốc, **idempotent** (một lần hoàn chỉ sinh một bút toán).

**Lý do:** pháp lý/vận hành đơn giản, không phát sinh tranh chấp đòi tiền, và sổ cái luôn khớp tuyệt đối.

---

## Q4. Quy tắc ghi nhận nguồn đơn (attribution)

**Chốt:** **Last-click, TTL 30 ngày**, cho phép khách nhập tay mã CTV ở bước thanh toán nhưng mã **phải hợp lệ**.

| Hạng mục | Quy tắc |
|---|---|
| Mô hình | **Last-click**: nguồn gần nhất còn hạn trong 30 ngày được tính |
| TTL | `attribution_ttl_days = 30` (cấu hình) |
| Lưu phía client | Cookie **và** localStorage (một nơi mất thì còn nơi kia). Chỉ lưu **mã đã chuẩn hóa**, không lưu dữ liệu nhạy cảm |
| Nhập tay mã | Được phép. **Mã nhập tay thắng** mã từ link/cookie vì là ý định rõ ràng của khách. Ghi `ref_source = manual` |
| Mã không hợp lệ/CTV bị khóa/chưa duyệt | **Không ghi nhận** hoa hồng; vẫn cho đặt đơn bình thường; báo khách "mã không hợp lệ" |
| Khóa nguồn | Chốt `affiliate_id` + `ref_source` + `attributed_at` **lúc tạo đơn** trong RPC. Sau đó chỉ **admin** đổi được, bắt buộc có lý do và ghi audit log |
| Tự giới thiệu | CTV đặt đơn bằng mã của mình (khớp `user_id`, SĐT hoặc email với hồ sơ CTV): **vẫn nhận đơn nhưng hoa hồng = 0**, đánh dấu `self_referral = true` (đồng thời trả lời Q13) |
| Chống gian lận cơ bản | Giới hạn tần suất ghi click theo IP/thiết bị; trùng click trong cửa sổ ngắn chỉ tính 1; cờ cảnh báo khi một CTV có nhiều đơn từ cùng SĐT/địa chỉ |
| Giá trị `ref_source` | `link`, `manual`, `admin_override` |

**Lý do:** last-click là cách phổ biến, dễ giải thích cho CTV. Cho nhập tay giúp CTV bán qua điện thoại/Zalo mà khách không bấm link. Khóa nguồn tại RPC chặn việc client tự gắn mã sau khi đặt.

---

## Q5. Rút tiền và chi trả

**Chốt:**

| Hạng mục | Giá trị (cấu hình được) |
|---|---|
| Hạn mức tối thiểu | `min_payout_amount = 200000` đ |
| Chu kỳ chi | **Hàng tuần**. CTV gửi yêu cầu bất kỳ lúc nào khi số dư `available` ≥ hạn mức; admin chi **gộp theo lô vào một ngày cố định mỗi tuần** (mặc định thứ Hai, cấu hình `payout_weekday = 1`). Yêu cầu gửi sau giờ chốt vào lô tuần sau |
| Một yêu cầu đang mở | Mỗi CTV chỉ có **1 yêu cầu `requested`** tại một thời điểm |
| Số tiền yêu cầu | Tối đa bằng số dư `available`, giữ chỗ (lock) ngay khi gửi để không rút trùng |
| Tài khoản nhận | CTV nhập ngân hàng/STK/tên chủ TK trong hồ sơ. **Mọi thay đổi ngân hàng phải được admin xác minh** trước khi dùng để chi (T41). Tên chủ TK phải khớp tên đăng ký |
| Phí chuyển khoản | **Shop chịu**, CTV nhận đủ số tiền sau thuế |
| Quy trình trạng thái | `requested → approved → paid` hoặc `rejected` (kèm lý do). `paid` bắt buộc có mã giao dịch/chứng từ, **bất biến** sau khi ghi |
| Atomic/idempotent | Duyệt và chi chạy trong **một transaction RPC**, có khóa idempotency; bấm 2 lần không chi 2 lần |
| Audit | Mọi bước ghi `audit_log` (ai, lúc nào, giá trị trước/sau) |

**Thuế thu nhập cá nhân (cần xác nhận với kế toán):**
- Thu nhập hoa hồng của cá nhân không có hợp đồng lao động thường thuộc diện **khấu trừ thuế TNCN tại nguồn** khi tổng mỗi lần chi vượt ngưỡng theo quy định hiện hành (trước đây là 10% với mỗi lần chi từ 2.000.000 đ; có thể có điều chỉnh mới, shop cần kế toán chốt).
- Vì chưa chắc quy định áp dụng, hệ thống thiết kế sẵn: `tax_withholding_rate` (mặc định `0`) và `tax_threshold_per_payment` (mặc định `0`) trong `app_settings`. Bản ghi payout lưu đủ `gross_amount`, `tax_amount`, `net_amount`.
- Nếu cần thu thập cam kết/MST của CTV, thêm trường `tax_code`, `id_number` (mã hóa/hạn chế đọc) ở hồ sơ CTV ở giai đoạn sau.
- **Antigravity không tự bật khấu trừ thuế.** Chỉ dựng sẵn cấu trúc và hiển thị dòng "Thuế khấu trừ" khi giá trị > 0.

**Lý do:** hạn mức và chu kỳ gộp giảm chi phí chuyển khoản và công đối soát. Shop chịu phí để chính sách rõ ràng, CTV dễ chấp nhận.

---

## Q6. Kiến trúc backend

**Chốt:** **Giữ Supabase thuần: Postgres RPC (`security definer`) + RLS.** Dùng **Supabase Edge Function** chỉ cho việc cần ra ngoài hoặc cần khóa bí mật. **Không** dựng thêm backend Node/`server/api`.

| Việc | Nơi xử lý |
|---|---|
| Tạo đơn, tính giá/mã giảm giá/hoa hồng, duyệt/hoàn/chi hoa hồng, đổi vai trò, ghi click | **RPC trong Postgres** (một transaction, kiểm tra quyền bằng `auth.uid()` và vai trò) |
| Giới hạn cột được sửa, che PII, KPI/báo cáo | **View/RPC** chỉ trả cột cho phép. Bỏ `select('*')` |
| Quyền truy cập dữ liệu | **RLS** thu hẹp: anon **không** ghi trực tiếp vào `orders`, `commission_*`, `affiliates` |
| Gửi email/Telegram, webhook ngân hàng sau này, job nền | **Edge Function** (giữ khóa bí mật trong secret của Supabase, không đưa vào client) |
| Job định kỳ (chuyển `holding → available`) | `pg_cron` hoặc Edge Function có lịch |
| `service_role` key | **Chỉ** ở secret của Edge Function. Tuyệt đối không có trong repo, `.env.example` chỉ ghi tên biến |

**Lý do:** dự án hiện không có backend và có script `generate` trong [`package.json`](../package.json), nên nhiều khả năng đang phát hành dạng tĩnh. Thêm server Node kéo theo hosting, vận hành và bề mặt tấn công mới. RPC + RLS đủ để chuyển toàn bộ logic nhạy cảm ra khỏi client, đúng mục tiêu P0.

**Ranh giới cần giữ:** mọi RPC phải `set search_path = public`, kiểm tra quyền ở đầu hàm, và `revoke execute ... from public/anon` rồi chỉ `grant` cho vai trò cần. Riêng RPC tạo đơn cho khách chưa đăng nhập thì grant cho `anon` nhưng chỉ nhận dữ liệu thô (sản phẩm, số lượng, thông tin giao hàng, mã giới thiệu) và tự tính mọi con số.

---

## Bảng tóm tắt cấu hình (`app_settings`)

| Khóa | Mặc định | Liên quan |
|---|---|---|
| `default_commission_rate` | Giữ theo tỷ lệ đang dùng trong [`supabase/schema.sql`](../supabase/schema.sql) | Q1 |
| `commission_hold_days` | `7` | Q2 |
| `attribution_ttl_days` | `30` | Q4 |
| `min_payout_amount` | `200000` | Q5 |
| `payout_weekday` | `1` (thứ Hai) | Q5 |
| `tax_withholding_rate` | `0` | Q5 |
| `tax_threshold_per_payment` | `0` | Q5 |

## Ghi chú cho người triển khai

- Q7–Q14 chưa chốt ở file này. Dùng giả định mặc định ở mục 8 của kế hoạch, và ghi rõ trong báo cáo.
- Dữ liệu cũ phải được **backfill** vào sổ cái trong migration, giữ nguyên số tiền đã tính/chi trước đây, không tính lại bằng quy tắc mới.
