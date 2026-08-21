# DX-OS — hệ thống thiết kế bảng điều hành

Nguồn hình ảnh: không gian làm việc B2B (Asana) — **bình tĩnh, vận hành, không “AI console”**.  
Giao diện vận hành: **tiếng Việt**. Tiền tệ: **VND (đồng)**.  
Font mã nguồn mở hỗ trợ tiếng Việt: **Be Vietnam Pro**. Không dùng TWK Lausanne (không phải font OSS).

Áp dụng cho `src/DXOS.Api/wwwroot/` và mọi UI cùng origin với API.

---

## 1. Không khí

DX-OS là **bảng điều hành quy trình** (chiến dịch → duyệt → lead → chi phí/lead), không phải sản phẩm “agent”.

- Nền trắng, chữ gần đen, xám ấm cho nút.
- Không gradient tím/cyan, không neon, không terminal giả.
- Phân tầng bằng **khoảng trắng + độ đậm chữ**, không bằng màu bão hòa.

## 2. Token

```yaml
locale: vi-VN
currency: VND
currencyDisplay: "1.500.000 ₫"

colors:
  primary: "#646f79"
  on-primary: "#ffffff"
  background: "#ffffff"
  surface: "#f3f3f3"
  border: "#e8e8e8"
  text: "#0d0d0d"
  text-muted: "#5c6370"
  accent: "#0d0e10"
  danger: "#b42318"
  warning: "#b54708"
  ok: "#027a48"

typography:
  fontFamily: "Be Vietnam Pro, Segoe UI, Noto Sans, sans-serif"
  display: { size: 30px, weight: 500, lineHeight: 1.2 }
  heading: { size: 20px, weight: 600, lineHeight: 1.3 }
  body: { size: 16px, weight: 400, lineHeight: 1.5 }
  label: { size: 12px, weight: 600, lineHeight: 1.4 }

spacing:
  base: 8px
  scale: [8, 12, 16, 24, 32, 48]

radius:
  sm: 4px
  md: 8px
  lg: 16px

shadow:
  card: "0 2px 8px rgba(0,0,0,0.08)"

motion:
  fast: 100ms
  base: 200ms
  easing: ease-in-out
```

Nút chính: nền `#646f79`, chữ trắng, cao tối thiểu 44px.  
Ô nhập: viền `#e8e8e8`, focus viền `#646f79` 2px.  
Thẻ: nền trắng, viền mềm, bán kính 8px.

## 3. Ngôn ngữ & tiền

| Khái niệm API (giữ tiếng Anh trong JSON) | Hiển thị UI |
|---|---|
| Draft | Nháp |
| PendingReview | Chờ chuyên viên |
| PendingApproval | Chờ chủ doanh nghiệp |
| Published | Đã phát hành (nội bộ) |
| Rejected | Từ chối |
| Marketer | Chuyên viên |
| Owner | Chủ doanh nghiệp |
| Sales | Kinh doanh |
| System | Hệ thống |
| NOT_READY | CHƯA SẴN SÀNG PHÁT HÀNH |
| spend / CPL | Chi phí quảng cáo / Chi phí trên mỗi lead (₫) |

Định dạng số: `Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND', maximumFractionDigits: 0 })`.

## 4. Bố cục một trang

1. Thanh trạng thái vận hành (sức khỏe API + CSDL).  
2. Chọn vai trò vận hành (không gọi “AI actor”).  
3. Cột quy trình chiến dịch (luồng duyệt).  
4. Cột tiếp nhận lead + nhận lead.  
5. Chỉ số chi phí / lead.  
6. Nhật ký thao tác (văn bản thường, không giả terminal).

## 5. Cấm trên UI này

- Gradient “AI”, icon robot, chữ Operator Console kiểu cyber.
- USD, `$`, `Ad Spend ($)`.
- Copy marketing tiếng Anh trên nút/nhãn.
- Tuyên bố ads đang chạy (`adsLive` luôn hiện **Chưa kết nối sàn quảng cáo**).
