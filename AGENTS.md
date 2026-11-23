# AGENTS.md – Project Thảm Lót Sàn Ô Tô (`d:\thamoto`)

File này là quy tắc nền cho mọi agent làm việc trong project. Đọc kỹ trước khi sửa bất cứ thứ gì.

---

## 1. Tổng quan project

- Website bán thảm lót sàn ô tô, nội dung **100% tiếng Việt**.
- Stack: **Vite + HTML/CSS/JS thuần**, multi-page, dùng partials. Không dùng framework (React/Vue...) trừ khi tôi yêu cầu.
- Luồng người dùng chính:
  `Trang chủ (lọc YMM / chọn hãng) → Dòng xe (san-pham.html) → Chọn đời xe/chất liệu/màu (chi-tiet.html) → Giỏ hàng → Thanh toán`
- Mục tiêu hiện tại: redesign toàn bộ UI/UX theo wireframe, responsive đầy đủ **Mobile và Desktop**.

## 2. Cấu trúc thư mục (giữ nguyên)

```
src/
  index.html, san-pham.html, chi-tiet.html, gio-hang.html, thanh-toan.html,
  gioi-thieu.html, tin-tuc.html, chi-tiet-tin-tuc.html, lien-he.html
  partials/        header.html, mobile-nav.html, cart-drawer.html, footer.html
  assets/
    css/index.css
    js/            main.js, selector.js, cart.js
    images/
scripts/prerender.cjs
```

Quy tắc cấu trúc:
- **Không đổi tên, không xóa, không di chuyển** file/route/partial hiện có.
- Chỉ thêm file mới khi thật sự cần, và đặt đúng thư mục theo loại.
- Dữ liệu xe/giá: dùng nguồn dữ liệu hiện có trong project. Nếu thiếu, bổ sung mock cùng nơi đang chứa dữ liệu, không tạo nguồn thứ hai.

## 3. Quy trình làm việc (bắt buộc)

1. **Khám phá trước**: đọc cấu trúc project, `index.css`, 3 file JS, `prerender.cjs`, các partials. Ghi lại chức năng đang chạy tốt.
2. **Lập Implementation Plan + Task List, rồi DỪNG chờ tôi duyệt.** Không code khi chưa được duyệt.
3. Làm theo giai đoạn, xong giai đoạn nào kiểm tra giai đoạn đó:
   - GĐ1: Design tokens, CSS nền, header/mobile-nav/cart-drawer/footer.
   - GĐ2: Trang chủ (hero, YMM filter, hãng xe, bán chạy, khách hàng thực tế).
   - GĐ3: `san-pham.html` (tìm nhanh, nhóm phân khúc, card dòng xe).
   - GĐ4: `chi-tiet.html` (bước 1, bước 2, ưu đãi, giá động, thêm vào giỏ).
   - GĐ5: Giỏ hàng, thanh toán và các trang phụ.
4. Sau mỗi giai đoạn: chạy dev server, mở browser, chụp screenshot ở **390px, 768px, 1440px**, tự sửa lỗi layout rồi mới sang giai đoạn tiếp.
5. Cuối cùng chạy `npm run build`, sửa lỗi nếu có, rồi tạo Walkthrough kèm screenshot 3 breakpoint cho từng trang.

Nếu gặp điểm mơ hồ có thể ảnh hưởng lớn (dữ liệu, URL, logic giá), hỏi tôi thay vì tự đoán.

## 4. Design System

**Màu** (khai báo thành CSS variables trong `:root`, không hard-code rải rác):

| Token | Giá trị | Dùng cho |
|---|---|---|
| `--navy` | `#0D2C54` | Header, hero, tiêu đề, border active của bước chọn |
| `--navy-2` | `#133A6E` | Hover/gradient của navy |
| `--red` | `#C81E2B` | CTA chính, thẻ dòng xe đang chọn, viền tròn hãng đang chọn |
| `--surface` | `#FFFFFF` | Card, nền sáng |
| `--bg` | `#F4F6F9` | Nền trang |
| `--star` | `#F59E0B` | Sao đánh giá |

- Không dùng màu ngoài bảng trên, trừ trạng thái lỗi/thành công khi thật sự cần.
- **Typography**: sans-serif hiện đại hỗ trợ tiếng Việt tốt (ưu tiên Be Vietnam Pro hoặc Inter, có fallback). Tiêu đề section in hoa, `font-weight: 700–800`. Giá tiền và năm dùng `font-variant-numeric: tabular-nums`.
- **Hình khối**: card bo `12px`, nút bo `8–10px`, shadow nhẹ, spacing theo bội số của 8px.
- **Trạng thái**: card đang chọn có viền + dấu check; hover có shadow nhẹ; `:focus-visible` luôn có outline rõ.
- Tiền tệ hiển thị dạng `1.500.000 đ`.

