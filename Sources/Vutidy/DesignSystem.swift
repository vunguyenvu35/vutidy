import SwiftUI
import AppKit
import CoreKit

// MARK: - Khối cơ bản

/// Ô icon bo góc, nền là màu nhấn nhạt — dùng thay cho icon trần để tạo nhịp thị giác.
struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.Signal.base
    var size: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(tint.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(Glyph(symbol: symbol, size: size * 0.58, stroke: tint, fill: tint))
            .accessibilityHidden(true)
    }
}

/// Icon của app thật (từ đường dẫn .app hoặc tiến trình), có fallback.
struct AppIconView: View {
    var image: NSImage?
    var fallback: String = "gearshape"
    var size: CGFloat = 32
    var body: some View {
        if let image { Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size) }
        else { IconTile(symbol: fallback, tint: Theme.Text.secondary, size: size) }
    }
}

/// Thanh đo ngang (CPU, RAM…).
struct MeterBar: View {
    let value: Double
    var color: Color = Theme.Signal.base
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(min(1, max(0, value)))))
            }
        }.frame(height: height)
    }
}

/// Thẻ chỉ số có vòng đo: số lớn + nhãn + chú thích.
struct GaugeTile: View {
    let title: String
    let value: String
    let caption: String
    let fraction: Double
    var color: Color = Theme.Signal.base
    var symbol: String
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Ring(segments: [.init(value: max(0.001, fraction), color: color), .init(value: max(0.0, 1 - fraction), color: .clear)], lineWidth: 8)
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
            }.frame(width: 62, height: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.Font.label).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
                Text(value).font(.vt(size: 24, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Text.primary).lineLimit(1).minimumScaleFactor(0.7)
                Text(caption).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).cardFlat()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Thẻ phần có header

struct SectionCard<Content: View, Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var tint: Color = Theme.Signal.base
    var trailing: Trailing
    var content: Content

    init(title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Theme.Signal.base,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.tint = tint
        self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let symbol { IconTile(symbol: symbol, tint: tint, size: 32) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                    if let subtitle { Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary) }
                }
                Spacer(minLength: 12)
                trailing
            }.padding(.horizontal, 18).padding(.vertical, 14)
            Divider().overlay(Theme.Border.subtle)
            content
        }.cardFlat()
    }
}

extension SectionCard where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = Theme.Signal.base,
         @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint, trailing: { EmptyView() }, content: content)
    }
}

/// Hàng danh sách: icon · tiêu đề/phụ đề · điều khiển. Có hover và đường kẻ dưới.
struct ListRow<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var monoSubtitle = false
    var showDivider = true
    var leading: Leading
    var trailing: Trailing
    @ViewState private var hover = false

    init(title: String, subtitle: String? = nil, monoSubtitle: Bool = false, showDivider: Bool = true,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.monoSubtitle = monoSubtitle; self.showDivider = showDivider
        self.leading = leading(); self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.vt(size: 13.5, weight: .medium)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(monoSubtitle ? Theme.Font.mono.leading(.tight) : Theme.Font.caption)
                            .foregroundStyle(Theme.Text.secondary).lineLimit(monoSubtitle ? 1 : 2).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(hover ? Color.white.opacity(0.035) : .clear)
            .onHover { hover = $0 }
            if showDivider { Divider().overlay(Theme.Border.subtle).padding(.leading, 18) }
        }
    }
}

/// Công tắc native kiểu macOS, kích thước nhỏ.
struct SwitchRow: View {
    @Binding var isOn: Bool
    var label: String
    var body: some View {
        Button { withAnimation(.easeInOut(duration: 0.16)) { isOn.toggle() } } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x5EF0B0), Color(hex: 0x1FB57A)], startPoint: .top, endPoint: .bottom))
                                    : AnyShapeStyle(Color.white.opacity(0.18)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0.55 : 0.30), lineWidth: 1))
                Circle().fill(.white).padding(2.5).shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            }
            .frame(width: 44, height: 25)
            .shadow(color: isOn ? Color(hex: 0x3DDC97).opacity(0.45) : .clear, radius: 8)
        }
        .buttonStyle(.plain).pointerCursor()
        .accessibilityLabel(label).accessibilityValue(isOn ? "on" : "off").accessibilityAddTraits(.isButton)
    }
}

/// Nút chữ nhỏ dạng "text button" cho thao tác phụ.
struct TextActionStyle: ButtonStyle {
    var color: Color = Theme.Signal.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.vt(size: 12.5, weight: .semibold)).foregroundStyle(color.opacity(configuration.isPressed ? 0.6 : 1)).pointerCursor()
    }
}

// MARK: - Tiện ích dữ liệu

