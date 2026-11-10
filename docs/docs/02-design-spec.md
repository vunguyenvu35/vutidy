# Đặc tả thiết kế: Graphite Glass

> Phiên bản: v2 · 10/11/2026
> Nguồn thiết kế: canvas "Vutidy — Mac Cleaner UI" (https://claude.ai/artifact/5u4xKYVwvMjaDqh5A9ZG3H), file nguồn trong `design/source/`
> Tên app: Vutidy (tạm thời)

---

## 1. Định hướng

- **Cảm giác:** một app macOS native, nghiêm túc, đáng tin. Đây là công cụ có quyền xóa file nên giao diện phải tạo cảm giác an toàn và minh bạch trước khi tạo cảm giác "wow".
- **Nguyên tắc:**
  1. Số liệu là nhân vật chính: con số lớn, rõ, dùng font hiển thị riêng.
  2. Một màu tín hiệu (mint) cho hành động an toàn. Amber dành cho mọi thứ cần người dùng xem lại.
  3. Luôn cho thấy cách hoàn tác: Quarantine 7 ngày, dry-run và lệnh sẽ chạy đều hiển thị ngay trên giao diện.
  4. Không dùng gradient trang trí trong nội dung, không emoji, không viền trái màu cho card.
- **Khung cửa sổ:** sidebar trong mờ kiểu vibrancy (`NSVisualEffectView`, material `.sidebar`), unified toolbar cao 52–54pt, nội dung nền đặc.

---

## 2. Design tokens

Bản máy đọc được: `design/tokens/tokens.json`, `tokens.css`, `Theme.swift`.

### 2.1 Màu

| Token | Giá trị | Dùng cho |
|---|---|---|
| `bg.desktop` | `#07090D` | Nền desktop (chỉ để trình bày mockup) |
| `bg.content` | `#0F1217` | Nền vùng nội dung |
| `bg.card` | `#151920` | Card thường |
| `bg.hero` | `#171C25 → #131720` | Card nổi bật (hero, panel tóm tắt) |
| `bg.code` | `#0A0C10` | Khối lệnh, path |
| `bg.sidebar` | `rgba(26,30,39,0.66)` + blur 40 | Sidebar (bản native dùng vibrancy) |
| `border.subtle` | `rgba(255,255,255,0.06)` | Viền card |
| `border.default` | `rgba(255,255,255,0.10)` | Viền nút phụ, input |
| `highlight.inset` | `inset 0 1px 0 rgba(255,255,255,0.04–0.06)` | Ánh sáng mép trên card |
| `text.primary` | `#EDF0F4` | Chữ chính |
| `text.secondary` | `#A6B0BD` | Chữ phụ (≥ 4.5:1 trên `bg.card`) |
| `text.tertiary` | `#8A95A3` | Nhãn nhỏ, placeholder |
| `signal` | `#3DDC97` | Hành động an toàn, CTA, trạng thái tốt |
| `signal.text` | `#8EF0C2` | Chữ màu tín hiệu trên nền tối |
| `signal.on` | `#062014` | Chữ trên nút màu tín hiệu |
| `review` | `#F2B13A` | Cần xem lại, cảnh báo |
| `info` | `#5AA9FF` | Hệ thống, thông tin |
| `apps` | `#A78BFA` | Ứng dụng |
| `danger` | `#FF8A7A` | Nguy hiểm (hiếm dùng) |

Màu danh mục dung lượng: Hệ thống `info`, Ứng dụng `apps`, Developer `signal`, Tài liệu `review`, Purgeable `#7D8796`, Trống `rgba(255,255,255,0.25)`.

### 2.2 Chữ

| Vai trò | Font | Size / weight | Ghi chú |
|---|---|---|---|
| Display (số lớn) | Space Grotesk → **SF Pro Rounded** (native) | 34–40 / 700 | `letter-spacing -0.02em`, tabular nums |
| Title | Space Grotesk → **SF Pro Display** | 30–34 / 700 | |
| Heading | Inter → **SF Pro Text** | 15 / 600 | |
| Body | Inter → **SF Pro Text** | 13.5–14 / 400–500 | |
| Label | Inter → **SF Pro Text** | 11–12 / 600 | |
| Mono | JetBrains Mono → **SF Mono** | 12 / 400–500 | Path, lệnh CLI |

### 2.3 Spacing & bo góc

- Spacing: 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40
- Bo góc: nav item 8 · nút 9–12 · card 16 · hero/panel 18 · popover 18 · cửa sổ 14
- Hit target tối thiểu 32pt cho sidebar, 44pt cho nút hành động chính.

---

## 3. Bố cục chung

```
┌───────────────┬───────────────────────────────────────────────┐
│ ● ● ●         │ ‹ ›  Tiêu đề   [ Tìm kiếm…  ⌘K ]  ● Real-time │  ← toolbar 54pt
│ [◆] Vutidy   ├───────────────────────────────────────────────┤
│               │                                               │
│ Smart Scan    │   Header: mô tả nhỏ + tiêu đề có số liệu      │
│ ─ Dọn dẹp     │                                               │
│   Rác hệ thống│   Nội dung module                             │
│   Dev Junk    │                                               │
│   Thùng rác   │                                               │
│ ─ Bảo vệ      │                                               │
│ ─ Tốc độ      │                                               │
│ ─ Ứng dụng    │                                               │
│ ─ File        │                                               │
│               │                                               │
│ [Quarantine]  │                                               │
└───────────────┴───────────────────────────────────────────────┘
  sidebar 248pt          content (min 640pt)
```

- Sidebar: nhóm theo module. Mục active có nền `rgba(255,255,255,0.09)` và icon màu tín hiệu. Badge số liệu dạng pill bên phải.
- Đáy sidebar: thẻ Quarantine (dung lượng, số lần dọn, link Khôi phục). Đây là "lưới an toàn" luôn hiển thị.
- Toolbar: back/forward, tiêu đề màn, tìm kiếm toàn cục ⌘K, pill trạng thái real-time.

---

## 4. Màn hình

### 4.1 Smart Scan (`Main.dc.html`)

| Vùng | Nội dung |
|---|---|
| Header | Ngày + thời lượng quét; tiêu đề "Mac của bạn có thể lấy lại **24,8 GB**"; nút Quét lại |
| Hero dung lượng | Vòng ngoài: dung lượng theo danh mục. Vòng trong: phần có thể dọn. Tâm: dung lượng trống hiện tại → sau khi dọn. Bên phải: legend có thanh tỉ lệ, CTA "Dọn 24,8 GB", "Xem trước (dry-run)", ghi chú "Hoàn tác được trong 7 ngày" |
| 3 card module | **Dọn dẹp:** thanh theo nhóm. **Bảo vệ:** 3 chỉ số và danh sách mục chưa ký. **Tăng tốc:** sparkline memory pressure và gợi ý |
| Hàng dưới | Biểu đồ giải phóng 30 ngày; danh sách Quarantine với vòng đếm ngày còn lại và nút Khôi phục |

### 4.2 Dev Junk (`DevJunk.dc.html`, interactive)

- Nhóm theo công cụ: Docker, JetBrains, Node.js, Go, Homebrew, Composer, Ollama. Mỗi nhóm có checkbox chọn cả nhóm, tile ký hiệu màu, thanh tỉ lệ đã chọn, tổng dung lượng và nút thu gọn/mở rộng.
- Dòng mục: checkbox, tên, badge `CLI` nếu dọn bằng lệnh native, path/lệnh dạng mono, nhãn An toàn / Cần xem lại, dung lượng.
- Bộ lọc: Tất cả / An toàn / Cần xem lại, kèm số lượng.
- Panel tóm tắt: donut theo công cụ, tổng đã chọn, 3 thẻ radio chọn cách dọn (Quarantine / Thùng rác / Chỉ xem trước), khung **"Lệnh sẽ chạy"** cập nhật theo lựa chọn, CTA.
- Mặc định chỉ chọn mục `safe`.

### 4.3 Space Lens (`SpaceLens.dc.html`)

- Breadcrumb dạng pill; chuyển kiểu hiển thị Treemap / Sunburst / Danh sách.
- Treemap nhóm theo thư mục cấp 1, màu theo danh mục. Tile đang chọn có viền tín hiệu, glow và nhãn "Đang chọn".
- Panel chi tiết: icon, tên, path, dung lượng thực / có thể prune, cảnh báo ngữ cảnh (ví dụ Docker.raw: không xóa trực tiếp), hành động dẫn sang Dev Junk.
- Danh sách "Lớn nhất trong ~/".

### 4.4 Menu Bar Popover (`Popover.dc.html`)

- Kích thước 400 × ~900pt, kính mờ (`NSPopover` với `NSVisualEffectView` material `.popover`).
- Thứ tự: Gợi ý (carousel ngang, mỗi thẻ có nút ẩn), Real-time monitor, lưới 2 cột (Ổ đĩa, Bộ nhớ, CPU + nhiệt độ + sparkline, Pin, Wi-Fi + Đo tốc độ, Thiết bị), footer (Mở app, Cài đặt).

### 4.5 Design tokens (`Styles.dc.html`)

Bảng màu, thang chữ, nút, nhãn mức an toàn, điều khiển, spacing và bo góc.

---

## 5. Component

| Component | Biến thể | Quy tắc |
|---|---|---|
| Button | Primary (nền `signal`, chữ `signal.on`, shadow glow), Secondary (viền `border.default`), Tonal (nền `rgba(255,255,255,0.08)`) | Mỗi màn chỉ một Primary |
| Badge an toàn | An toàn / Cần xem lại / Nguy hiểm / Thông tin | Luôn có chữ, không chỉ dựa vào màu |
| Segmented control | 2–4 lựa chọn, có số đếm | Dùng `aria-pressed` / `NSSegmentedControl` |
| Checkbox nhóm | all / some / none | Native: trạng thái mixed |
| Card | Thường / Hero | Hero dùng cho số liệu chính và panel hành động |
| Ring chart | Dung lượng, donut lựa chọn, đếm ngày | Gap 2–3pt giữa các đoạn |
| Code block | Lệnh sẽ chạy | Prefix `$`, chế độ dry-run hiển thị dạng comment |

---

## 6. Trạng thái & tương tác

- **Quét:** nút Quét lại chuyển thành tiến độ trong header; card module hiện skeleton cho tới khi có dữ liệu.
- **Dọn:** xác nhận một bước (hiển thị tổng và cách dọn), sau đó toast "Đã chuyển 24,8 GB vào Quarantine · Hoàn tác".
- **Rỗng:** khi không có gì để dọn, hero hiển thị "Mac của bạn đang gọn gàng", không hiển thị CTA.
- **Lỗi quyền:** thiếu Full Disk Access thì hiện banner amber ở đầu nội dung kèm nút "Mở System Settings".
- **Chuyển động:** chỉ dùng cho tiến độ quét và chuyển màn (≤ 200ms). Tôn trọng *Reduce Motion*.

---

## 7. Accessibility

- Contrast chữ ≥ 4.5:1 (nhãn 11px dùng `text.secondary`, không dùng `text.tertiary`).
- Màu danh mục khác nhau cả về độ sáng, không chỉ khác về sắc độ.
- Mọi icon-only button có label (VoiceOver).
- Biểu đồ có mô tả bằng chữ (`accessibilityLabel`).
- Hỗ trợ Increase Contrast: tăng `border.subtle` lên `0.16`.

---

## 8. Còn thiếu (đề xuất làm tiếp)

- [ ] Light mode
- [ ] Màn Uninstaller, Malware, Tối ưu, Bảo trì, Cập nhật, File trùng lặp, Quyền riêng tư
- [ ] Onboarding cấp Full Disk Access và cài privileged helper
- [ ] Settings (lịch quét, retention Quarantine, thư mục project)
- [ ] App icon
