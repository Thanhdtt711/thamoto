# Báo Cáo Đánh Giá Thiết Kế UI/UX (`d:\thamoto`)

**Vai trò thực hiện:** Art Director kiêm UI/UX Design Critic  
**Đối tượng đánh giá:** Giao diện thực tế trên trình duyệt Chrome tại `http://localhost:5173` qua **15 screenshot** ở `390px`, `768px`, `1440px` (đối chiếu với wireframe mẫu và `AGENTS.md`).  
**Lưu ý lưu trữ ảnh:** Trình duyệt subagent đã chụp đủ 15 screenshot tại thư mục artifact `C:\Users\ADMIN\.gemini\antigravity\brain\cbd2d9d4-d1c1-45ef-bd98-d2e685e64607\.system_generated\steps\<step>\media_0.png` (sandbox không cho phép script copy trực tiếp từ thư mục conversation subagent sang `d:\thamoto\docs\design-review\`). Mọi nhận xét dưới đây đều dựa trên việc xem trực tiếp từng ảnh đã chụp.

---

## 1. Điểm tổng & Điểm 10 tiêu chí

**Điểm tổng:** **74 / 100** *(Giao diện sạch, sáng, mạch lạc và đúng luồng thương mại điện tử thực dụng; đạt mức tốt để chạy thử nghiệm, nhưng còn một số điểm lệch chi tiết ảnh/xe, trải nghiệm tablet `768px`, và dấu ấn "template AI" ở các khối card lặp lại).*

| # | Tiêu chí | Điểm (/10) | Nhận xét 1 câu |
|---|---|---|---|
| 1 | Ấn tượng đầu tiên (5 giây) | **8.0** | Vào `index-1440.png` hiểu ngay bán thảm lót sàn theo xe và thấy ngay bộ lọc YMM + nút đỏ `TÌM KIẾM NGAY`. |
| 2 | Thứ bậc thị giác | **7.5** | Dẫn mắt tốt từ YMM Filter → Hãng xe → Bán chạy → Đánh giá, nhưng ở `768px` thanh đáy mobile làm phân tán nhẹ. |
| 3 | Màu sắc | **8.0** | Navy `#0D2C54`, Đỏ `#C81E2B`, nền `#F4F6F9` và sao `#F59E0B` cân bằng, đỏ chỉ giữ cho CTA chính và trạng thái chọn hãng. |
| 4 | Typography | **7.5** | `Be Vietnam Pro` hiển thị tiếng Việt sắc nét, giá `tabular-nums` dễ quét; vài tiêu đề phụ in hoa liên tiếp hơi cứng. |
| 5 | Bố cục, khoảng trắng & nhịp điệu | **7.0** | Desktop `1440px` thoáng và thẳng hàng (lưới 6 cột hãng xe rất gọn), nhưng ở `768px` (`index-768.png`) vẫn dùng layout cuộn ngang như mobile. |
| 6 | Hình ảnh & nội dung | **6.0** | Ảnh chụp thực tế trong xe sắc nét, nhưng `chi-tiet-1440.png` (Toyota Fortuner) lại dùng ảnh bậc cửa Mercedes-Benz và `san-pham-1440.png` lặp ảnh thảm cho mọi dòng xe. |
| 7 | Component & trạng thái | **7.5** | Nút, select, swatch màu, chip hãng xe (`san-pham-1440.png`) thẳng hàng và rõ trạng thái chọn; thiếu trạng thái phân biệt cho các card chính sách. |
| 8 | Niềm tin & chuyển đổi | **7.5** | Luồng 3 bước mượt, có sticky tổng tiền trên mobile và cam kết rõ ràng, nhưng tên khách hàng & 100% 5 sao ở `index-1440.png` hơi đều đặn nhân tạo. |
| 9 | Bản Mobile & Desktop | **7.0** | Mobile `390px` và Desktop `1440px` tách biệt tốt (2 cột sticky trên `chi-tiet-1440.png`), nhưng Tablet `768px` bị lỡ cỡ và nút nổi Zalo dễ che mép phải nội dung. |
| 10 | Độ tự nhiên / Cá tính thương hiệu (AI look) | **7.0** | Sạch sẽ nhưng vẫn mang nét template SaaS/E-commerce chuẩn hóa (bo góc 12px đồng loạt, các card chính sách 2×2 và 1×3 giống hệt nhau). |

---

## 2. Top 5 điểm mạnh

1. **Bộ lọc YMM ngang 1 hàng trên Desktop tiết kiệm chiều dọc xuất sắc** (`index-1440.png`, khu vực đầu trang): 3 dropdown + nút đỏ `TÌM KIẾM NGAY` nằm gọn trên 1 hàng, giúp toàn bộ khối **CHỌN THEO HÃNG XE** (12 hãng) hiện trọn vẹn ngay trong màn hình đầu tiên.
2. **Lưới bộ lọc 12 hãng xe trên `san-pham.html` thẳng hàng tuyệt đối** (`san-pham-1440.png` & `san-pham-390.png`, khối `#brand-tabs-bar`): `TẤT CẢ` chiếm hàng đầu, 12 hãng xếp đều 4×3 trên Desktop và 2×6 trên Mobile, logo và chữ thẳng mép trái, trạng thái active viền đỏ không nhảy kích thước.
3. **Trang cấu hình `chi-tiet.html` Desktop 2 cột rõ ràng, ít ma sát** (`chi-tiet-1440.png`, cột trái gallery + cột phải cấu hình): Bước 1 chọn Form xe có ảnh + dấu check Navy, Bước 2 chọn Chất liệu & Swatch màu, Ưu đãi checkbox cập nhật `TỔNG TIỀN: 1.500.000 đ` rất trực quan.
4. **Header Desktop & Logo SVG mới đồng bộ hoàn hảo với bảng màu** (`index-1440.png`, `thanh-toan-1440.png`, thanh Header): Icon thảm đỏ `#C81E2B` trên nền Navy `#0D2C54`, ô tìm kiếm trắng tương phản cao, nút Giỏ hàng đỏ có badge số lượng.
5. **Footer cân đối, đầy đủ thông tin thật và chính sách minh bạch** (`index-1440.png`, `gioi-thieu-1440.png`, phần đáy trang): Viền đỏ 4px tách nền, 3 cụm thông tin rõ ràng (CTA gọi/Zalo, Điều hướng + Chính sách, Card liên hệ Yên Lãng - Hà Nội).

---

## 3. Top 10 vấn đề thẩm mỹ (Theo mức độ ảnh hưởng)

| # | Mức độ | Trang | Viewport | Khu vực | Mô tả vấn đề | Vì sao ảnh hưởng | Đề xuất sửa cụ thể | Screenshot |
|---|---|---|---|---|---|---|---|---|
| 1 | **Cao** | `chi-tiet.html` | `1440px`, `768px`, `390px` | Gallery ảnh chính & Bước 1 Form Mới | Trang đang cấu hình **Toyota Fortuner** nhưng ảnh nội thất lại hiện bậc cửa **Mercedes-Benz** (`CUSTOM FITTED` + logo ngôi sao). | Khách mua xe Toyota nhìn thấy logo Mercedes sẽ nghi ngờ ảnh ghép/không phải hàng chụp thật cho xe mình, giảm niềm tin chuyển đổi. | Dùng ảnh `install-fortuner.png` (hoặc ảnh khoang lái không dính logo hãng khác) làm ảnh mặc định cho dòng Toyota/xe phổ thông. | `chi-tiet-1440.png` (steps/38) |
| 2 | **Cao** | `san-pham.html` | `1440px`, `390px` | Lưới card dòng xe | 7/8 dòng xe Toyota (`Corolla Cross`, `Innova`, `Raize`, `Veloz Cross`, `Vios`, `Camry`, `Corolla Altis`) dùng lặp lại 4 ảnh thảm rời giống hệt nhau. | Người dùng không phân biệt được phom xe SUV vs Sedan bằng mắt thường; trang trông thiếu đầu tư hình ảnh riêng cho từng mẫu xe. | Dùng ảnh ngoại thất/nội thất theo từng phân khúc (SUV/Sedan/MPV) hoặc gắn nhãn phân khúc/đời xe hỗ trợ lên góc ảnh card. | `san-pham-1440.png` (steps/33) |
| 3 | **Cao** | `gio-hang.html`, `thanh-toan.html`, `cart-drawer` | `390px`, `1440px` | Tên sản phẩm trong giỏ | Hiển thị **"Thảm Lót Sàn Mazda Mazda 3"** và **"Mazda Mazda 3"** (lặp chữ `Mazda` 2 lần). | Lỗi ghép chuỗi `${brand} ${model}` khi tên dòng xe đã chứa tên hãng (`Mazda 3`, `Mazda 6`) tạo cảm giác thiếu chỉn chu. | Kiểm tra `model.startsWith(brand)` trước khi ghép tên đầy đủ: nếu đã bắt đầu bằng tên hãng thì chỉ dùng `${model}`. | `gio-hang-1440.png` (steps/49), `cart-drawer-1440.png` (steps/54) |
| 4 | **Vừa** | `index.html`, `chi-tiet.html` | `768px` (Tablet) | Phần Chọn hãng xe & Thanh đáy | Ở `768px`, mục Chọn hãng xe vẫn cuộn ngang làm `Mercedes-Benz` bị cắt nửa ở mép phải, đồng thời thanh `mobile-nav` vẫn hiện ở đáy màn hình. | `768px` là màn hình Tablet (đủ rộng cho lưới 4 cột hãng xe và header desktop gọn) nhưng đang dùng trải nghiệm mobile phóng to. | Đổi lưới hãng xe sang `md:grid-cols-4 lg:grid-cols-6` từ `768px`; ẩn `mobile-nav` hoặc chuyển sang menu tablet hợp lý hơn. | `index-768.png` (steps/24) |
| 5 | **Vừa** | `chi-tiet.html`, `gio-hang.html`, `thanh-toan.html` | `390px`, `768px` | Nút nổi `Zalo` góc phải dưới | Nút tròn `Zalo` (`right-4 bottom-20`) nằm đè sát mép trên thanh sticky `ĐẶT MUA NGAY` (`chi-tiet-390.png`) và che một phần nút `Áp dụng` / radio `VietQR`. | Gây rối mắt và tăng nguy cơ bấm nhầm khi thao tác ngón tay ở vùng mép phải màn hình mobile. | Trên `chi-tiet.html` mobile, nâng nút `Zalo` lên `bottom-24` (hoặc ẩn nút nổi trên trang checkout/giỏ hàng vì đã có nút Zalo trong Footer/Header). | `chi-tiet-390.png` (steps/42), `gio-hang-390.png` (steps/47) |
| 6 | **Vừa** | `chi-tiet.html` | `1440px` | Bước 2: Chất liệu thảm | 4 nút chất liệu chia thành 2 hàng (hàng trên 2 nút, hàng dưới 2 nút dài hơn) với độ rộng không đều. | Nhìn hơi lộn xộn so với sự ngay ngắn của Bước 1 (2 thẻ bằng nhau) và Ưu đãi (2 dòng full-width). | Dùng `grid grid-cols-2 gap-2.5` cho 4 pill chất liệu để tạo lưới 2×2 cân đối tuyệt đối. | `chi-tiet-1440.png` (steps/38) |
| 7 | **Vừa** | `index.html` | `1440px`, `390px` | Khách hàng lắp đặt thực tế | Cả 4 đánh giá đều là 5 sao, cả 4 khách đều ở Hà Nội (`Đống Đa`, `Cầu Giấy`, `Thanh Xuân`, `Hai Bà Trưng`) với cấu trúc câu na ná nhau. | Người mua tinh ý dễ nhận ra mẫu đánh giá dàn dựng, làm giảm độ tin cậy thật. | Đa dạng hóa tỉnh thành (Hà Nội, TP.HCM, Đà Nẵng, Hải Phòng), thêm ngày lắp đặt thực tế hoặc chi tiết cụ thể hơn (VD: "Xe chạy dịch vụ", "Lắp bản 7 chỗ"). | `index-1440.png` (steps/20) |
| 8 | **Nhẹ** | `gioi-thieu.html` | `1440px`, `390px` | Cam kết & Chính sách (2×2) | 3 thẻ Cam kết và 4 thẻ Chính sách dùng chung 1 kiểu card trắng bo `12px`, chữ đều tăm tắp, không có icon hay điểm nhấn số thứ tự. | Nhìn đơn điệu, thiếu điểm neo thị giác để khách quét nhanh chính sách quan trọng. | Thêm icon nhỏ (`shield-check`, `refresh-cw`, `truck`, `lock`) màu Navy/Đỏ hoặc badge số `01–04` đầu mỗi thẻ chính sách. | `gioi-thieu-1440.png` (steps/69) |
| 9 | **Nhẹ** | `gio-hang.html` | `1440px` | Cột trái & Cột phải | Khi giỏ có 1–2 sản phẩm, cột trái ngắn hơn cột phải `TÓM TẮT ĐƠN HÀNG` để lại khoảng nền xám trống dưới thẻ sản phẩm. | Tạo cảm giác hụt chân nhẹ ở cột trái trên màn hình rộng. | Thêm 1 dải cam kết nhỏ gọn (`Miễn phí lắp đặt · Đổi trả 1-1 · Bảo hành 24 tháng`) ngay dưới danh sách sản phẩm ở cột trái. | `gio-hang-1440.png` (steps/49) |
| 10 | **Nhẹ** | `index.html` | `768px` | Thanh Header tablet | Ở `768px`, chữ `THẢM LÓT SÀN` cạnh logo chỉ cách ô tìm kiếm khoảng vài pixel; phần `Vừa vặn 100% \| Lắp tại nhà \| Đổi trả 1-1` bên phải tiêu đề YMM bị rớt `1-1` xuống dòng lẻ. | Chữ `1-1` mồ côi xuống dòng làm tiêu đề card YMM mất cân đối trên tablet. | Thêm `whitespace-nowrap` hoặc đặt dòng cam kết ngay dưới tiêu đề ở `< 1024px` để không rớt chữ `1-1`. | `index-768.png` (steps/24) |

---

## 4. Đối chiếu wireframe

| Khu vực | Trạng thái | Mức lệch | Ghi chú đối chiếu |
|---|---|---|---|
| Header Mobile (Trang chủ & App bar trang con) | **Khớp** | Không lệch | `index-390.png` có Logo + Search + Giỏ hàng; `san-pham-390.png` và `chi-tiet-390.png` có App bar `←`, tiêu đề in hoa, Giỏ hàng. |
| Header Desktop 1 hàng + Breadcrumb | **Khớp** | Không lệch | Menu 4 mục, tìm kiếm nhanh, Giỏ hàng đỏ, Breadcrumb đầy đủ ở trang con. |
| Trang chủ: YMM Filter (Không banner) | **Khớp** | Không lệch | Đặt ngay đầu trang, 3 dropdown + nút đỏ `TÌM KIẾM NGAY` + cam kết 1 hàng. |
| Trang chủ: Chọn Theo Hãng Xe | **Khớp** | Lệch nhẹ ở `768px` | `390px` cuộn ngang tròn viền đỏ; `1440px` 6 cột đẹp; `768px` vẫn cuộn ngang nên cắt chữ hãng thứ 9. |
| Trang chủ: Sản Phẩm Bán Chạy & Khách Hàng Thực Tế | **Khớp** | Không lệch | Mobile cuộn ngang / 2 cột; Desktop 4 cột với 5 sao `#F59E0B` và giá `tabular-nums`. |
| `san-pham.html`: Tab hãng, tìm nhanh, phân khúc | **Khớp** | Lệch nhẹ về ảnh | Nhóm `SUV / CUV / MPV` & `SEDAN / HATCHBACK` chuẩn, card active/hover viền đỏ, nhưng ảnh từng dòng xe bị dùng chung ảnh thảm. |
| `chi-tiet.html`: 2 bước + ưu đãi + sticky bar | **Khớp** | Lệch nhẹ ở `chi-tiet-1440.png` | Đủ 2 bước, 2 ưu đãi, sticky đáy mobile; riêng ảnh mặc định của Fortuner đang dính logo Mercedes-Benz. |

---

## 5. Mục 10: Đánh giá mức độ "đồ AI làm" (AI-generated look) & 5 đề xuất tạo cá tính riêng

### Các dấu hiệu "AI look" quan sát được trên screenshot
1. **Card đồng loạt một khuôn (`gioi-thieu-1440.png`, `index-1440.png`):** Toàn bộ card (YMM, Hãng xe, Bán chạy, Đánh giá, Chính sách) dùng đúng 1 công thức: nền trắng `#FFFFFF`, viền `#E2E8F0`, bo góc `12px`, shadow nhẹ giống hệt nhau.
2. **Đánh giá khách hàng quá đều (`index-1440.png`):** Cả 4 khách đều 5.0 sao, đều ở Hà Nội, độ dài câu nhận xét đều 2 dòng bằng nhau.
3. **Lặp ảnh sản phẩm làm ảnh xe (`san-pham-1440.png`):** Dùng 4 ảnh thảm xoay vòng cho 8 mẫu xe Toyota làm mất tính chân thực của danh mục dòng xe.

### 5 thay đổi cụ thể để tạo cá tính riêng ngành thảm ô tô
1. **Dùng họa tiết đường chỉ may / vân quả trám tinh tế (Subtle Stitch / Carbon Accent):** Thêm đường viền đứt đoạn tinh tế (`1px dashed rgba(200,30,43,0.35)`) hoặc góc cắt vát nhẹ ở thẻ Form xe đang chọn hoặc banner cam kết, gợi liên tưởng trực tiếp đến **đường chỉ may thảm 6D**.
2. **Hiển thị trực quan "Mặt cắt / Lợi ích 5 lớp" hoặc "So sánh 6D vs 360 vs TPE" gọn trong `chi-tiet.html`:** Thay vì 4 pill chữ đơn thuần ở Bước 2, thêm 1 dòng mô tả ngắn 3–4 từ ngay dưới tên chất liệu (VD: `Thảm 6D Cao Cấp — Êm chân, có thảm rối`, `Thảm 360 Full Xe — Phủ kín 100% nỉ sàn`).
3. **Thay ảnh bậc cửa Mercedes-Benz ở `chi-tiet.html` và ảnh card xe ở `san-pham.html`:** Mỗi dòng xe phổ biến (`Fortuner`, `Vios`, `CX-5`, `SantaFe`, `CR-V`) nên có ảnh nội thất/ngoại thất đúng xe đó thay vì dùng chung ảnh bậc cửa Mercedes.
4. **Cá nhân hóa đánh giá thực tế (`index.html`):** Hiển thị ngày lắp (`12/11/2026`), biển tỉnh đa dạng (`Hà Nội`, `Hải Phòng`, `TP.HCM`, `Bắc Ninh`), và tag loại thảm khách đã lắp (`Đã lắp: Thảm 6D Đen chỉ đỏ`).
5. **Tạo điểm nhấn thị giác cho `gioi-thieu.html`:** Dùng số thứ tự lớn màu Navy nhạt (`01`, `02`, `03`, `04`) + icon đặc thù ở 4 thẻ Chính sách thay cho 4 hộp chữ giống nhau hoàn toàn.

---

## 6. Lộ trình sửa 3 nhóm (Chờ bạn chọn trước khi sửa)

### Nhóm 1: Sửa nhanh (Dưới 1 giờ) — **ĐÁNG LÀM NHẤT NGAY**
- Sửa lỗi lặp tên `"Mazda Mazda 3"` trong giỏ hàng/checkout (`chi-tiet.html`, `cart.js`).
- Sửa ảnh mặc định ở `chi-tiet.html` cho Toyota Fortuner (dùng `install-fortuner.png` thay cho ảnh bậc cửa Mercedes-Benz).
- Đẩy nút nổi `Zalo` lên `bottom-24` trên `chi-tiet.html` mobile (hoặc ẩn nút nổi ở `gio-hang.html`, `thanh-toan.html`) để không đè lên thanh sticky và nút thao tác.
- Chuyển 4 pill chất liệu ở `chi-tiet.html` sang lưới `grid-cols-2`, thêm `whitespace-nowrap` cho dòng cam kết ở `index-768.png`.

### Nhóm 2: Sửa vừa (1–3 giờ)
- Tối ưu giao diện Tablet `768px`: chuyển `CHỌN THEO HÃNG XE` sang lưới 4 cột ở `md:` (`index.html`) để không bị cắt hãng thứ 9.
- Thêm mô tả ngắn 1 dòng dưới mỗi chất liệu ở Bước 2 (`chi-tiet.html`), đa dạng hóa đánh giá khách hàng (`index.html`), thêm icon/số thứ tự cho 4 thẻ chính sách (`gioi-thieu.html`) và dải cam kết dưới cột trái `gio-hang.html`.

### Nhóm 3: Sửa lớn (Nửa ngày+)
- Tạo/thu thập ảnh đại diện riêng theo từng dòng xe phổ biến cho `san-pham.html` (tránh lặp 4 ảnh thảm cho mọi mẫu xe) và nén toàn bộ ảnh sang WebP (< 150 KB/ảnh).
