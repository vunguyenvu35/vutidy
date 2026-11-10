import SwiftUI
import AppKit
import CoreKit
import Modules

/// Popover trên menu bar — cùng ngôn ngữ thiết kế với app: nền gradient, thẻ kính, icon riêng.
struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var devices: [BluetoothDevice] = []
    @ViewState private var speed: SpeedResult?
    @ViewState private var testing = false
    @ViewState private var showAllCards = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = state.snapshot
        ZStack {
            PageBackground(page: .smartScan)
            Color.black.opacity(0.18)
            VStack(alignment: .leading, spacing: 12) {
                header
                recommendations
                realtimeRow
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    diskTile(s); memoryTile(s); cpuTile(s); batteryTile(s); networkTile(s); devicesTile
                }
                footer
            }.padding(14)
        }
        .frame(width: 400)
        .task { devices = await ConnectedDevices.bluetooth() }
        .onAppear { state.openMainWindow = { openWindow(id: "main") } }
    }

    // MARK: Khối chính

    var header: some View {
        HStack(spacing: 8) {
            LogoMark(size: 24)
            Text("Vutidy").font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Spacer()
            Button { state.openSettings(.general); activate() } label: { Image(systemName: "gearshape").font(.system(size: 13)) }
                .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary).help(tr("Mở Cài đặt"))
        }
    }

    @ViewBuilder var recommendations: some View {
        let cards = state.recommendations
        if !cards.isEmpty {
            let shown = showAllCards ? cards : Array(cards.prefix(2))
            VStack(spacing: 8) {
                ForEach(shown) { r in
                    HStack(spacing: 12) {
                        SolidIcon(symbol: r.icon, tint: tint(for: r), size: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(r.title).font(.vt(size: 13, weight: .medium)).foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(r.actionTitle) { state.perform(r.action); activate() }.buttonStyle(SecondaryButtonStyle()).controlSize(.small)
                        }
                        Spacer(minLength: 0)
                        Button { state.dismissStore.dismiss(r); state.pollSystem() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                            .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.tertiary).help(tr("Ẩn thông báo"))
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 14, strong: false)
                }
                if cards.count > 2 {
                    Button(showAllCards ? tr("Thu gọn") : trf("Hiện tất cả (%@)", "\(cards.count)")) { showAllCards.toggle() }
                        .buttonStyle(TextActionStyle(color: Theme.Text.secondary)).frame(maxWidth: .infinity)
                }
            }
        }
    }

    func tint(for r: Recommendation) -> Color {
        switch r.action {
        case .openDevJunk: return Page.devJunk.palette.glow
        case .openSpaceLens, .thinSnapshots, .openCleanup: return Page.systemJunk.palette.glow
        case .openUpdater: return Page.updater.palette.glow
        case .openUninstaller: return Page.uninstaller.palette.glow
        case .openOptimization, .openBattery: return Page.optimization.palette.glow
        case .runDeepScan: return Page.protection.palette.glow
        }
    }

    var realtimeRow: some View {
        HStack(spacing: 12) {
            IconTile(symbol: "v.wifi", tint: state.realtimeOn ? Theme.Signal.base : Theme.Text.secondary, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.realtimeOn ? tr("Real-time bật") : tr("Real-time tắt")).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                Text(state.lastScanned.map { URL(fileURLWithPath: $0).lastPathComponent } ?? tr("Theo dõi file mới")).font(Theme.Font.caption)
                    .foregroundStyle(Theme.Text.secondary).lineLimit(1)
            }
            Spacer()
            SwitchRow(isOn: Binding(get: { state.realtimeOn }, set: { state.setRealtime($0) }), label: "Real-time")
        }
        .padding(.horizontal, 14).padding(.vertical, 10).glassSurface(radius: 14, strong: false)
    }

    // MARK: Ô số liệu — mọi ô cùng một khung (tiêu đề · giá trị · vùng đồ thị · dòng phụ)

    func tile<M: View>(_ title: String, symbol: String, tint: Color, value v: String, sub: String? = nil,
                       @ViewBuilder middle: () -> M) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                IconTile(symbol: symbol, tint: tint, size: 22)
                Text(title).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase).lineLimit(1)
            }.frame(height: 22)
            Text(v).font(.vt(size: 19, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7).frame(height: 28, alignment: .leading).padding(.top, 6)
            middle().frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
            Text(sub ?? " ").font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                .lineLimit(1).minimumScaleFactor(0.75).frame(height: 16, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, maxHeight: 128, alignment: .topLeading)
        .glassSurface(radius: 14, strong: false)
    }

    func diskTile(_ s: SystemSnapshot?) -> some View {
        let d = s?.disk
        let used = d.map { 1 - $0.freeFraction } ?? 0
        return tile(tr("Ổ đĩa"), symbol: "v.drive", tint: Page.systemJunk.palette.glow,
                    value: d.map { ByteFormat.string($0.availableImportant) + tr(" trống") } ?? "—",
                    sub: d.flatMap { $0.purgeable > 0 ? "Purgeable " + ByteFormat.string($0.purgeable) : nil}) {
            MeterBar(value: used, color: used > 0.9 ? Theme.danger : Color.white.opacity(0.9), height: 6)
        }
    }

    func memoryTile(_ s: SystemSnapshot?) -> some View {
        let m = s?.memory
        let used = m.map { 1 - Double($0.available) / Double(max(1, $0.total)) } ?? 0
        let c: Color = (m?.pressure ?? .normal) == .normal ? Color.white.opacity(0.9) : ((m?.pressure ?? .normal) == .warning ? Theme.Review.base : Theme.danger)
        return tile(tr("Bộ nhớ"), symbol: "v.ram", tint: Page.optimization.palette.glow,
                    value: m.map { ByteFormat.string($0.available) + tr(" khả dụng") } ?? "—",
                    sub: m.map { trf("Áp lực: %@ · swap %@", $0.pressure.rawValue, ByteFormat.string($0.swapUsed)) }) {
            MeterBar(value: used, color: c, height: 6)
        }
    }

    func cpuTile(_ s: SystemSnapshot?) -> some View {
        tile("CPU", symbol: "v.chip", tint: Page.updater.palette.glow, value: "\(Int((s?.cpuLoad ?? 0) * 100))%", sub: cpuThermalText(s)) {
            Sparkline(values: state.cpuHistory, color: Color.white.opacity(0.9))
        }
    }

    func batteryTile(_ s: SystemSnapshot?) -> some View {
        let b = s?.battery
        return tile(tr("Pin"), symbol: "v.bolt", tint: Page.protection.palette.glow,
                    value: b.map { "\($0.percent)%" + ($0.charging ? " ⚡︎" : "") } ?? tr("Không có"),
                    sub: b.flatMap { x in x.health.map { trf("Sức khỏe %@%%", "\(Int($0 * 100))") + (x.cycleCount.map { trf(" · %@ chu kỳ", "\($0)") } ?? "") } }) {
            if let b { MeterBar(value: Double(b.percent) / 100, color: b.percent < 20 ? Theme.danger : Color.white.opacity(0.9), height: 6) }
            else { Color.clear }
        }
    }

    func networkTile(_ s: SystemSnapshot?) -> some View {
        tile(tr("Mạng"), symbol: "v.wifi", tint: Page.cloud.palette.glow, value: "↓ " + rate(s?.network.downBytesPerSec),
             sub: speed.map { String(format: "%.0f ↓ / %.0f ↑ Mbps", $0.downMbps, $0.upMbps) } ?? ("↑ " + rate(s?.network.upBytesPerSec))) {
            Button {
                Task { testing = true; if let r = await SpeedTest.run() { speed = r; SpeedTest.append(r) }; testing = false }
            } label: {
                HStack(spacing: 5) {
                    if testing { VSpinner(size: 11, lineWidth: 1.6) } else { Glyph(symbol: "v.optimization", size: 12, stroke: Theme.Text.primary, fill: Theme.Text.primary) }
                    Text(testing ? tr("Đang đo…") : tr("Đo tốc độ"))
                }
            }
            .buttonStyle(MiniButtonStyle()).disabled(testing)
        }
    }

    var devicesTile: some View {
        tile(tr("Thiết bị"), symbol: "v.command", tint: Page.privacy.palette.glow,
             value: devices.isEmpty ? tr("Không có") : "\(devices.count)",
             sub: devices.isEmpty ? nil : devices.map { "\($0.name) \($0.batteryPercent)%" }.joined(separator: " · ")) {
            Color.clear
        }
    }

    var footer: some View {
        HStack {
            primaryButton
            Spacer()
            Button { AppDelegate.quitCompletely() } label: { Image(systemName: "power") }
                .buttonStyle(GlassIconButtonStyle(diameter: 28))
                .help(tr("Thoát hẳn Vutidy"))
                .accessibilityLabel(tr("Thoát hẳn"))
        }
    }

    /// Nút chính đổi theo tình trạng máy: có gợi ý cần dọn (RAM áp lực, purgeable, ổ đầy, dev junk…) thì hiện hành động đó.
    var cleanSuggestion: Recommendation? {
        state.recommendations.first { [.thinSnapshots, .openSpaceLens, .openDevJunk, .openOptimization, .openCleanup].contains($0.action) }
    }

    @ViewBuilder var primaryButton: some View {
        if let r = cleanSuggestion {
            Button { state.perform(r.action); activate() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .bold))
                    Text(footerTitle(for: r))
                }
            }
            .buttonStyle(PrimaryButtonStyle()).controlSize(.small).help(r.title)
        } else {
            Button(tr("Mở Vutidy")) { state.section = .smartScan; activate() }.buttonStyle(PrimaryButtonStyle()).controlSize(.small)
        }
    }

    func footerTitle(for r: Recommendation) -> String {
        switch r.id {
        case "memory-pressure": tr("Giải phóng bộ nhớ")
        case "purgeable": tr("Dọn purgeable")
        case "disk-low": tr("Dọn ổ đĩa")
        case "dev-junk": tr("Dọn Dev Junk")
        default: r.actionTitle
        }
    }

    func rate(_ b: Double?) -> String { ByteFormat.string(Int64(b ?? 0)) + "/s" }

    func activate() { state.showMainWindow() }
}

extension PopoverView {
    /// "🌡 52°C · Bình thường": nhiệt độ cảm biến (nếu đọc được) + trạng thái nhiệt của macOS.
    func cpuThermalText(_ s: SystemSnapshot?) -> String? {
        guard let s else { return nil }
        let label: String
        switch s.thermal {
        case .nominal: label = tr("Bình thường")
        case .fair: label = tr("Hơi nóng")
        case .serious: label = tr("Nóng")
        case .critical: label = tr("Quá nóng")
        @unknown default: label = ""
        }
        if let t = s.cpuTemp { return String(format: "%.0f°C · %@", t, label) }
        return tr("Nhiệt: ") + label
    }
}