enum AppLookup {
    /// Tìm bundle .app chứa một đường dẫn chương trình.
    static func bundleURL(containing path: String?) -> URL? {
        guard let path else { return nil }
        var acc = ""
        for comp in path.split(separator: "/") {
            acc += "/" + comp
            if comp.hasSuffix(".app") { return URL(fileURLWithPath: acc) }
        }
        return nil
    }
    static func icon(forAppAt url: URL?) -> NSImage? { url.map { NSWorkspace.shared.icon(forFile: $0.path) } }
    static func name(forAppAt url: URL) -> String {
        if let b = Bundle(url: url) {
            return (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Bảng màu mở rộng & màu theo từng trang

extension Theme {
    static let teal = Color(hex: 0x2DD4D4)
    static let orange = Color(hex: 0xFF9F5A)
    static let pink = Color(hex: 0xFF6FA5)
}

extension Page {
    /// Mỗi mục có một màu riêng (như CleanMyMac) để người dùng định hướng nhanh.
    var tint: Color {
        switch self {
        case .smartScan: return Theme.Signal.base
        case .systemJunk: return Theme.Info.base
        case .devJunk: return Theme.teal
        case .trash: return Theme.pink
        case .privacy: return Theme.apps
        case .protection: return Theme.Signal.base
        case .malware: return Theme.danger
        case .optimization: return Theme.orange
        case .maintenance: return Theme.Info.base
        case .uninstaller: return Theme.pink
        case .updater: return Theme.Info.base
        case .spaceLens: return Theme.teal
        case .largeFiles: return Theme.Review.base
        case .duplicates: return Theme.apps
        case .cloud: return Theme.Info.base
        case .quarantine: return Theme.Signal.base
        }
    }
}

/// Icon "đặc" (gradient + biểu tượng trắng) dùng cho sidebar và hero.
struct SolidIcon: View {
    let symbol: String
    var tint: Color
    var size: CGFloat = 26
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.72)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Glyph(symbol: symbol, size: size * 0.62, stroke: Color(hex: 0x0B1020, opacity: 0.86), fill: .white))
            .shadow(color: tint.opacity(0.25), radius: size * 0.25, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

/// Bộ chọn dạng "chip" (thay segmented mặc định).
struct ChipPicker<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                let on = selection == o.value
                Button { selection = o.value } label: {
                    Text(o.title).font(.vt(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .foregroundStyle(on ? Theme.Text.primary : Theme.Text.secondary)
                        .background(Capsule().fill(on ? Color.white.opacity(0.13) : .clear))
                        .animation(.easeOut(duration: 0.15), value: on)
                        .contentShape(Capsule())
                }.buttonStyle(.plain).pointerCursor()
            }
        }
        .padding(3).background(Capsule().fill(Color.white.opacity(0.05)))
    }
}

/// Hero ở giữa màn hình khi chưa quét (kiểu CleanMyMac): icon lớn, tiêu đề, mô tả, nút chính.
struct ScanHero: View {
    let page: Page
    let title: String
    let subtitle: String
    let actionTitle: String
    var busy = false
    var status: String? = nil
    let action: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            HeroArt(page: page, size: 168).frame(height: 190)
            Text(title).font(.vt(size: 30, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(subtitle).font(.vt(size: 14.5)).foregroundStyle(Color.white.opacity(0.78))
                .multilineTextAlignment(.center).frame(maxWidth: 480)
            if busy {
                ScanActivity(status: status ?? tr("Đang quét…"))
            } else if !actionTitle.isEmpty {
                ScanButton(title: actionTitle, action: action).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

// MARK: - Nền gradient theo từng mục (phong cách CleanMyMac)

extension Page {
    /// (đáy tối, đỉnh sáng hơn, màu phát sáng) — mỗi mục một "thế giới màu" riêng.
    var palette: (deep: Color, mid: Color, glow: Color) {
        switch self {
        case .smartScan:    return (Color(hex: 0x1A0638), Color(hex: 0x5B1696), Color(hex: 0xD946EF))
        case .systemJunk:   return (Color(hex: 0x071A47), Color(hex: 0x1D55C9), Color(hex: 0x56B0FF))
        case .devJunk:      return (Color(hex: 0x032B30), Color(hex: 0x0B7C80), Color(hex: 0x2DE0C6))
        case .trash:        return (Color(hex: 0x3A0A24), Color(hex: 0xA8195A), Color(hex: 0xFF72A8))
        case .privacy:      return (Color(hex: 0x170A47), Color(hex: 0x5A38C4), Color(hex: 0xB79BFF))
        case .protection:   return (Color(hex: 0x04281A), Color(hex: 0x0E8C53), Color(hex: 0x4DEBA4))
        case .malware:      return (Color(hex: 0x3A0610), Color(hex: 0xA8142B), Color(hex: 0xFF5A6E))
        case .optimization: return (Color(hex: 0x3A1308), Color(hex: 0xC2461A), Color(hex: 0xFFA25E))
        case .maintenance:  return (Color(hex: 0x0A2036), Color(hex: 0x2A64A8), Color(hex: 0x7CC0FF))
        case .uninstaller:  return (Color(hex: 0x3A0830), Color(hex: 0xA3168F), Color(hex: 0xFF7ACB))
        case .updater:      return (Color(hex: 0x06284A), Color(hex: 0x1B79C9), Color(hex: 0x62CCFF))
        case .spaceLens:    return (Color(hex: 0x042838), Color(hex: 0x0B86A0), Color(hex: 0x3FE0E8))
        case .largeFiles:   return (Color(hex: 0x3A2706), Color(hex: 0xB07A0C), Color(hex: 0xFFD470))
        case .duplicates:   return (Color(hex: 0x1B0F4F), Color(hex: 0x5A2BC4), Color(hex: 0xA68BFF))
        case .cloud:        return (Color(hex: 0x081F55), Color(hex: 0x2A6FD6), Color(hex: 0x8FCBFF))
        case .quarantine:   return (Color(hex: 0x042A26), Color(hex: 0x0C8776), Color(hex: 0x4EEBCB))
        }
    }
}

/// Nền một trang: gradient dọc + quầng sáng + vignette tối ở góc.
struct PageBackground: View {
    let page: Page
    var body: some View {
        let p = page.palette
        ZStack {
            LinearGradient(colors: [p.mid, p.deep], startPoint: .topTrailing, endPoint: .bottomLeading)
            RadialGradient(colors: [p.glow.opacity(0.55), .clear], center: UnitPoint(x: 0.78, y: 0.12), startRadius: 10, endRadius: 620)
            RadialGradient(colors: [p.glow.opacity(0.22), .clear], center: UnitPoint(x: 0.1, y: 1.0), startRadius: 10, endRadius: 480)
            RadialGradient(colors: [Color.black.opacity(0.45), .clear], center: UnitPoint(x: 0.0, y: 0.35), startRadius: 10, endRadius: 420)
        }
    }
}

/// Tất cả nền xếp chồng, chỉ trang hiện tại hiện lên → chuyển trang mượt (cross-fade).
struct WindowBackground: View {
    let current: Page
    var body: some View {
        ZStack {
            ForEach(Page.allCases) { p in PageBackground(page: p).opacity(p == current ? 1 : 0) }
        }
        .animation(.easeInOut(duration: 0.55), value: current)
        .ignoresSafeArea()
    }
}

// MARK: - Bề mặt kính

extension View {
    /// Thẻ kính mờ: nền trắng trong suốt, viền sáng, ánh sáng mép trên.
    func glassSurface(radius: CGFloat, strong: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(strong ? 0.17 : 0.11), Color.white.opacity(strong ? 0.08 : 0.05)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.30), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: - Minh họa hero (khối kính lớn) & nút Scan tròn

struct HeroArt: View {
    let page: Page
    var size: CGFloat = 176
    var symbolOverride: String? = nil
    var body: some View {
        let p = page.palette
        ZStack {
            Circle().fill(RadialGradient(colors: [p.glow.opacity(0.55), .clear], center: .center, startRadius: 4, endRadius: size * 0.95))
                .frame(width: size * 2, height: size * 2)
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.62), p.glow.opacity(0.40), p.mid.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.10)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                .overlay(alignment: .top) {
                    Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.78, height: size * 0.34).offset(y: size * 0.05).blur(radius: 1)
                }
                .shadow(color: p.glow.opacity(0.55), radius: 36, y: 18)
            if let i = IconAlias.icon(for: symbolOverride ?? page.icon) {
                VIconView(icon: i, stroke: .white, fill: .white, lineWidth: 1.5).frame(width: size * 0.54, height: size * 0.54)
                    .shadow(color: p.deep.opacity(0.5), radius: 6, y: 3)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Nút hành động chính của màn hình chào: viên thuốc sáng, icon của trang + nhãn một dòng.
/// Chữ và icon lấy màu đậm của chính trang đó nên hợp với nền; quầng sáng theo màu glow của trang.
struct ScanButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void
    @Environment(\.currentPage) private var page
    @ViewState private var hover = false

    var body: some View {
        let p = page.palette
        let ink = p.deep.mixed(with: p.mid, 0.35)
        Button(action: action) {
            HStack(spacing: 10) {
                Glyph(symbol: symbol ?? page.icon, size: 20, stroke: ink, fill: ink)
                Text(title).font(.vt(size: 17, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 30).frame(minWidth: 168).frame(height: 54)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                ZStack {
                    Capsule().fill(LinearGradient(colors: [Color.white, Color.white.opacity(hover ? 0.92 : 0.84)], startPoint: .top, endPoint: .bottom))
                    // Vệt sáng phía trên cho cảm giác bóng.
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.9), .clear], startPoint: .top, endPoint: .center))
                        .padding(.horizontal, 6).padding(.top, 2).padding(.bottom, 26)
                }
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.95), lineWidth: 1))
            .shadow(color: p.glow.opacity(hover ? 0.80 : 0.50), radius: hover ? 30 : 22, y: 8)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .scaleEffect(hover ? 1.03 : 1)
            .animation(.easeOut(duration: 0.16), value: hover)
        }
        .buttonStyle(PlainPointerStyle()).onHover { hover = $0 }
    }
}

// MARK: - Hệ nút (Primary "viên ngọc" · Danger · Secondary kính · Icon)

private struct CurrentPageKey: EnvironmentKey { static let defaultValue: Page = .smartScan }
extension EnvironmentValues {
    /// Trang đang mở — để nút lấy đúng màu của trang.
    var currentPage: Page {
        get { self[CurrentPageKey.self] }
        set { self[CurrentPageKey.self] = newValue }
    }
}

extension Color {
    /// Pha màu với một màu khác (0…1) — dùng để tạo sắc sáng/tối của nút.
    func mixed(with other: Color, _ t: Double) -> Color {
        guard let a = NSColor(self).usingColorSpace(.sRGB), let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        let m = a.blended(withFraction: CGFloat(t), of: b) ?? a
        return Color(nsColor: m)
    }
}

/// Nhãn nút có icon riêng của Vutidy.
struct IconLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack(spacing: 8) {
            Glyph(symbol: symbol, size: 16, stroke: .white, fill: .white)
            Text(title)
        }
    }
}

