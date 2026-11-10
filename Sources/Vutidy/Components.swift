import SwiftUI
import CoreKit

struct SafetyBadge: View {
    let level: SafetyLevel
    var body: some View {
        let (text, color): (String, Color) = switch level {
        case .safe: (tr("An toàn"), Theme.Signal.text)
        case .review: (tr("Cần xem lại"), Theme.Review.text)
        case .dangerous: (tr("Nguy hiểm"), Theme.danger)
        }
        Text(text).font(Theme.Font.label).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.Text.secondary
    var body: some View {
        Text(text).font(Theme.Font.label).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

struct PageHeader: View {
    @EnvironmentObject var state: AppState
    let caption: String
    let title: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SolidIcon(symbol: state.section.icon, tint: state.section.tint, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.vt(size: 24, weight: .bold)).foregroundStyle(Theme.Text.primary).lineLimit(2)
                Text(caption).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).lineLimit(2)
            }
            Spacer()
            trailing
        }
    }
}

struct CodeBlock: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Text(l).font(Theme.Font.mono)
                    .foregroundStyle(l.hasPrefix("#") ? Theme.Text.tertiary : Theme.Signal.text)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.Bg.code))
    }
}

struct Ring: View {
    struct Segment: Identifiable { let id = UUID(); let value: Double; let color: Color }
    let segments: [Segment]
    var lineWidth: CGFloat = 14
    var body: some View {
        let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
        ZStack {
            Circle().stroke(Color.white.opacity(0.05), lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.element.id) { i, s in
                let start = segments.prefix(i).reduce(0) { $0 + $1.value } / total
                let end = start + s.value / total
                Circle().trim(from: start + 0.004, to: max(start + 0.004, end - 0.004))
                    .stroke(s.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.Signal.base
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                let mx = max(values.max() ?? 1, 0.001)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(values.count - 1), y: g.size.height * (1 - CGFloat(v / mx)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }.stroke(color, lineWidth: 1.5)
        }
    }
}

struct EmptyStateView: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Theme.Signal.base)
            Text(title).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
            Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(48)
    }
}

struct FDABanner: View {
    var message: String = tr("Thiếu Full Disk Access — một số mục (Mail, Photos, Safari) sẽ không quét được.")
    var onDismiss: (() -> Void)? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").foregroundStyle(Theme.Review.base)
            Text(message)
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.primary)
            Spacer()
            // Chạy bằng `swift run` thì không có .app để cấp quyền — chỉ hiện nút khi đang chạy từ bundle.
            if Bundle.main.bundleURL.pathExtension == "app" {
                Button(tr("Hiện app trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    .buttonStyle(SecondaryButtonStyle())
                Button(tr("Khởi động lại Vutidy")) { AppDelegate.relaunch() }
                    .buttonStyle(SecondaryButtonStyle()).help(tr("Sau khi bật quyền trong System Settings, hãy khởi động lại Vutidy để macOS áp dụng."))
            }
            Button(tr("Mở System Settings")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }.buttonStyle(SecondaryButtonStyle())
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(PlainPointerStyle())
                    .foregroundStyle(Theme.Text.secondary).help(tr("Ẩn thông báo"))
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.Review.tint))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Review.base.opacity(0.3)))
    }
}

extension View {
    /// Card không có padding bên trong (nội dung tự quản lý).
    func cardFlat() -> some View { glassSurface(radius: Theme.Radius.card, strong: false) }
}

/// Thay cho `@State`. Trong SDK mới `@State` là macro cần plugin SwiftUIMacros (chỉ có trong Xcode);
/// wrapper này dựa trên `@StateObject` nên build được cả với Command Line Tools.
final class ViewStateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ v: Value) { value = v }
}

@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    @StateObject private var box: ViewStateBox<Value>
    init(wrappedValue: Value) { _box = StateObject(wrappedValue: ViewStateBox(wrappedValue)) }
    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<Value> { Binding(get: { box.value }, set: { box.value = $0 }) }
}

