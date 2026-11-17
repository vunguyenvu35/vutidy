import SwiftUI
import AppKit
import CoreKit
import Modules

/// Panel thông tin nằm cạnh popover thanh menu (bên trái), mở khi bấm "Giải phóng" ở ô Ổ đĩa / Bộ nhớ.
@MainActor
final class PopoverDetailPanel {
    static let shared = PopoverDetailPanel()
    enum Kind { case memory, disk }

    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    static let width: CGFloat = 372

    static var popoverWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.canBecomeMain && String(describing: type(of: $0)).contains("MenuBarExtra") }
    }

    func show(_ kind: Kind, state: AppState) {
        guard let pop = Self.popoverWindow else { return }
        close()
        let host = NSHostingView(rootView: DetailPanelView(kind: kind, state: state, close: { [weak self] in self?.close() })
            .environmentObject(state).preferredColorScheme(.dark))
        // Cao đúng bằng nội dung, bám cạnh trên của popover.
        let h = host.fittingSize.height
        let p = NSPanel(contentRect: NSRect(x: pop.frame.minX - Self.width - 10, y: pop.frame.maxY - h, width: Self.width, height: h),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.level = pop.level; p.isFloatingPanel = true; p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.orderFrontRegardless()
        panel = p
        // Đóng cùng popover: khi popover mất phím và đã ẩn thì đóng panel.
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: pop, queue: .main) { [weak self, weak pop] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { if pop?.isVisible != true { self?.close() } }
            }
        }
    }

    func close() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        panel?.orderOut(nil); panel = nil
    }
}

private struct DetailPanelView: View {
    let kind: PopoverDetailPanel.Kind
    @ObservedObject var state: AppState
    let close: () -> Void
    @ViewState private var apps: [Optimization.AppMemory] = []
    @ViewState private var loadedApps = false
    @ViewState private var breakdown = SystemMonitor.memoryBreakdown()
    @ViewState private var purging = false
    @ViewState private var cats: [DiskBreakdown.Kind: Int64]?
    @ViewState private var smart: Bool?
    @ViewState private var smartLoaded = false
    @ViewState private var trash: Int64?