private struct ButtonMetrics {
    let height: CGFloat, font: CGFloat, hPad: CGFloat
    init(_ s: ControlSize) {
        switch s {
        case .mini, .small: height = 28; font = 12; hPad = 14
        case .large, .extraLarge: height = 46; font = 15; hPad = 26
        default: height = 36; font = 13.5; hPad = 20
        }
    }
}

private struct GemSkin<Label: View>: View {
    let label: Label
    let pressed: Bool
    let enabled: Bool
    let bright: Color, deep: Color, glow: Color
    let metrics: ButtonMetrics
    @ViewState private var hover = false

    var body: some View {
        label
            .font(.vt(size: metrics.font, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
            .padding(.horizontal, metrics.hPad).frame(height: metrics.height)
            .background(
                ZStack {
                    Capsule().fill(LinearGradient(colors: [bright, deep], startPoint: .top, endPoint: .bottom))
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(hover ? 0.38 : 0.28), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                }
            )
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.8), Color.white.opacity(0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: glow.opacity(enabled ? (hover ? 0.75 : 0.5) : 0), radius: hover ? 20 : 14, y: 5)
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.42)
            .onHover { hover = $0 }
            .pointerCursor()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    @Environment(\.currentPage) private var page
    func makeBody(configuration: Configuration) -> some View {
        let p = page.palette
        GemSkin(label: configuration.label, pressed: configuration.isPressed, enabled: enabled,
                bright: p.glow.mixed(with: .white, 0.18), deep: p.mid.mixed(with: p.glow, 0.25), glow: p.glow, metrics: ButtonMetrics(size))
    }
}

/// Hành động phá hủy: Remove, xóa vĩnh viễn.
struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    func makeBody(configuration: Configuration) -> some View {
        GemSkin(label: configuration.label, pressed: configuration.isPressed, enabled: enabled,
                bright: Color(hex: 0xFF7A8A), deep: Color(hex: 0xD02250), glow: Color(hex: 0xFF4D6D), metrics: ButtonMetrics(size))
    }
}