extension Language {
    /// Tên hiển thị trong menu: "Theo hệ thống" được dịch, các ngôn ngữ khác giữ tên bản địa.
    var menuTitle: String { self == .system ? tr("Theo hệ thống") : nativeName }
}

struct LanguageMenu: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Menu {
            ForEach(Language.allCases) { l in
                Button { state.language = l } label: {
                    if state.language == l { Label(l.menuTitle, systemImage: "checkmark") } else { Text(l.menuTitle) }
                }
            }
        } label: {
            Label(L10n.current.nativeName, systemImage: "globe").font(Theme.Font.label)
        }
        .menuStyle(.borderlessButton).fixedSize().pointerCursor()
        .help(tr("Ngôn ngữ"))
    }
}

/// Logo Vutidy vẽ bằng SwiftUI, khớp `docs/assets/brand/logo-mark.svg` (lưới 1024).
struct LogoMark: View {
    var size: CGFloat = 28
    var body: some View {
        Canvas { ctx, sz in
            let k = sz.width / 1024
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: (y + 65) * k) }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: sz), cornerRadius: 228 * k),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x171C25), Color(hex: 0x0A0C10)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: sz.height)))
            var v = Path(); v.move(to: P(292, 282)); v.addLine(to: P(512, 612)); v.addLine(to: P(732, 282))
            let style = StrokeStyle(lineWidth: 92 * k, lineCap: .round, lineJoin: .round)
            var left = ctx; left.clip(to: Path(CGRect(x: 0, y: 0, width: 512 * k, height: sz.height)))
            left.stroke(v, with: .color(Color(hex: 0x5AA9FF)), style: style)
            var right = ctx; right.clip(to: Path(CGRect(x: 512 * k, y: 0, width: 512 * k, height: sz.height)))
            right.stroke(v, with: .color(Color(hex: 0x3DDC97)), style: style)
            ctx.fill(Path(roundedRect: CGRect(x: 437 * k, y: P(0, 262).y, width: 150 * k, height: 92 * k), cornerRadius: 20 * k),
                     with: .color(Color(hex: 0xEDF0F4)))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Vutidy")
    }
}

// MARK: - Con trỏ bàn tay cho mọi vùng bấm được

/// Vùng con trỏ bàn tay do hệ thống quản lý: không bao giờ bị "kẹt" sau khi bấm hoặc đổi trang.
struct PointerRegion: NSViewRepresentable {
    /// Dùng cursor rect của hệ thống: AppKit tự dựng lại sau khi layout/click, không bị nháy về mũi tên.
    final class RegionView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // không chặn chuột/click
        override func resetCursorRects() { addCursorRect(visibleRect, cursor: .pointingHand) }
        override func layout() { super.layout(); window?.invalidateCursorRects(for: self) }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.invalidateCursorRects(for: self) }
    }
    func makeNSView(context: Context) -> RegionView { RegionView() }
    func updateNSView(_ v: RegionView, context: Context) { v.window?.invalidateCursorRects(for: v) }
}

/// Chỉ hiện bàn tay khi vùng đó thật sự bấm được: bỏ qua nếu control bị `.disabled`.
private struct PointerCursorModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.isEnabled) private var envEnabled
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // API chính thức của SwiftUI: con trỏ luôn đúng sau click/re-render.
            content.pointerStyle(enabled && envEnabled ? .link : nil)
        } else {
            content.overlay { if enabled && envEnabled { PointerRegion() } }
        }
    }
}

extension View {
    /// Đổi con trỏ thành bàn tay khi rê chuột lên vùng bấm được (không áp dụng cho control đang disabled).
    func pointerCursor(_ enabled: Bool = true) -> some View { modifier(PointerCursorModifier(enabled: enabled)) }
}

/// Thay cho `.buttonStyle(.plain)`: giữ nguyên giao diện, thêm bàn tay và hiệu ứng nhấn.
struct PlainPointerStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1).pointerCursor()
    }
}