    private let cyan = Color(red: 0.30, green: 0.78, blue: 1.0)
    private let blue = Color(red: 0.42, green: 0.55, blue: 1.0)
    private let violet = Color(red: 0.72, green: 0.52, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if kind == .memory { memory } else { disk }
        }
        .padding(14)
        .frame(width: PopoverDetailPanel.width, alignment: .top)
        .background(ZStack { PageBackground(page: .smartScan); Color.black.opacity(0.18) })
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .task { await reload() }
    }

    func reload() async {
        breakdown = SystemMonitor.memoryBreakdown()
        if kind == .memory { apps = await Optimization.memoryByApp(limit: 5); loadedApps = true; return }
        async let t = DiskBreakdown.trashSize()
        async let sm = DiskBreakdown.smartVerified()
        smart = await sm; smartLoaded = true
        trash = await t
        cats = await DiskBreakdown.measure()
    }

    static var volumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? tr("Ổ đĩa")
    }

    var header: some View {
        HStack(spacing: 8) {
            IconTile(symbol: kind == .memory ? "v.ram" : "v.drive",
                     tint: (kind == .memory ? Page.optimization : Page.systemJunk).palette.glow, size: 24)
            Text(kind == .memory ? tr("Bộ nhớ") : Self.volumeName).font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Button { close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                .buttonStyle(GlassIconButtonStyle(diameter: 24))
        }
    }

    // MARK: Bộ nhớ

    var memory: some View {
        let m = state.snapshot?.memory
        let total = Double(max(1, m?.total ?? 1))
        let b = breakdown
        let parts: [(String, Int64, Color)] = [(tr("Đang hoạt động"), b.active, cyan), ("Wired", b.wired, blue), (tr("Đã nén"), b.compressed, violet)]
        let usedFraction = m.map { 1 - Double($0.available) / total } ?? 0
        let pressure = m?.pressure ?? .normal
        let pc: Color = pressure == .normal ? Theme.Signal.base : (pressure == .warning ? Theme.Review.base : Theme.danger)
        let ptext: String = pressure == .normal ? tr("Bình thường") : (pressure == .warning ? tr("Cao") : tr("Rất cao"))
        let pnote: String = pressure == .normal ? tr("Chưa cần dọn bộ nhớ.") : (pressure == .warning ? tr("Nên thoát bớt app không cần.") : tr("Hãy thoát app ngay."))
        return VStack(alignment: .leading, spacing: 12) {
            overview(parts: parts.map { (Double($0.1) / total, $0.2) }, value: m.map { ByteFormat.string($0.available) } ?? "—",
                     caption: tr("khả dụng"), legend: parts.map { ($0.0, ByteFormat.string($0.1), $0.2) },
                     footer: (tr("Tổng"), ByteFormat.string(m?.total ?? 0)))
            HStack(spacing: 10) {
                statCard(tr("Áp lực"), badge: ptext, badgeColor: pc, meter: usedFraction, meterColor: pc, note: pnote)
                statCard(tr("Tệp swap"), badge: ByteFormat.string(m?.swapUsed ?? 0), badgeColor: Theme.Text.primary, meter: nil, meterColor: .clear,
                         note: tr("Phần ổ đĩa dùng thay RAM khi bị đầy."))
            }
            consumers
            Button { Task { await purge() } } label: {
                HStack(spacing: 7) {
                    if purging { VSpinner(size: 13, lineWidth: 2) } else { Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)) }
                    Text(purging ? tr("Đang chạy…") : tr("Giải phóng bộ nhớ"))
                }
            }.buttonStyle(PrimaryButtonStyle(fullWidth: true)).disabled(purging)
                .help(tr("Xóa cache bộ nhớ (purge). Cần quyền admin."))
        }
    }

    var consumers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("Ngốn bộ nhớ nhất")).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(apps.enumerated()), id: \.element.id) { i, a in
                appRow(a)
                if i < apps.count - 1 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52) }
            }
            if apps.isEmpty {
                HStack(spacing: 8) { if !loadedApps { VSpinner(size: 14, lineWidth: 2) }; Text(loadedApps ? "—" : tr("Đang tính dung lượng…")) }
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity, minHeight: 40 * 5)
            }
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 40 * 5 + 40, alignment: .topLeading)
        .glassSurface(radius: 14, strong: false)
    }

    func appRow(_ a: Optimization.AppMemory) -> some View {
        let app = NSRunningApplication(processIdentifier: a.id)
        let canQuit = app.map { $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" && $0.processIdentifier != getpid() } ?? false
        let heavy = a.footprint > 2 << 30
        return HStack(spacing: 10) {
            AppIconView(image: app?.icon, fallback: "terminal.fill", size: 26)
            Text(a.name).font(.vt(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 8)
            Text(ByteFormat.string(a.footprint)).font(.vt(size: 12.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(heavy ? Theme.Review.base : Theme.Text.secondary)
            Group {
                if canQuit {
                    Button(tr("Thoát")) { app?.terminate(); Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await reload() } }
                        .buttonStyle(MiniButtonStyle())
                } else { Color.clear }
            }.frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    func purge() async {
        purging = true
        let r = await Optimization.purgeMemory()
        if r.ok { state.notify(tr("Đã xóa cache bộ nhớ")) } else { state.notify(trf("Lỗi: %@", r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)), .error) }
        purging = false
        state.pollSystem()
        await reload()
    }

    // MARK: Ổ đĩa

    func catColor(_ k: DiskBreakdown.Kind) -> Color {
        switch k {
        case .audio: return Color(red: 1.00, green: 0.50, blue: 0.95)
        case .applications: return Color(red: 1.00, green: 0.42, blue: 0.50)
        case .images: return Color(red: 1.00, green: 0.85, blue: 0.45)
        case .documents: return Color(red: 0.50, green: 0.56, blue: 1.00)
        case .movies: return Color(red: 0.30, green: 0.90, blue: 0.75)
        }
    }

    func catName(_ k: DiskBreakdown.Kind) -> String {
        switch k {
        case .audio: return "Audio"; case .applications: return tr("Ứng dụng"); case .images: return tr("Hình ảnh")
        case .documents: return tr("Tài liệu"); case .movies: return tr("Phim")
        }
    }

    var disk: some View {
        let d = state.snapshot?.disk
        let total = Double(max(1, d?.total ?? 1))
        let free = Double(d?.available ?? 0), purgeable = Double(d?.purgeable ?? 0)
        let used = max(0, total - free - purgeable)
        // Các loại đo được, lớn trước; phần còn lại của dung lượng đã dùng là "Khác"; vùng trống để trong nền vòng.
        let measured = (cats ?? [:]).filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let other = max(0, used + purgeable - measured.reduce(0) { $0 + Double($1.value) })
        var legend: [(String, String, Color)] = measured.map { (catName($0.key), ByteFormat.string($0.value), catColor($0.key)) }
        var parts: [(Double, Color)] = measured.map { (Double($0.value) / total, catColor($0.key)) }
        if cats == nil { // đang đo: hiện tổng đã dùng một màu để vòng không trống
            legend = [(tr("Đã dùng"), ByteFormat.string(Int64(used)), violet), ("Purgeable", ByteFormat.string(Int64(purgeable)), cyan)]
            parts = [(used / total, violet), (purgeable / total, cyan)]
        } else {
            legend.append((tr("Khác"), ByteFormat.string(Int64(other)), Color.white.opacity(0.9))); parts.append((other / total, Color.white.opacity(0.9)))
        }
        return VStack(alignment: .leading, spacing: 12) {
            overview(parts: parts, value: d.map { ByteFormat.string($0.availableImportant) } ?? "—", caption: tr("trống"),
                     legend: legend, footer: (cats == nil ? tr("Đang phân tích…") : tr("Tổng"), ByteFormat.string(d?.total ?? 0)))
            HStack(spacing: 10) {
                statCard(tr("Sức khỏe"), badge: smartLoaded ? (smart == true ? tr("Tốt") : (smart == false ? tr("Có lỗi") : "—")) : "…",
                         badgeColor: smart == false ? Theme.danger : Theme.Signal.base, meter: nil, meterColor: .clear,
                         note: smart == true ? tr("SMART báo ổ đĩa hoạt động bình thường.") : (smart == false ? tr("SMART báo ổ đĩa sắp hỏng, hãy sao lưu ngay.") : tr("Ổ đĩa này không báo trạng thái SMART.")),
                         minHeight: 0)
                statCard("Purgeable", badge: ByteFormat.string(d?.purgeable ?? 0), badgeColor: cyan, meter: nil, meterColor: .clear,
                         note: tr("macOS tự lấy lại khi cần (cache, snapshot Time Machine)."), minHeight: 0)
            }
            trashCard
            HStack(spacing: 8) {
                Button { go(.systemJunk) } label: {
                    HStack(spacing: 7) { Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)); Text(tr("Dọn rác hệ thống")) }
                }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                Button { go(.spaceLens) } label: { Text("Space Lens") }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        }
    }

    var trashCard: some View {
        let size = trash ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "trash").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Thùng rác")).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                Text(trash == nil ? tr("Đang tính dung lượng…") : (size == 0 ? tr("Trống") : trf("Đang chứa %@", ByteFormat.string(size))))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            }
            Spacer()
            Button { go(.trash) } label: { Text(tr("Giải phóng")) }.buttonStyle(MiniButtonStyle()).disabled(size == 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12).glassSurface(radius: 14, strong: false)
    }

    func go(_ page: Page) {
        state.section = page; state.showMainWindow(); close(); AppDelegate.closeMenuBarPopover()
    }

    // MARK: Thành phần

    /// Thẻ tổng quan: vòng đo bên trái, chú thích bên phải, dòng tổng ở cuối.
    func overview(parts: [(Double, Color)], value: String, caption: String, legend: [(String, String, Color)], footer: (String, String)) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                ring(parts, value: value, caption: caption)
                VStack(alignment: .leading, spacing: legend.count > 3 ? 7 : 9) {
                    ForEach(legend.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle().fill(legend[i].2).frame(width: 8, height: 8)
                            if legend.count > 3 {   // nhiều mục: một dòng mỗi mục (tên · dung lượng)
                                Text(legend[i].0).font(.vt(size: 12)).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(legend[i].1).font(.vt(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white).lineLimit(1)
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(legend[i].0).font(.vt(size: 11.5)).foregroundStyle(Theme.Text.secondary)
                                    Text(legend[i].1).font(.vt(size: 13.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Text(footer.0).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Spacer()
                Text(footer.1).font(.vt(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
            }
        }
        .padding(14).frame(maxWidth: .infinity).glassSurface(radius: 14, strong: false)
    }

    func ring(_ parts: [(Double, Color)], value: String, caption: String) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 11)
            ForEach(parts.indices, id: \.self) { i in
                let start = parts[..<i].reduce(0) { $0 + $1.0 }
                let end = min(1, start + max(0, parts[i].0))
                if end - start > 0.012 {
                    Circle().trim(from: start + 0.004, to: end - 0.004)
                        .stroke(parts[i].1, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: 0) {
                Text(value).font(.vt(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(caption).font(.vt(size: 11)).foregroundStyle(Theme.Text.secondary)
            }.padding(.horizontal, 18)
        }
        .padding(6).frame(width: 128, height: 128)
    }

    func statCard(_ title: String, badge: String, badgeColor: Color, meter: Double?, meterColor: Color, note: String, minHeight: CGFloat = 112) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
            Text(badge).font(.vt(size: 17, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(badgeColor).lineLimit(1).minimumScaleFactor(0.7)
            if let meter { MeterBar(value: meter, color: meterColor, height: 5) }
            Text(note).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading).glassSurface(radius: 14, strong: false)
    }
}