private struct GlassSkin<Label: View>: View {
    let label: Label
    let pressed: Bool
    let enabled: Bool
    let metrics: ButtonMetrics
    var minWidth: CGFloat? = nil
    @ViewState private var hover = false
    var body: some View {
        // Cùng chiều cao với nút chính để hai nút đặt cạnh nhau (vd. "Free up memory" · "Quit") cân đối.
        label
            .font(.vt(size: metrics.font, weight: .semibold))
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color.white.opacity(hover ? 1 : 0.94))
            .padding(.horizontal, metrics.hPad).frame(minWidth: minWidth).frame(height: metrics.height)
            .background(
                ZStack {
                    Capsule().fill(Color.black.opacity(0.16))                                   // đáy tối nhẹ cho nút nổi khỏi nền
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(pressed ? 0.26 : (hover ? 0.30 : 0.20)),
                                                           Color.white.opacity(pressed ? 0.12 : (hover ? 0.14 : 0.08))],
                                                  startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(hover ? 0.7 : 0.5), Color.white.opacity(0.12)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(Capsule().inset(by: 1).strokeBorder(Color.white.opacity(0.10), lineWidth: 1).blur(radius: 0.5)) // viền sáng bên trong
            .shadow(color: .black.opacity(enabled ? 0.28 : 0), radius: hover ? 10 : 6, y: 3)
            .scaleEffect(pressed ? 0.97 : 1).opacity(enabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }.pointerCursor()
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    /// Độ rộng tối thiểu để các nút đặt cạnh nhau (ví dụ cột nút trong Cài đặt) đều nhau; nút dài hơn vẫn tự giãn.
    var minWidth: CGFloat? = nil
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    func makeBody(configuration: Configuration) -> some View {
        GlassSkin(label: configuration.label, pressed: configuration.isPressed, enabled: enabled, metrics: ButtonMetrics(size), minWidth: minWidth)
    }
}

/// Nút tròn chỉ có icon.
struct IconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 30
    @ViewState private var dummy = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.vt(size: 13, weight: .medium)).foregroundStyle(Theme.Text.primary)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.26 : 0.14)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.28)))
            .pointerCursor()
    }
}

