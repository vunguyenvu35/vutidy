import SwiftUI
import AppKit
import CoreKit
import Modules

/// Màn Smart Scan theo mockup "1 · Smart Scan": thẻ hero + thẻ ổ đĩa, rồi dải 5 thẻ module xếp quạt (rê chuột để nâng thẻ).
/// Dùng chung cho mọi trạng thái — chưa quét, đang quét, đang dọn, đã quét — chỉ khác nội dung hero, thẻ ổ đĩa và chân thẻ module.
struct SmartScanDashboard: View {
    @EnvironmentObject var state: AppState
    /// Bấm nút Dọn (hộp thoại xác nhận do `SmartScanView` giữ).
    var onClean: () -> Void = {}
    /// Bảng "Sẽ dọn những gì" khi đã có mục để dọn.
    var details: AnyView? = nil
    @ViewState private var hovered: Int?

    enum Phase { case idle, scanning, cleaning, done }

    private enum P {
        static let accent = Color(hex: 0x6E5BEA)
        static let accentText = Color(hex: 0xB4A7FF)
        static let muted = Color(hex: 0x8E8E97)
        static let body = Color(hex: 0xA1A1AA)
        static let text = Color(hex: 0xD4D4D8)
        static let track = Color(hex: 0x2A2A30)
        static let cardFill = Color.white.opacity(0.05)
        static let cardBorder = Color.white.opacity(0.06)
        static let ok = Color(hex: 0x30D158)
        static let attention = Color(hex: 0xF5B657)
        static let reclaim = Color(hex: 0x4FD1C5)
    }

    struct Module {
        let title: String, desc: String, symbol: String, color: UInt32, rotation: Double
    }

    let modules: [Module] = [
        .init(title: tr("Dọn dẹp"), desc: tr("Rác hệ thống, cache dev và Thùng rác"), symbol: "tray.full", color: 0x0A84FF, rotation: -26),
        .init(title: tr("Bảo vệ"), desc: tr("Malware, adware và mục persistence"), symbol: "shield", color: 0x30D158, rotation: -13),
        .init(title: tr("Hiệu năng"), desc: tr("Mục đăng nhập và tiến trình nền"), symbol: "bolt", color: 0xFF9F0A, rotation: 0),
        .init(title: tr("Ứng dụng"), desc: tr("App lỗi thời và file còn sót"), symbol: "arrow.down.circle", color: 0xFF375F, rotation: 13),
        .init(title: tr("File lớn & cũ"), desc: tr("File lớn bạn đã không mở nhiều tháng"), symbol: "doc.badge.clock", color: 0xF5B400, rotation: 26),
    ]

    var phase: Phase {
        if !state.cleaning.isEmpty { return .cleaning }
        if state.smartScanning { return .scanning }
        return state.smart == nil ? .idle : .done
    }
    var cleanable: Int64 { state.smart?.cleanableBytes ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            ViewThatFits(in: .horizontal) {
                RatioHStack(ratio: 1.15, spacing: 20) { heroCard; diskCard }
                VStack(spacing: 20) { heroCard; diskCard }
            }
            if let details { details }
            checks
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .smooth(phase == .idle).smooth(phase == .done).smooth(cleanable)
    }

    // MARK: Header

    var header: some View {
        HStack(spacing: 12) {
            Text("Smart Scan").font(.vt(size: 15, weight: .semibold)).foregroundStyle(Theme.Text.primary)
            // Khi đã có kết quả, thời điểm quét đã nằm ở dòng nhỏ trên tiêu đề hero — không lặp lại ở đây.
            if state.smart == nil {
                Text(tr("Quét lần cuối: chưa bao giờ")).font(.vt(size: 12)).foregroundStyle(P.muted)
            }
            Spacer()
        }
    }

    // MARK: Hero