## 5. Responsive

- **Mobile-first**. Breakpoint: `768px` (tablet), `1024px` (desktop), `1280px` (desktop rộng).
- Container desktop tối đa `1200–1280px`, căn giữa.
- Mobile: 1 cột, lưới xe 2 cột, YMM xếp dọc, carousel dạng cuộn ngang, thanh tổng tiền + `ĐẶT MUA NGAY` **sticky đáy màn hình** ở `chi-tiet.html`.
- Desktop: header 1 hàng có menu ngang; hero 2 cột; trang dòng xe có sidebar trái + lưới 3–4 cột + breadcrumb; trang chi tiết 2 cột (gallery sticky trái, cấu hình phải).
- Không được có cuộn ngang ở 390px. Nút bấm trên mobile tối thiểu **44×44px**.

## 6. Quy tắc code

- HTML ngữ nghĩa (`header`, `nav`, `main`, `section`, `footer`), có `alt` cho ảnh, `aria-label` cho nút chỉ có icon.
- CSS: tập trung trong `src/assets/css/index.css`, đặt tên class nhất quán (BEM hoặc quy ước đang dùng, không trộn nhiều kiểu). Không dùng `!important` trừ khi bắt buộc.
- JS: vanilla ES modules, không thêm thư viện nặng. Không để `console.log` thừa. Tách hàm nhỏ, đặt tên rõ nghĩa.
- Logic giá: tính ở một nơi duy nhất, công thức = giá gốc theo (đời xe + chất liệu) + phụ phí ưu đãi (+150k thảm rối, +300k thảm lót cốp). Cập nhật realtime, lưu đủ thuộc tính cấu hình vào giỏ (`cart.js`).
- YMM filter: 3 dropdown phụ thuộc nhau (Hãng → Dòng → Năm); nút `TÌM KIẾM NGAY` chỉ bật khi chọn đủ; điều hướng đúng URL, ví dụ `san-pham.html?hang=toyota`, `chi-tiet.html?xe=fortuner`.
- Giữ nguyên prerender: mọi thay đổi không được làm hỏng `scripts/prerender.cjs`.

## 7. Ảnh và asset

- Chỉ dùng ảnh trong `src/assets/images/`. **Không hotlink ảnh từ web.**
- Chưa có ảnh thật thì dùng placeholder chất lượng cao, đặt đúng đường dẫn để tôi dễ thay sau.
- Ảnh có `loading="lazy"` (trừ ảnh hero), có `width/height` để tránh nhảy layout.

## 8. Những điều KHÔNG làm

- Không đổi tên/xóa file, route, partial đang có.
- Không cài thêm thư viện nặng hoặc đổi bundler/stack.
- Không sửa nội dung chữ tiếng Việt của wireframe (tiêu đề, nhãn nút, tên bước) trừ khi tôi yêu cầu.
- Không sang giai đoạn mới khi screenshot giai đoạn trước còn lỗi layout.
- Không xóa chức năng đang chạy để "làm cho gọn".
- Không chạy lệnh phá hoại (xóa thư mục, `git reset --hard`, ghi đè `node_modules`...) khi chưa hỏi.

## 9. Tiêu chí hoàn thành (Definition of Done)

- [ ] Không tràn ngang ở 390px; nút mobile ≥ 44px.
- [ ] Luồng Trang chủ → Dòng xe → Chọn đời/năm → Giỏ hàng → Thanh toán chạy trọn vẹn trên mobile và desktop.
- [ ] Giá động đúng theo đời xe + chất liệu + màu + ưu đãi, giỏ hàng lưu đủ cấu hình.
- [ ] `npm run build` (gồm `prerender.cjs`) không lỗi; không link/asset nào 404.
- [ ] Điều hướng bằng bàn phím dùng được, độ tương phản đạt AA.
- [ ] Có Walkthrough kèm screenshot 390px / 768px / 1440px cho từng trang.

## 10. Cách báo cáo

- Cuối mỗi giai đoạn, tóm tắt ngắn: đã làm gì, file nào thay đổi, điều gì còn dở, điều gì cần tôi quyết định.
- Nêu rõ mọi giả định đã đặt ra.