// MARK: - Checkbox của Vutidy

enum CheckState { case off, on, mixed }

/// Ô chọn kiểu kính: tắt = viền sáng, bật = ô trắng có dấu tích màu của trang, "một phần" = gạch ngang.
/// Mọi checkbox dùng đúng một kích thước để các cột luôn thẳng hàng.
struct VCheckbox: View {
    let state: CheckState
    let action: () -> Void
    @Environment(\.currentPage) private var page
    @ViewState private var hover = false

    init(state: CheckState, action: @escaping () -> Void) { self.state = state; self.action = action }
    init(isOn: Binding<Bool>) { self.init(state: isOn.wrappedValue ? .on : .off) { isOn.wrappedValue.toggle() } }

    static let size: CGFloat = 22

    var body: some View {
        let ink = page.palette.deep.mixed(with: page.palette.mid, 0.35)
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(state == .off ? Color.white.opacity(hover ? 0.16 : 0.08) : Color.white.opacity(0.96))
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(state == .off ? Color.white.opacity(hover ? 0.75 : 0.5) : Color.white, lineWidth: 1.5)
                if state == .on {
                    Path { p in
                        p.move(to: CGPoint(x: 6.2, y: 11.4)); p.addLine(to: CGPoint(x: 9.6, y: 14.8)); p.addLine(to: CGPoint(x: 15.8, y: 7.6))
                    }.stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                } else if state == .mixed {
                    Path { p in p.move(to: CGPoint(x: 6.5, y: 11)); p.addLine(to: CGPoint(x: 15.5, y: 11)) }
                        .stroke(ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                }
            }
            .frame(width: Self.size, height: Self.size)
            .animation(.easeOut(duration: 0.14), value: state)
            .shadow(color: state == .off ? .clear : Color.white.opacity(0.35), radius: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.pointerCursor()
        .accessibilityValue(state == .on ? "on" : (state == .mixed ? "mixed" : "off"))
    }
}

// MARK: - Điều khiển chuẩn: ô chọn · bộ tăng giảm · công tắc · ô nhập (cùng một ngôn ngữ kính)

private struct GlassField<Content: View>: View {
    let hover: Bool
    var height: CGFloat = 32
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 12).frame(height: height)
            .background(Capsule().fill(LinearGradient(colors: [Color.white.opacity(hover ? 0.22 : 0.15), Color.white.opacity(hover ? 0.12 : 0.07)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.38), Color.white.opacity(0.10)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// Ô chọn thả xuống (thay `Picker` mặc định màu xanh). Dùng popover tự dựng vì `Menu` của macOS làm phẳng giao diện nhãn.
struct VSelect<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, title: String)]
    var width: CGFloat? = nil
    var symbol: ((T) -> String?)? = nil
    var height: CGFloat = 32
    @ViewState private var hover = false
    @ViewState private var open = false

    var current: String { options.first { $0.value == selection }?.title ?? "" }

    var body: some View {
        Button { open.toggle() } label: {
            GlassField(hover: hover || open, height: height) {
                HStack(spacing: 8) {
                    if let sym = symbol?(selection) { Glyph(symbol: sym, size: 14, stroke: Theme.Text.primary, fill: Theme.Text.primary) }
                    Text(current).lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Text.secondary)
                }
                .font(.vt(size: 13, weight: .medium)).foregroundStyle(Theme.Text.primary)
                .frame(width: width.map { $0 - 24 })
            }
        }
        .buttonStyle(.plain).onHover { hover = $0 }.pointerCursor()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            // Danh sách dài (ví dụ phông chữ) cuộn được thay vì tràn khỏi màn hình. Danh sách ngắn KHÔNG bọc ScrollView:
            // `ScrollView([])` không có trục cuộn nên không có chiều cao riêng và popover co thành một thanh trống.
            let rows = VStack(alignment: .leading, spacing: 2) {
                ForEach(options.indices, id: \.self) { i in
                    SelectRow(title: options[i].title, symbol: symbol?(options[i].value), selected: options[i].value == selection) {
                        selection = options[i].value; open = false
                    }
                }
            }
            .padding(6)
            if options.count > 10 {
                ScrollView(.vertical) { rows }.frame(minWidth: max(width ?? 0, 160), maxHeight: 360)
            } else {
                rows.frame(minWidth: max(width ?? 0, 160))
            }
        }
    }
}