    var eyebrow: String {
        switch phase {
        case .idle: return tr("Chưa quét")
        case .scanning: return tr("Đang quét…")
        case .cleaning: return tr("Đang dọn…")
        case .done: return state.smart.map { trf("Quét lúc %@", $0.date.formatted(date: .abbreviated, time: .shortened)) } ?? ""
        }
    }

    var heroTitle: String {
        switch phase {
        case .idle: return tr("Kiểm tra toàn bộ Mac\ntrong một lần")
        case .scanning: return tr("Đang kiểm tra Mac của bạn")
        case .cleaning: return tr("Đang chuyển mục an toàn vào Quarantine")
        case .done: return cleanable == 0 ? tr("Mac của bạn đang gọn gàng") : trf("Mac của bạn có thể lấy lại %@", ByteFormat.string(cleanable))
        }
    }

    var heroBody: String? {
        switch phase {
        case .idle: return tr("Tìm rác, cache dev, mối đe dọa và điểm gây chậm. Bạn xem lại mọi thứ trước khi có gì bị xóa.")
        case .done: return cleanable > 0 ? tr("Chỉ mục an toàn. Mục \"Cần xem lại\" không bị đụng tới.") : tr("Không có mục an toàn nào cần dọn lúc này.")
        case .scanning, .cleaning: return nil
        }
    }

