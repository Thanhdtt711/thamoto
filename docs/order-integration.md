# Tài Liệu Tích Hợp Nhận & Xác Nhận Đơn Hàng (`d:\thamoto`)

> **Trạng thái:** Chưa triển khai (lưu lại để làm ở bước sau khi chốt xong giao diện).  
> **Hiện trạng:** Khi bấm `ĐẶT HÀNG NGAY` ở `src/thanh-toan.html` hoặc gửi form ở `src/lien-he.html`, dữ liệu hiện chỉ hiển thị trên màn hình xác nhận và xóa giỏ hàng `localStorage` (`thamoto_cart`), **chưa gửi về hệ thống quản lý của cửa hàng**.

---

## 1. Phương án đề xuất: Google Sheets (Apps Script) + Email / Telegram

- **Chi phí:** Miễn phí 100%, không cần backend/database riêng.
- **Kênh nhận thông báo:**
  1. Lưu toàn bộ đơn hàng thành từng dòng trong **Google Sheets** (dễ lọc trạng thái, tra cứu bảo hành 24 tháng).
  2. Gửi thông báo tức thì về email **`dothanh0711@gmail.com`** (qua `MailApp.sendEmail`) và/hoặc **Telegram Bot** để gọi xác nhận phom xe trong 15 phút.

---

## 2. Cấu trúc dữ liệu gửi đi (Payload JSON)

### A. Đơn đặt hàng (`src/thanh-toan.html`)
```json
{
  "type": "order",
  "orderId": "TT-84920",
  "createdAt": "2026-11-23T11:35:00+07:00",
  "customerName": "Nguyễn Văn A",
  "phone": "0963294492",
  "address": "Yên Lãng, Đống Đa, Hà Nội",
  "notes": "Giao chiều nay",
  "paymentMethod": "COD",
  "couponCode": "THAMOTO2026",
  "totalAmount": 1500000,
  "itemsSummary": "1x Thảm Lót Sàn Toyota Fortuner (ĐỜI 2017 - 2025 (Form Mới) | Thảm 6D Cao Cấp | Đen chỉ đỏ | + Thảm rối chống bẩn)"
}
```

### B. Yêu cầu tư vấn / Đo xe riêng (`src/lien-he.html`)
```json
{
  "type": "lead",
  "createdAt": "2026-11-23T11:35:00+07:00",
  "customerName": "Trần Văn B",
  "phone": "0963294492",
  "vehicle": "Toyota Fortuner 2022",
  "message": "Cần tư vấn đo phom tại nhà"
}
```

---

## 3. Hướng dẫn cài đặt Google Apps Script (3 bước)

1. Tạo một file **Google Sheets** mới gồm 2 sheet: `DonHang` và `TuVan`.
2. Vào **Tiện ích mở rộng (Extensions) → Apps Script**, dán đoạn mã mẫu sau:

```javascript
const NOTIFY_EMAIL = 'dothanh0711@gmail.com';

function doPost(e) {
  try {
    const data = JSON.parse(e.postData.contents);
    const ss = SpreadsheetApp.getActiveSpreadsheet();

    if (data.type === 'order') {
      const sheet = ss.getSheetByName('DonHang') || ss.insertSheet('DonHang');
      if (sheet.getLastRow() === 0) {
        sheet.appendRow([
          'Mã đơn', 'Thời gian', 'Khách hàng', 'SĐT', 'Địa chỉ',
          'Sản phẩm & Cấu hình', 'Tổng tiền', 'Thanh toán', 'Mã giảm giá', 'Ghi chú', 'Trạng thái'
        ]);
      }
      sheet.appendRow([
        data.orderId, data.createdAt, data.customerName, "'" + data.phone, data.address,
        data.itemsSummary, data.totalAmount, data.paymentMethod, data.couponCode || '', data.notes || '', 'Mới'
      ]);

      MailApp.sendEmail({
        to: NOTIFY_EMAIL,
        subject: `[ĐƠN MỚI ${data.orderId}] ${data.customerName} - ${data.phone}`,
        body: `Khách: ${data.customerName}\nSĐT: ${data.phone}\nĐịa chỉ: ${data.address}\nThanh toán: ${data.paymentMethod}\nTổng tiền: ${data.totalAmount} đ\nChi tiết:\n${data.itemsSummary}\nGhi chú: ${data.notes || 'Không'}`
      });
    } else if (data.type === 'lead') {
      const sheet = ss.getSheetByName('TuVan') || ss.insertSheet('TuVan');
      if (sheet.getLastRow() === 0) {
        sheet.appendRow(['Thời gian', 'Khách hàng', 'SĐT', 'Xe', 'Nội dung', 'Trạng thái']);
      }
      sheet.appendRow([data.createdAt, data.customerName, "'" + data.phone, data.vehicle || '', data.message || '', 'Chưa gọi']);

      MailApp.sendEmail({
        to: NOTIFY_EMAIL,
        subject: `[TƯ VẤN XE] ${data.customerName} - ${data.phone}`,
        body: `Khách: ${data.customerName}\nSĐT: ${data.phone}\nXe: ${data.vehicle || 'Chưa chọn'}\nNội dung: ${data.message || 'Không'}`
      });
    }

    return ContentService.createTextOutput(JSON.stringify({ ok: true })).setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService.createTextOutput(JSON.stringify({ ok: false, error: err.message })).setMimeType(ContentService.MimeType.JSON);
  }
}
```

3. Chọn **Deploy → New deployment → Web app** (`Execute as: Me`, `Who has access: Anyone`), copy URL Web App để gắn vào frontend.

---

## 4. Checklist tích hợp vào code frontend (khi triển khai)

- [ ] Tạo biến cấu hình `ORDER_WEBHOOK_URL` (hoặc `VITE_ORDER_WEBHOOK_URL` trong `.env`).
- [ ] Tại `src/thanh-toan.html`:
  - Khóa nút `#btn-place-order` + hiển thị `"Đang gửi đơn..."` khi đang `fetch()` để chống bấm đúp.
  - Xử lý khi mạng lỗi: vẫn hiện thông báo + nút mở nhanh Zalo (`https://zalo.me/0963294492`) kèm mã đơn để không mất khách.
  - Ở màn hình `#checkout-success-container`, thêm nút **"Nhắn Zalo xác nhận nhanh (0963 294 492)"**.
- [ ] Tại `src/lien-he.html`:
  - Gửi payload `type: "lead"` tới cùng `ORDER_WEBHOOK_URL` trước khi mở `#contact-success-modal`.
- [ ] Test gửi thử 1 đơn COD, 1 đơn VietQR và 1 form Tư vấn, kiểm tra dòng mới trong Google Sheets và email tới `dothanh0711@gmail.com`.