private struct SelectRow: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let action: () -> Void
    @ViewState private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol { Glyph(symbol: symbol, size: 15, stroke: .primary, fill: .primary) }
                Text(title).font(.vt(size: 13, weight: selected ? .semibold : .regular))
                Spacer(minLength: 12)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Color.accentColor.opacity(0.9) : .clear))
            .foregroundStyle(hover ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }.pointerCursor()
    }
}

/// Bộ tăng giảm: − giá trị +
struct VStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value - step >= range.lowerBound) { value = max(range.lowerBound, value - step) }
            Text(format(value)).font(.vt(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.Text.primary).frame(minWidth: 86)
            button("plus", enabled: value + step <= range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 34, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(PlainPointerStyle()).foregroundStyle(enabled ? Theme.Text.primary : Theme.Text.tertiary)
        .disabled(!enabled).pointerCursor(enabled)
    }
}

/// Ô nhập một dòng có icon tìm kiếm.
struct VTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol = "v.search"
    var width: CGFloat? = 220
    @ViewState private var hover = false
    var body: some View {
        GlassField(hover: hover) {
            HStack(spacing: 8) {
                Glyph(symbol: symbol, size: 14, stroke: Theme.Text.secondary, fill: Theme.Text.secondary)
                TextField(placeholder, text: $text).textFieldStyle(.plain).font(.vt(size: 13)).foregroundStyle(.white)
                if !text.isEmpty {
                    Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }
                        .buttonStyle(.plain).foregroundStyle(Theme.Text.tertiary).pointerCursor()
                }
            }.frame(width: width.map { $0 - 24 })
        }.onHover { hover = $0 }
    }
}

/// Nhóm "nhãn + ô chọn" dùng cho thanh bộ lọc.
struct LabeledControl<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            control
        }
    }
}

// MARK: - Loading: vòng cung phát sáng · thanh chạy mờ · thẻ loading kính

/// Vòng xoay riêng của Vutidy (thay `ProgressView` mặc định nhỏ, xám, lạc tông).
struct VSpinner: View {
    var size: CGFloat = 18
    var lineWidth: CGFloat? = nil
    var color: Color = .white
    var body: some View {
        let w = lineWidth ?? max(2, size * 0.11)
        TimelineView(.animation) { ctx in
            let angle = (ctx.date.timeIntervalSinceReferenceDate * 360 / 0.85).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: w)
                Circle().trim(from: 0, to: 0.30)
                    .stroke(AngularGradient(colors: [color.opacity(0.05), color], center: .center, startAngle: .degrees(0), endAngle: .degrees(108)),
                            style: StrokeStyle(lineWidth: w, lineCap: .round))
                    .rotationEffect(.degrees(angle))
                    .shadow(color: color.opacity(0.55), radius: size * 0.12)
            }
        }
        .frame(width: size, height: size).accessibilityLabel("Loading")
    }
}

/// Thanh tiến trình không xác định: một vệt sáng chạy qua lại.
struct IndeterminateBar: View {
    var width: CGFloat = 200
    var height: CGFloat = 5
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2.6) + 1) / 2                    // 0…1, chạy qua lại mượt
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.95), Color.white.opacity(0.2)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * 0.38).offset(x: (width * 0.62) * phase)
            }
        }
        .frame(width: width, height: height).clipShape(Capsule())
    }
}

/// Khối loading nhỏ dùng trong hero khi đang quét.
struct ScanActivity: View {
    let status: String
    var body: some View {
        VStack(spacing: 10) {
            VSpinner(size: 34, lineWidth: 3.5)
            Text(status).font(Theme.Font.caption).foregroundStyle(Color.white.opacity(0.8)).lineLimit(1).frame(maxWidth: 360)
            IndeterminateBar(width: 180)
        }.frame(minHeight: 92)
    }
}