    var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow).textCase(.uppercase).tracking(0.3).font(.vt(size: 12, weight: .semibold)).foregroundStyle(P.accentText)
            Text(heroTitle).font(.vt(size: 28, weight: .bold)).tracking(-0.5).lineSpacing(2).foregroundStyle(Theme.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let body = heroBody {
                Text(body).font(.vt(size: 14)).lineSpacing(3).foregroundStyle(P.body).frame(maxWidth: 420, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if phase == .scanning || phase == .cleaning {
                HStack(spacing: 10) {
                    VSpinner(size: 18)
                    Text(phase == .cleaning ? tr("Đang dọn…") : (state.status["smart"] ?? tr("Đang quét…")))
                        .font(.vt(size: 13)).foregroundStyle(P.body).lineLimit(1)
                }
            }
            if phase == .idle && state.autoCleanAfterScan {
                Label(tr("Dọn tự động đang bật: quét xong, mục An toàn hoàn tác được sẽ vào Quarantine."), systemImage: "bolt.fill")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Review.text).fixedSize(horizontal: false, vertical: true)
            }
            if phase == .done && cleanable > 0 {
                Label(trf("Hoàn tác được trong %@ ngày", "\(state.retentionDays)"), systemImage: "arrow.uturn.backward")
                    .font(Theme.Font.caption).foregroundStyle(P.body)
            }
            if phase == .idle || phase == .done {
                ViewThatFits(in: .horizontal) { actions(stacked: false); actions(stacked: true) }.padding(.top, 8)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "shield").font(.system(size: 12))
                Text(tr("Mục đã gỡ vào Quarantine và có thể khôi phục."))
            }
            .font(.vt(size: 12)).foregroundStyle(P.muted).padding(.top, 12)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.cardFill)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(RadialGradient(colors: [P.accent.opacity(0.32), .clear], center: .topLeading, startRadius: 0, endRadius: 380))
            }
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.cardBorder))
    }

    // MARK: Nút

    func primaryButton(_ title: String, icon: String? = nil, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(title).font(.vt(size: 14, weight: .semibold)).lineLimit(1).fixedSize()
                if let shortcut {
                    Text(shortcut).font(.vt(size: 11, weight: .medium)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.18)))
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(P.accent))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(PlainPointerStyle()).keyboardShortcut(.return, modifiers: .command)
    }

    func secondaryButton(_ title: String, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.vt(size: 13, weight: .medium)).lineLimit(1).fixedSize().foregroundStyle(P.text)
                .padding(.horizontal, 14).frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(PlainPointerStyle()).help(help ?? "")
    }

    func linkButton(_ title: String, icon: String? = nil, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.vt(size: 13, weight: .medium)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(P.accentText).padding(.horizontal, 6).frame(height: 40)
        }
        .buttonStyle(PlainPointerStyle()).help(help ?? "")
    }

    @ViewBuilder func actions(stacked: Bool) -> some View {
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            if phase == .done && cleanable > 0 {
                primaryButton(trf("Dọn %@", ByteFormat.string(cleanable)), shortcut: "⌘↵") { onClean() }
                secondaryButton(tr("Xem trước (dry-run)")) { Task { await state.cleanSmart(mode: .dryRun) } }
                linkButton(tr("Quét lại"), icon: "arrow.clockwise") { Task { await state.runSmartScan() } }
                if !state.autoCleanAfterScan {
                    linkButton(tr("Quét và dọn luôn"), help: scanAndCleanHelp) { Task { await state.runSmartScan(autoClean: true) } }
                }
            } else if phase == .done {
                primaryButton(tr("Quét lại"), icon: "arrow.clockwise", shortcut: "⌘↵") { Task { await state.runSmartScan() } }
                if !state.autoCleanAfterScan {
                    secondaryButton(tr("Quét và dọn luôn"), help: scanAndCleanHelp) { Task { await state.runSmartScan(autoClean: true) } }
                }
                linkButton(tr("Cài đặt quét…")) { state.settingsOpen = true }
            } else {
                primaryButton(state.autoCleanAfterScan ? tr("Quét và dọn") : tr("Bắt đầu Smart Scan"), icon: "sparkles", shortcut: "⌘↵") {
                    Task { await state.runSmartScan() }
                }
                // "Quét và dọn luôn" là nút viền ngay cạnh nút chính (không phải link nhỏ) để dễ thấy.
                if !state.autoCleanAfterScan {
                    secondaryButton(tr("Quét và dọn luôn"), help: scanAndCleanHelp) { Task { await state.runSmartScan(autoClean: true) } }
                }
                linkButton(tr("Cài đặt quét…")) { state.settingsOpen = true }
            }
        }
    }

    var scanAndCleanHelp: String {
        tr("Quét xong tự chuyển các mục An toàn, hoàn tác được vào Quarantine. Mục không hoàn tác được vẫn chờ bạn.")
    }

    // MARK: Ổ đĩa

    static var volumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
    }

    var diskCard: some View {
        let d = state.snapshot?.disk
        let total = Double(max(1, d?.total ?? 1))
        let free = Double(d?.available ?? 0), purge = Double(d?.purgeable ?? 0)
        let reclaim = min(Double(cleanable), max(0, total - free - purge))
        let used = max(0, total - free - purge - reclaim)
        var seg: [(String, Color, Double)] = [(tr("Đã dùng"), Color(hex: 0x9B87F5), used)]
        if reclaim > 0 { seg.append((tr("Có thể dọn"), P.reclaim, reclaim)) }
        seg += [(tr("Có thể thu hồi"), Color(hex: 0xF5B657), purge), (tr("Trống"), P.track, free)]
        let bar = seg.filter { $0.1 != P.track }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.volumeName).font(.vt(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                Spacer()
                Text(d.map { ByteFormat.string($0.total) } ?? "—").font(.vt(size: 12)).foregroundStyle(P.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.map { ByteFormat.string($0.availableImportant) } ?? "—")
                    .font(.vt(size: 32, weight: .bold)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.Text.primary)
                if phase == .done && cleanable > 0 {
                    Text(trf("→ %@ sau khi dọn", ByteFormat.string((d?.availableImportant ?? 0) + cleanable)))
                        .font(.vt(size: 13, weight: .medium)).foregroundStyle(P.reclaim)
                } else {
                    Text(tr("còn trống")).font(.vt(size: 13)).foregroundStyle(P.body)
                }
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(Array(bar.enumerated()), id: \.offset) { _, s in
                        Rectangle().fill(s.1).frame(width: max(0, (g.size.width - 6) * s.2 / total))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(P.track)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }.frame(height: 10).accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(Array(seg.enumerated()), id: \.offset) { _, s in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(s.1).frame(width: 8, height: 8)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(s.1 == P.track ? 0.15 : 0)))
                        Text(s.0).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(d == nil ? "—" : ByteFormat.string(Int64(s.2))).foregroundStyle(P.muted)
                    }.font(.vt(size: 12)).foregroundStyle(P.text)
                }
            }
            Spacer(minLength: 0)
            Button { state.section = .spaceLens } label: {
                Text(tr("Mở Space Lens →")).font(.vt(size: 12, weight: .medium)).foregroundStyle(P.accentText)
            }.buttonStyle(PlainPointerStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(P.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(P.cardBorder))
    }

    // MARK: Dải thẻ module

    var checks: some View {
        let groups = CareGroups(state: state).groups
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(phase == .done ? tr("Kết quả theo nhóm") : tr("Smart Scan kiểm tra gì"))
                    .font(.vt(size: 14, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                Text(phase == .done ? tr("Bấm một thẻ để xem chi tiết") : trf("%@ mục · thường 1–3 phút", "\(modules.count)"))
                    .font(.vt(size: 12)).foregroundStyle(P.muted)
            }
            GeometryReader { geo in
                let layout = FanHitTest.Layout(rotations: modules.map(\.rotation))
                ZStack(alignment: .top) {
                    ForEach(Array(modules.enumerated()), id: \.offset) { i, m in
                        let on = hovered == i
                        let dim = hovered != nil && !on
                        let g = groups.indices.contains(i) ? groups[i] : nil
                        CheckCard(module: m, hovered: on, status: g?.status ?? .pending,
                                  summary: g.flatMap { $0.status == .pending ? nil : $0.summary },
                                  busy: (state.smartScanning || state.malwareScanning) && (g?.status ?? .pending) == .pending)
                            .scaleEffect(on ? 1.06 : 1)
                            .offset(y: on ? -34 : 0)
                            .rotationEffect(.degrees(m.rotation), anchor: UnitPoint(x: 0.5, y: 3))
                            .brightness(dim ? -0.2 : 0).saturation(dim ? 0.8 : 1)
                            .zIndex(on ? 10 : Double(i))
                            .padding(.top, 30)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { if let g { state.section = g.review } }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                // Hit-test bằng hình học thật của dải thẻ, thẻ đang nâng được giữ chừng nào con trỏ còn trên nó (xem FanHitTest).
                .overlay(
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let p):
                                let hit = FanHitTest.card(at: p, width: geo.size.width, current: hovered, layout: layout)
                                if hit != hovered { hovered = hit }
                                (hit != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
                            case .ended:
                                hovered = nil
                                NSCursor.arrow.set()
                            }
                        }
                        .gesture(SpatialTapGesture().onEnded { v in
                            if let i = FanHitTest.card(at: v.location, width: geo.size.width, current: hovered, layout: layout),
                               groups.indices.contains(i) {
                                state.section = groups[i].review
                            }
                        })
                )
            }
            .frame(height: 390)
            // Lò xo có thể ngắt giữa chừng và đổi hướng êm khi con trỏ chuyển sang thẻ khác.
            .animation(state.reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.8), value: hovered)
        }
    }
}