/// Thẻ loading ở giữa nội dung: vòng xoay, tiêu đề, mô tả và thanh chạy.
struct LoadingCard: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 14) {
            VSpinner(size: 40, lineWidth: 4)
            VStack(spacing: 4) {
                Text(title).font(.vt(size: 15, weight: .semibold)).foregroundStyle(.white)
                if let subtitle { Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(2).multilineTextAlignment(.center) }
            }
            IndeterminateBar(width: 220)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 34).padding(.horizontal, 24)
        .glassSurface(radius: Theme.Radius.card, strong: false)
    }
}

// MARK: - Trạng thái "đang dọn"

struct CleanProgress: Equatable {
    var done: Int
    var total: Int
    var current: String
    var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
}

/// Thẻ tiến độ nổi ở đầu nội dung khi đang dọn: vòng xoay, "n / tổng mục", mục đang xử lý, thanh tiến độ thật.
struct CleaningBanner: View {
    let progress: CleanProgress
    var body: some View {
        HStack(spacing: 16) {
            VSpinner(size: 34, lineWidth: 3.5)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(tr("Đang dọn…")).font(.vt(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Spacer()
                    Text(trf("Đang dọn %@ / %@ mục", "\(min(progress.done + 1, max(progress.total, 1)))", "\(progress.total)"))
                        .font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.Text.secondary)
                }
                MeterBar(value: max(0.04, progress.fraction), color: .white, height: 7)
                if !progress.current.isEmpty {
                    Text(progress.current).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .glassSurface(radius: Theme.Radius.card, strong: true)
        .animation(.easeOut(duration: 0.2), value: progress)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Kết quả sau khi dọn

struct CleanSummary: Equatable {
    var bytes: Int64
    var done: Int
    var failed: Int
    var skipped: Int
    var mode: CleanMode
}

/// Màn hoàn tất sau khi dọn hết mọi thứ: thay cho màn "gọn gàng" bật ra đột ngột.
struct CleanDoneHero: View {
    let page: Page
    let summary: CleanSummary
    var onUndo: (() -> Void)? = nil
    let onRescan: () -> Void
    @ViewState private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            HeroArt(page: page, size: 168, symbolOverride: "v.check").frame(height: 190)
            Text(trf("Đã giải phóng %@", ByteFormat.string(summary.bytes))).font(.vt(size: 30, weight: .semibold)).foregroundStyle(.white)
            Text(trf("%@ mục đã xử lý", "\(summary.done)")
                 + (summary.failed + summary.skipped > 0 ? " · " + trf("%@ lỗi · %@ bỏ qua", "\(summary.failed)", "\(summary.skipped)") : ""))
                .font(.vt(size: 14.5)).foregroundStyle(Color.white.opacity(0.78))
            HStack(spacing: 12) {
                if let onUndo { Button { onUndo() } label: { IconLabel(title: tr("Xem Quarantine"), symbol: "v.quarantine") }.buttonStyle(SecondaryButtonStyle()) }
                Button(tr("Quét lại"), action: onRescan).buttonStyle(SecondaryButtonStyle())
            }.padding(.top, 6)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .scaleEffect(appeared ? 1 : 0.96).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appeared = true } }
    }
}

/// Thẻ kết quả nằm ở đầu danh sách khi vẫn còn mục chưa dọn.
struct CleanSummaryBanner: View {
    let summary: CleanSummary
    var onUndo: (() -> Void)? = nil
    let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "v.check", tint: Theme.Signal.base, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(trf("Đã giải phóng %@", ByteFormat.string(summary.bytes))).font(.vt(size: 14.5, weight: .semibold)).foregroundStyle(.white)
                Text(trf("%@ mục đã xử lý", "\(summary.done)")
                     + (summary.failed + summary.skipped > 0 ? " · " + trf("%@ lỗi · %@ bỏ qua", "\(summary.failed)", "\(summary.skipped)") : ""))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            }
            Spacer()
            if let onUndo { Button(tr("Xem Quarantine"), action: onUndo).buttonStyle(TextActionStyle()) }
            Button(action: onDismiss) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.tertiary).help(tr("Ẩn thông báo"))
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassSurface(radius: Theme.Radius.card, strong: true)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hộp thoại xác nhận tự dựng (thay `.alert` mặc định: nút đỏ trên nền đỏ khó đọc)

struct ConfirmRequest {
    let title: String
    let message: String
    let confirmTitle: String
    var destructive = false
    var symbol = "v.warn"
    let action: () -> Void
}

/// Dùng như `.alert` nhưng hiển thị hộp thoại của Vutidy ở cấp cửa sổ gốc (không bị cắt bởi vùng cuộn).
struct ConfirmDialogModifier: ViewModifier {
    @EnvironmentObject var state: AppState
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let confirmTitle: String
    let destructive: Bool
    let symbol: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isPresented) { shown in
            guard shown else { return }
            isPresented = false
            state.confirmRequest = ConfirmRequest(title: title, message: message, confirmTitle: confirmTitle,
                                                  destructive: destructive, symbol: symbol, action: action)
        }
    }
}

extension View {
    func confirmDialog(isPresented: Binding<Bool>, title: String, message: String, confirmTitle: String,
                       destructive: Bool = false, symbol: String = "v.warn", action: @escaping () -> Void) -> some View {
        modifier(ConfirmDialogModifier(isPresented: isPresented, title: title, message: message, confirmTitle: confirmTitle,
                                       destructive: destructive, symbol: symbol, action: action))
    }
}

struct ConfirmDialogView: View {
    @EnvironmentObject var state: AppState
    let request: ConfirmRequest

    var body: some View {
        let page = state.section
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { state.confirmRequest = nil }
            VStack(spacing: 20) {
                SolidIcon(symbol: request.symbol, tint: request.destructive ? Color(hex: 0xFF6B7A) : page.palette.glow, size: 44)
                VStack(spacing: 6) {
                    Text(request.title).font(.vt(size: 17, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text(request.message).font(.vt(size: 13)).foregroundStyle(Color.white.opacity(0.6)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { state.confirmRequest = nil } label: { Text(tr("Hủy")).frame(maxWidth: .infinity) }
                        .buttonStyle(SecondaryButtonStyle()).controlSize(.large)
                    Button {
                        let run = request.action
                        state.confirmRequest = nil
                        run()
                    } label: { Text(request.confirmTitle).frame(maxWidth: .infinity) }
                        .modifier(ConfirmButtonStyle(destructive: request.destructive)).controlSize(.large)
                }
            }
            .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 22).frame(width: 340)
            .background(Color(white: 0.11).opacity(0.96))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
        .transition(.opacity)
        .accessibilityAddTraits(.isModal)
    }
}

struct ConfirmButtonStyle: ViewModifier {
    let destructive: Bool
    func body(content: Content) -> some View {
        if destructive { content.buttonStyle(DangerButtonStyle()) } else { content.buttonStyle(PrimaryButtonStyle()) }
    }
}

// MARK: - Chuyển tiếp mượt

extension View {
    /// Mọi thay đổi trạng thái làm bố cục đổi (hero ↔ kết quả, loading ↔ nội dung…) phải đi qua một hoạt ảnh,
    /// nếu không giao diện sẽ "nháy". Dùng thống nhất một đường cong để cả app chuyển động đồng bộ.
    func smooth<V: Equatable>(_ value: V, _ duration: Double = 0.28) -> some View {
        animation(.easeInOut(duration: duration), value: value)
    }
}

/// Nút tròn kính cùng chiều cao với nút chính (36pt): dùng cạnh nút chính cho hành động phụ như thoát.
struct GlassIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 36
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.vt(size: diameter * 0.4, weight: .semibold))
            .foregroundStyle(Color.white.opacity(hover ? 1 : 0.92))
            .frame(width: diameter, height: diameter)
            .background(
                ZStack {
                    Circle().fill(Color.black.opacity(0.16))
                    Circle().fill(LinearGradient(colors: [Color.white.opacity(pressed ? 0.26 : (hover ? 0.30 : 0.20)),
                                                          Color.white.opacity(pressed ? 0.12 : (hover ? 0.14 : 0.08))],
                                                 startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(hover ? 0.7 : 0.5), Color.white.opacity(0.12)],
                                                          startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(enabled ? 0.28 : 0), radius: hover ? 10 : 6, y: 3)
            .scaleEffect(pressed ? 0.95 : 1).opacity(enabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }.pointerCursor()
    }
}

/// Nút nhỏ dạng viên thuốc kính, cùng chiều cao với `ChipPicker` (đặt cạnh nhau trên thanh lọc): icon + chữ trắng.
struct PillActionStyle: ButtonStyle {
    @ViewState private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.vt(size: 12.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(pressed ? 0.20 : (hover ? 0.15 : 0.08))))
            .overlay(Capsule().strokeBorder(Color.white.opacity(hover ? 0.30 : 0.18), lineWidth: 1))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: hover)
            .onHover { hover = $0 }.pointerCursor()
    }
}

/// Nút rất nhỏ (cao 22pt) dùng trong các ô gọn như popover: viền kính, chữ 11.5pt, không bao giờ xuống dòng.
struct MiniButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.Text.primary)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.28 : 0.16)))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.6)
            .pointerCursor()
    }
}