/// Một thẻ module 232×236: ô icon gradient, tiêu đề, mô tả hoặc kết quả, trạng thái và mũi tên hiện khi rê chuột.
private struct CheckCard: View {
    let module: SmartScanDashboard.Module
    let hovered: Bool
    let status: CareGroups.Status
    /// Kết quả của nhóm (đã quét); nil thì hiện mô tả cố định.
    let summary: String?
    let busy: Bool
    private var c: Color { Color(hex: module.color) }

    private var dot: Color {
        switch status {
        case .ok: return Color(hex: 0x30D158)
        case .attention: return Color(hex: 0xF5B657)
        case .pending: return Color(hex: 0x8E8AA8)
        }
    }
    private var label: String {
        if busy { return tr("Đang quét…") }
        switch status {
        case .ok: return tr("Ổn")
        case .attention: return tr("Cần chú ý")
        case .pending: return tr("Chưa quét")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Glyph(symbol: module.symbol, size: 24, stroke: .white, fill: .white, lineWidth: 1.9)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [c, c.mix(with: .black, by: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: c.opacity(0.45), radius: 11, y: 10)
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
            Text(module.title).font(.vt(size: 18, weight: .bold)).tracking(-0.2).foregroundStyle(.white).padding(.top, 10)
            Text(summary ?? module.desc).font(.vt(size: 13)).lineSpacing(3)
                .foregroundStyle(summary == nil ? Color(hex: 0xBDB9D2) : .white.opacity(0.92))
                .lineLimit(4).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if busy { VSpinner(size: 12, lineWidth: 1.5) } else { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(label).font(.vt(size: 12)).foregroundStyle(Color(hex: 0xABA7C2)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(hovered ? c : Color.white.opacity(0.08)))
                    .opacity(hovered ? 1 : 0).offset(x: hovered ? 0 : -8)
            }
        }
        .padding(22)
        .frame(width: 232, height: 236, alignment: .topLeading)
        .background(
            ZStack {
                LinearGradient(colors: [Color(hex: 0x2B2452), Color(hex: 0x18142E)], startPoint: .top, endPoint: .bottom)
                RadialGradient(stops: [.init(color: c.opacity(0.38), location: 0), .init(color: .clear, location: 0.62)],
                               center: .topLeading, startRadius: 0, endRadius: 250)
            }
        )
        .overlay(alignment: .bottomTrailing) {
            Glyph(symbol: module.symbol, size: 130, stroke: c.opacity(0.12), fill: c.opacity(0.12), lineWidth: 1.25)
                .offset(x: 22, y: 26).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(hovered ? c : Color.white.opacity(0.10), lineWidth: hovered ? 1.5 : 1))
        .shadow(color: hovered ? c.opacity(0.42) : .black.opacity(0.5), radius: 26, y: 22)
    }
}

/// Hai cột theo tỉ lệ `ratio : 1` (hero rộng hơn thẻ ổ đĩa), cao bằng nhau. Dưới ~760pt nên chuyển sang xếp dọc.
private struct RatioHStack: Layout {
    var ratio: CGFloat
    var spacing: CGFloat
    private let idealWidth: CGFloat = 760

    private func widths(_ total: CGFloat) -> (CGFloat, CGFloat) {
        let avail = total - spacing
        let first = avail * ratio / (ratio + 1)
        return (first, avail - first)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let w = proposal.width ?? idealWidth
        let (w1, w2) = widths(w)
        let h = max(subviews[0].sizeThatFits(.init(width: w1, height: nil)).height,
                    subviews[1].sizeThatFits(.init(width: w2, height: nil)).height)
        // Hẹp hơn mức lý tưởng thì báo không vừa để ViewThatFits chọn phương án xếp dọc.
        return CGSize(width: max(w, idealWidth), height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (w1, w2) = widths(bounds.width)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: .init(width: w1, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + w1 + spacing, y: bounds.minY), anchor: .topLeading, proposal: .init(width: w2, height: bounds.height))
    }
}

private extension Color {
    /// Trộn với một màu khác (tương đương `color-mix(in srgb, c 55%, #000)` khi `by` = 0.45).
    func mix(with other: Color, by amount: Double) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black, b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB, red: a.redComponent * (1 - amount) + b.redComponent * amount,
                     green: a.greenComponent * (1 - amount) + b.greenComponent * amount,
                     blue: a.blueComponent * (1 - amount) + b.blueComponent * amount)
    }
}
