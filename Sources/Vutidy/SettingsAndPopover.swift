import SwiftUI
import AppKit
import CoreKit
import Modules

/// Giữ cạnh TRÊN của cửa sổ MenuBarExtra cố định. Khi nội dung đổi chiều cao (ẩn/hiện thẻ gợi ý), AppKit giữ cạnh dưới
/// và dời cạnh trên, nên popover tụt xuống để hở một khoảng trống dưới thanh menu. Ghi nhớ cạnh trên lúc cửa sổ hiện ra
/// rồi đặt lại vị trí mỗi khi kích thước đổi.
struct PopoverHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Giữ cạnh TRÊN của cửa sổ MenuBarExtra cố định và ép chiều cao cửa sổ bằng đúng chiều cao nội dung.
/// Khi nội dung đổi chiều cao (ẩn/hiện thẻ gợi ý), AppKit giữ cạnh dưới nên popover tụt xuống, để hở một khoảng
/// trống dưới thanh menu. Ở đây ta ghi nhớ cạnh trên lúc cửa sổ hiện ra rồi đặt lại toàn bộ khung theo chiều cao đo được.
struct PopoverTopPin: NSViewRepresentable {
    var height: CGFloat
    func makeNSView(context: Context) -> PinView { PinView() }
    func updateNSView(_ nsView: PinView, context: Context) { nsView.height = height; nsView.apply() }

    final class PinView: NSView {
        var height: CGFloat = 0
        private var top: CGFloat?
        private var observers: [NSObjectProtocol] = []
        private var monitors: [Any] = []
        /// Lần bấm chuột gần nhất nằm NGOÀI popover và panel phụ (thời điểm máy chạy, giây).
        private var lastOutsideClick: TimeInterval = 0

        /// Popover chỉ được tắt khi người dùng bấm ra ngoài (hoặc app chủ động đóng). macOS/SwiftUI còn tự ẩn nó khi mất focus vì
        /// lý do khác (hộp thoại hệ thống, một app thoát làm đổi app đang chạy…): trường hợp đó hiện lại.
        private func guardStayOpen(_ w: NSWindow) {
            monitors.forEach(NSEvent.removeMonitor); monitors = []
            let mark: (NSEvent) -> Void = { [weak self, weak w] _ in
                let p = NSEvent.mouseLocation
                let inside = (w?.frame.contains(p) ?? false) || (PopoverDetailPanel.shared.panelFrame?.contains(p) ?? false)
                if !inside { self?.lastOutsideClick = ProcessInfo.processInfo.systemUptime }
            }
            let down: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            if let m = NSEvent.addGlobalMonitorForEvents(matching: down, handler: { mark($0) }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: down, handler: { mark($0); return $0 }) { monitors.append(m) }
            // Esc là cách đóng có chủ ý.
            if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in
                if e.keyCode == 53 { AppDelegate.noteIntentionalPopoverClose() }
                return e
            }) { monitors.append(m) }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { [weak self, weak w] _ in
                for delay in [0.08, 0.25, 0.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        guard let self, let w, !w.isVisible else { return }
                        let now = ProcessInfo.processInfo.systemUptime
                        let clickedOutside = now - self.lastOutsideClick < 0.8
                        let appClosed = now - AppDelegate.lastIntentionalPopoverClose < 1.0
                        if !clickedOutside && !appClosed { w.orderFront(nil) }
                    }
                }
            })
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver); observers = []
            guard let w = window else { return }
            top = w.frame.maxY
            guardStayOpen(w)
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { [weak self, weak w] _ in
                self?.top = w?.frame.maxY
                DispatchQueue.main.async { self?.apply() }
            })
            // Đặt lại khung ở vòng lặp kế tiếp, không sửa khung ngay trong lúc cửa sổ đang đổi kích thước.
            observers.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.apply() }
            })
        }

        func apply() {
            guard let w = window, let top, height > 1 else { return }
            let target = w.frameRect(forContentRect: NSRect(x: 0, y: 0, width: w.contentRect(forFrameRect: w.frame).width, height: height)).height
            guard abs(w.frame.height - target) > 0.5 || abs(w.frame.maxY - top) > 0.5 else { return }
            w.setFrame(NSRect(x: w.frame.minX, y: top - target, width: w.frame.width, height: target), display: true)
        }
        deinit { observers.forEach(NotificationCenter.default.removeObserver); monitors.forEach(NSEvent.removeMonitor) }
    }
}

/// Popover trên menu bar — cùng ngôn ngữ thiết kế với app: nền gradient, thẻ kính, icon riêng.
struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var devices: [BluetoothDevice] = []
    @ViewState private var devicesLoaded = false
    @ViewState private var speed: SpeedResult?
    @ViewState private var testing = false
    @ViewState private var turbo: TurboBoost.Status?
    @ViewState private var turboBusy = false
    @ViewState private var contentHeight: CGFloat = 0
    @Environment(\.openWindow) private var openWindow

    /// Popover không cao hơn vùng nhìn thấy của màn hình (trừ thanh menu); cao hơn thì cuộn dọc.
    static var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 800) - 12 }

    var body: some View {
        let s = state.snapshot
        // Nền gắn vào chính nội dung; PopoverTopPin giữ cạnh trên của cửa sổ khi nó co/giãn theo nội dung.
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 12) {
                recommendations
                togglesRow
                protectionCard
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    diskTile(s); memoryTile(s); cpuTile(s); batteryTile(s); networkTile(s); devicesTile
                }
                footer
            }
            .padding(14)
        }
        .frame(width: 400, alignment: .top)
        .frame(maxHeight: Self.maxHeight)
        // Nền phải tràn qua vùng an toàn: cửa sổ MenuBarExtra có thể chừa một dải phía trên, nếu nền chỉ phủ phần nội dung
        // thì dải đó lộ lớp vật liệu mờ (màu của cửa sổ phía sau) thành một băng sai màu trên đầu popover.
        .background(ZStack { PageBackground(page: .smartScan); Color.black.opacity(0.18) }.ignoresSafeArea())
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: PopoverHeightKey.self, value: g.size.height) })
        .onPreferenceChange(PopoverHeightKey.self) { contentHeight = $0 }
        .background(PopoverTopPin(height: contentHeight))
        .task { devices = await ConnectedDevices.bluetooth(); devicesLoaded = true }
        .task { turbo = await TurboBoost.status() }
        .onDisappear { PopoverDetailPanel.shared.close() }
        .onAppear { state.openMainWindow = { openWindow(id: "main") } }
    }

    // MARK: Khối chính

    /// Băng chuyền "Gợi ý": mỗi thẻ một việc đáng làm (biểu tượng, lời gợi ý, nút), vuốt ngang để xem tiếp; thẻ thứ ba ló ra một phần.
    /// Việc gấp (ưu tiên ≥ 80) có nút nổi bật; bấm ✕ để ẩn thẻ 7 ngày (hiện lại nếu tình trạng xấu đi nhiều).
    @ViewBuilder var recommendations: some View {
        let cards = state.recommendations
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Gợi ý")).font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cards) { r in recommendationCard(r) }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.horizontal, -14)   // băng chuyền chạy sát mép popover, thẻ đầu vẫn thẳng hàng với phần còn lại
            }
        }
    }

    func recommendationCard(_ r: Recommendation) -> some View {
        let urgent = r.priority >= 80
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: r.icon).font(.system(size: 20, weight: .regular)).foregroundStyle(.white).frame(height: 24)
                Spacer(minLength: 0)
                Button { state.dismissStore.dismiss(r); state.pollSystem() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.Text.tertiary)
                }.buttonStyle(PlainPointerStyle()).help(tr("Ẩn thông báo"))
            }
            Text(r.title).font(.vt(size: 13, weight: .medium)).foregroundStyle(.white)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Group {
                if urgent {
                    Button { state.perform(r.action); activate() } label: { Text(r.actionTitle) }.buttonStyle(PrimaryButtonStyle(fullWidth: true))
                } else {
                    Button { state.perform(r.action); activate() } label: { Text(r.actionTitle) }.buttonStyle(SecondaryButtonStyle(fullWidth: true))
                }
            }.controlSize(.small)
        }
        .padding(12)
        .frame(width: 168, height: 148, alignment: .topLeading)
        .glassSurface(radius: 14, strong: false)
    }

    func tint(for r: Recommendation) -> Color {
        switch r.action {
        case .openDevJunk: return Page.devJunk.palette.glow
        case .openSpaceLens, .thinSnapshots, .openCleanup: return Page.systemJunk.palette.glow
        case .openUpdater: return Page.updater.palette.glow
        case .openUninstaller: return Page.uninstaller.palette.glow
        case .openOptimization, .openBattery: return Page.optimization.palette.glow
        case .runDeepScan, .openMalware: return Page.protection.palette.glow
        case .openSmartScan: return Page.smartScan.palette.glow
        }
    }

    /// "vừa xong", "15 giây trước", "3 phút trước"… tính chính xác theo giây.
    static func agoText(from date: Date, to now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case 0..<3: return tr("vừa xong")
        case 3..<60: return trf("%@ giây trước", "\(s)")
        case 60..<3600: return trf("%@ phút trước", "\(s / 60)")
        case 3600..<86_400: return trf("%@ giờ trước", "\(s / 3600)")
        default: return trf("%@ ngày trước", "\(s / 86_400)")
        }
    }

    /// Trạng thái bảo vệ: giám sát file mới theo thời gian thực (FSEvents), file vừa quét, lần kiểm tra malware gần nhất và nút kiểm tra ngay.
    var protectionCard: some View {
        let on = state.realtimeOn
        let review = state.alerts.count + (state.malwareReport?.highCount ?? 0)
        let (symbol, color, badge): (String, Color, String) = !on ? ("shield.slash.fill", Theme.Text.secondary, tr("Đang tắt"))
            : (review > 0 ? ("exclamationmark.shield.fill", Theme.Review.base, trf("%@ mục cần xem", "\(review)"))
                          : ("checkmark.shield.fill", Theme.Signal.base, tr("Đã bảo vệ")))
        let checking = state.malwareScanning
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(color)
                Text(tr("Bảo vệ")).font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Text(badge).font(.vt(size: 12, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(on ? tr("Giám sát malware thời gian thực đang bật") : tr("Giám sát malware thời gian thực đang tắt"))
                    .font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                Text(on ? (state.lastScanned.map { trf("File vừa quét: %@", URL(fileURLWithPath: $0).lastPathComponent) } ?? tr("Đang chờ file mới"))
                        : tr("Bật Real-time để theo dõi file mới"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
            }
            HStack {
                // Đếm từng giây: TimelineView vẽ lại mỗi giây nên 15s → 16s → 17s, không nhảy cóc theo lần vẽ lại của popover.
                Group {
                    if let date = state.malwareReport?.date {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(trf("Kiểm tra lần cuối %@", Self.agoText(from: date, to: ctx.date))).monospacedDigit()
                        }
                    } else { Text(tr("Chưa kiểm tra")) }
                }.font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Button { Task { await state.runMalwareCheck() } } label: {
                    HStack(spacing: 5) {
                        if checking { VSpinner(size: 11, lineWidth: 1.6) }
                        Text(checking ? tr("Đang kiểm tra…") : tr("Kiểm tra ngay"))
                    }
                }.buttonStyle(MiniButtonStyle()).disabled(checking)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 14, strong: false)
        .clickable {
            // Cảnh báo real-time chỉ hiện (và dọn được) ở trang Bảo vệ; kết quả quét malware nằm ở trang Malware.
            state.section = (state.malwareReport?.highCount ?? 0) > 0 ? .malware : .protection; activate()
        }
    }

    /// Hai công tắc nhanh cạnh nhau: Real-time và (chỉ Mac Intel) Turbo Boost. Mỗi ô: biểu tượng + công tắc ở trên, tên + trạng thái ở dưới.
    @ViewBuilder var togglesRow: some View {
        HStack(spacing: 10) {
            toggleTile(symbol: "v.wifi", tint: Theme.Signal.base, title: "Real-time",
                       status: state.realtimeOn ? (state.lastScanned.map { URL(fileURLWithPath: $0).lastPathComponent } ?? tr("Đang theo dõi")) : tr("Đang tắt"),
                       isOn: Binding(get: { state.realtimeOn }, set: { state.setRealtime($0) }), busy: false,
                       help: tr("Theo dõi file mới"))
            if let t = turbo, t.isIntel, t.kextPath != nil || t.lowPowerMode != nil {
                let limited = t.turboLimited
                toggleTile(symbol: "bolt.fill", tint: Theme.orange, title: "Turbo Boost",
                           status: limited ? tr("Đã hạ xung") : tr("Hiệu năng tối đa"),
                           isOn: Binding(get: { !limited }, set: { setTurbo(enabled: $0, status: t) }), busy: turboBusy,
                           help: t.kextPath != nil ? tr("Tắt Turbo Boost (kext)") : tr("Chế độ Tiết kiệm điện"))
            }
        }
    }

    func toggleTile(symbol: String, tint: Color, title: String, status: String, isOn: Binding<Bool>, busy: Bool, help: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconTile(symbol: symbol, tint: isOn.wrappedValue ? tint : Theme.Text.secondary, size: 28)
                Spacer(minLength: 0)
                if busy { VSpinner(size: 14, lineWidth: 2) }
                SwitchRow(isOn: isOn, label: title).disabled(busy)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.vt(size: 14, weight: .semibold)).foregroundStyle(.white)
                HStack(spacing: 5) {
                    Circle().fill(isOn.wrappedValue ? Theme.Signal.base : Theme.Text.tertiary).frame(width: 5, height: 5)
                    Text(status).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 14, strong: false)
        .help(help)
    }

    func setTurbo(enabled: Bool, status t: TurboBoost.Status) {
        turboBusy = true
        Task {
            let r: ProcessResult
            if let path = t.kextPath { r = await TurboBoost.setKextLoaded(!enabled, path: path) }
            else { r = await TurboBoost.setLowPowerMode(!enabled) }
            if !r.ok { state.notify(tr("Không thể đổi cài đặt Turbo Boost."), .error) }
            turbo = await TurboBoost.status()
            turboBusy = false
        }
    }

    // MARK: Ô số liệu — gọn: tiêu đề · giá trị · một thanh/đồ thị nhỏ. Chi tiết và hành động nằm trong panel mở ra khi bấm vào ô.

    /// Chiều cao chung của các ô số liệu.
    static let tileHeight: CGFloat = 96

    /// Giá trị của ô: số vừa phải (font mặc định) + đơn vị nhỏ và mờ bên cạnh. "248,63 GB free" → "248,63" + "GB free".
    /// Cỡ chữ co giãn theo cài đặt Text size của người dùng, nên bố cục tự lùi từng bước thay vì bị cắt giữa chừng:
    /// số + đơn vị đầy đủ → số + đơn vị ngắn ("GB") → chỉ số.
    @ViewBuilder func tileValue(_ v: String) -> some View {
        var rest = Substring(v)
        let lead: String = {
            if let f = rest.first, !f.isNumber, !f.isLetter { rest = rest.dropFirst().drop(while: { $0 == " " }); return String(f) }
            return ""
        }()
        let parts = rest.split(separator: " ", maxSplits: 1).map(String.init)
        if let num = parts.first, num.contains(where: \.isNumber) {
            let unit = parts.count > 1 ? parts[1] : ""
            let short = unit.split(separator: " ").first.map(String.init) ?? ""
            ViewThatFits(in: .horizontal) {
                valueRow(lead, num, unit)
                if !short.isEmpty && short != unit { valueRow(lead, num, short) }
                valueRow(lead, num, "")
            }
        } else {
            Text(v).font(.vt(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    func valueRow(_ lead: String, _ num: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !lead.isEmpty { Text(lead).font(.vt(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.secondary) }
            Text(num).font(.vt(size: 19, weight: .semibold)).tracking(-0.3).monospacedDigit().foregroundStyle(.white)
            if !unit.isEmpty { Text(unit).font(.vt(size: 11.5, weight: .medium)).foregroundStyle(Theme.Text.secondary) }
        }.lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    /// `go`: bấm vào ô để mở panel chi tiết hoặc trang tương ứng.
    func tile<M: View>(_ title: String, symbol: String, tint: Color, value v: String,
                       middleHeight: CGFloat = 14, go: (() -> Void)? = nil, @ViewBuilder middle: () -> M) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                IconTile(symbol: symbol, tint: tint, size: 22)
                Text(title).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase).lineLimit(1)
                Spacer(minLength: 0)
                if go != nil { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Text.tertiary) }
            }.frame(height: 22)
            tileValue(v).frame(height: 26, alignment: .bottomLeading).padding(.top, 4)
            middle().frame(maxWidth: .infinity, minHeight: middleHeight, maxHeight: middleHeight, alignment: .leading).padding(.top, 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Self.tileHeight + middleHeight - 14, maxHeight: Self.tileHeight + middleHeight - 14, alignment: .topLeading)
        .glassSurface(radius: 14, strong: false)
        .clickable(go)
    }

    /// Mở một trang của cửa sổ chính từ popover.
    func open(_ page: Page) { state.section = page; activate() }

    /// Mở một pane của System Settings rồi đóng popover.
    func openSystemSettings(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        AppDelegate.closeMenuBarPopover()
    }

    func diskTile(_ s: SystemSnapshot?) -> some View {
        let d = s?.disk
        let used = d.map { 1 - $0.freeFraction } ?? 0
        return tile(tr("Ổ đĩa"), symbol: "v.drive", tint: Page.systemJunk.palette.glow,
                    value: d.map { ByteFormat.string($0.availableImportant) + tr(" trống") } ?? "—",
                    middleHeight: 24, go: { PopoverDetailPanel.shared.show(.disk, state: state) }) {
            meterWithFreeUp(MeterBar(value: used, color: used > 0.9 ? Theme.danger : Color.white.opacity(0.9), height: 5), kind: .disk)
        }
    }

    func memoryTile(_ s: SystemSnapshot?) -> some View {
        let m = s?.memory
        let used = m.map { 1 - Double($0.available) / Double(max(1, $0.total)) } ?? 0
        let c: Color = (m?.pressure ?? .normal) == .normal ? Color.white.opacity(0.9) : ((m?.pressure ?? .normal) == .warning ? Theme.Review.base : Theme.danger)
        return tile(tr("Bộ nhớ"), symbol: "v.ram", tint: Page.optimization.palette.glow,
                    value: m.map { ByteFormat.string($0.available) + tr(" khả dụng") } ?? "—",
                    middleHeight: 24, go: { PopoverDetailPanel.shared.show(.memory, state: state) }) {
            meterWithFreeUp(MeterBar(value: used, color: c, height: 5), kind: .memory)
        }
    }

    func cpuTile(_ s: SystemSnapshot?) -> some View {
        tile("CPU", symbol: "v.chip", tint: Page.updater.palette.glow, value: "\(Int((s?.cpuLoad ?? 0) * 100))%",
             go: { PopoverDetailPanel.shared.show(.cpu, state: state) }) {
            Sparkline(values: state.cpuHistory, color: Color.white.opacity(0.9))
        }
    }

    func batteryTile(_ s: SystemSnapshot?) -> some View {
        let b = s?.battery
        return tile(tr("Pin"), symbol: "v.bolt", tint: Page.protection.palette.glow,
                    value: b.map { "\($0.percent)%" + ($0.charging ? " ⚡︎" : "") } ?? tr("Không có"),
                    go: b == nil ? nil : { PopoverDetailPanel.shared.show(.battery, state: state) }) {
            if let b { MeterBar(value: Double(b.percent) / 100, color: b.percent < 20 ? Theme.danger : Color.white.opacity(0.9), height: 5) }
            else { Color.clear }
        }
    }

    func networkTile(_ s: SystemSnapshot?) -> some View {
        tile(tr("Mạng"), symbol: "v.wifi", tint: Page.cloud.palette.glow, value: "↓ " + rate(s?.network.downBytesPerSec),
             middleHeight: 24, go: { PopoverDetailPanel.shared.show(.network, state: state) }) {
            // Hàng upload + nút Đo tốc độ. Cỡ chữ co giãn nên lùi từng bước: nút có chữ → chỉ biểu tượng.
            let up = Text("↑ " + rate(s?.network.upBytesPerSec)).font(.vt(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(Theme.Text.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { up; Spacer(minLength: 4); speedTestButton(label: tr("Đo tốc độ")) }
                HStack(spacing: 6) { up; Spacer(minLength: 4); speedTestButton(label: tr("Đo thử")) }
                HStack(spacing: 6) { up; Spacer(minLength: 4); speedTestButton(label: nil) }
            }
        }
    }

    /// Thanh đo + nút "Giải phóng" cùng hàng (ô Ổ đĩa, Bộ nhớ). Hết chỗ thì nút chỉ còn biểu tượng.
    func meterWithFreeUp(_ meter: MeterBar, kind: PopoverDetailPanel.Kind) -> some View {
        let bar = meter.frame(minWidth: 56)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { bar; freeUpButton(kind, labelled: true) }
            HStack(spacing: 8) { bar; freeUpButton(kind, labelled: false) }
        }
    }

    /// Mở panel chi tiết và chạy luôn: Bộ nhớ → giải phóng RAM; Ổ đĩa → quét rác (không tự xóa).
    func freeUpButton(_ kind: PopoverDetailPanel.Kind, labelled: Bool) -> some View {
        Button { PopoverDetailPanel.shared.show(kind, state: state, autoRun: true) } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                if labelled { Text(tr("Giải phóng")).lineLimit(1) }
            }
        }
        .buttonStyle(MiniButtonStyle()).fixedSize().help(tr("Giải phóng"))
    }

    /// Mở panel Mạng và chạy đo tốc độ ngay.
    func speedTestButton(label: String?) -> some View {
        Button { PopoverDetailPanel.shared.show(.network, state: state, autoRun: true) } label: {
            HStack(spacing: 4) {
                Image(systemName: "speedometer").font(.system(size: 10, weight: .bold))
                if let label { Text(label).lineLimit(1) }
            }
        }
        .buttonStyle(MiniButtonStyle()).fixedSize().help(tr("Đo tốc độ"))
    }
    /// Ô thiết bị: mỗi thiết bị Bluetooth đang kết nối một hàng (biểu tượng theo loại · tên · loại/trạng thái · pin). Tối đa 2 hàng, huy hiệu ở tiêu đề cho biết tổng.
    var devicesTile: some View {
        let shown = Array(devices.prefix(2))
        let tint = Page.privacy.palette.glow
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                IconTile(symbol: "v.command", tint: tint, size: 22)
                Text(tr("Thiết bị")).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase).lineLimit(1)
                Spacer(minLength: 0)
                if devices.count > 0 {
                    Text(devices.count > 2 ? "+\(devices.count - 2)" : "\(devices.count)")
                        .font(.vt(size: 11, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                        .padding(.horizontal, 7).frame(minWidth: 20, minHeight: 18)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
            }.frame(height: 22)
            if devices.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(devicesLoaded ? tr("Không có") : tr("Đang kiểm tra…")).font(.vt(size: 19, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                }.padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 2) { ForEach(shown) { deviceRow($0, tint: tint) } }.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Self.tileHeight, maxHeight: .infinity, alignment: .topLeading)   // giãn theo ô cùng hàng
        .glassSurface(radius: 14, strong: false)
        .clickable { PopoverDetailPanel.shared.show(.devices, state: state, devices: devices) }
    }

    /// Một dòng gọn: biểu tượng · tên · pin (nếu thiết bị báo được). Loại thiết bị hiện ở tooltip.
    func deviceRow(_ d: BluetoothDevice, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: deviceSymbol(d.kind)).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
            Text(d.name).font(.vt(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if let b = d.batteryPercent {
                Text("\(b)%").font(.vt(size: 12.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(b <= 20 ? Theme.danger : Theme.Text.primary)
            }
        }
        .frame(height: 22)
        .help(d.kind.isEmpty ? tr("Đã kết nối") : d.kind)
    }

    func deviceSymbol(_ kind: String) -> String {
        switch kind.lowercased() {
        case "mouse": return "computermouse.fill"
        case "keyboard": return "keyboard.fill"
        case "trackpad": return "rectangle.and.hand.point.up.left.fill"
        case "headphones", "headset": return "headphones"
        case "speaker": return "hifispeaker.fill"
        case "gamepad": return "gamecontroller.fill"
        case "phone", "iphone": return "iphone"
        case "ipad": return "ipad"
        case "watch": return "applewatch"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// Chân popover: đường kẻ · biểu tượng app · dòng hành động chính ở giữa · nút bánh răng mở menu (Giới thiệu, Góp ý, Cài đặt, Thoát).
    var footer: some View {
        VStack(spacing: 10) {
            Divider().overlay(Color.white.opacity(0.1))
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 24, height: 24)
                primaryButton.frame(maxWidth: .infinity)
                Menu {
                    Button { AboutPanel.show(); AppDelegate.closeMenuBarPopover() } label: { Label(tr("Giới thiệu Vutidy"), systemImage: "info.circle") }
                    Button(tr("Góp ý…")) {
                        if let u = URL(string: "https://github.com/vunguyenvu35/vutidy/issues") { NSWorkspace.shared.open(u) }
                        AppDelegate.closeMenuBarPopover()
                    }
                    Divider()
                    Button(tr("Cài đặt…")) { state.openSettings(.general); AppDelegate.closeMenuBarPopover() }.keyboardShortcut(",")
                    Divider()
                    Button(tr("Thoát hẳn Vutidy")) { AppDelegate.quitCompletely() }
                } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 15)).foregroundStyle(Theme.Text.primary)
                        .frame(width: 30, height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(tr("Tùy chọn"))
            }
        }
        .padding(.top, 2)
    }

    /// Số byte rác an toàn đã biết từ lần quét gần nhất (0 nếu chưa quét).
    var junkBytes: Int64 { state.smart?.cleanableBytes ?? 0 }

    /// Nút chính đổi theo tình trạng máy: có gợi ý cần dọn (RAM áp lực, purgeable, ổ đầy, dev junk…) thì hiện hành động đó.
    var cleanSuggestion: Recommendation? {
        state.recommendations.first { [.thinSnapshots, .openSpaceLens, .openDevJunk, .openOptimization, .openCleanup].contains($0.action) }
    }

    @ViewBuilder var primaryButton: some View {
        if let r = cleanSuggestion {
            Button { state.perform(r.action); activate() } label: { footerLabel(footerTitle(for: r), icon: "sparkles") }
                .buttonStyle(FooterLinkStyle()).help(r.title)
        } else if junkBytes > 0 {
            Button { state.section = .systemJunk; activate() } label: { footerLabel(trf("Dọn tới %@ rác", ByteFormat.string(junkBytes)), icon: "sparkles") }
                .buttonStyle(FooterLinkStyle())
        } else {
            Button { state.section = .smartScan; activate() } label: { footerLabel(tr("Mở Vutidy"), icon: "arrow.up.forward.app") }.buttonStyle(FooterLinkStyle())
        }
    }

    func footerLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(title).lineLimit(1)
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

    /// Mở cửa sổ chính và đóng popover thanh menu (MenuBarExtra kiểu .window không tự đóng khi bấm nút bên trong).
    func activate() {
        // Lúc bấm nút, popover chính là cửa sổ đang nhận phím; lấy nó TRƯỚC khi cửa sổ chính được đưa lên.
        let popover = NSApp.keyWindow.flatMap { $0.canBecomeMain ? nil : $0 }
        state.showMainWindow()
        popover?.orderOut(nil)
        AppDelegate.closeMenuBarPopover()
    }
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

/// Nút hành động chính ở chân popover: capsule gradient tím có ánh sáng và viền, cùng ngôn ngữ với các nút chính của app.
private struct FooterLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FooterLinkBody(configuration: configuration) }
}

private struct FooterLinkBody: View {
    let configuration: ButtonStyleConfiguration
    @ViewState private var hover = false
    private let bright = Color(hex: 0x9A8CFF), deep = Color(hex: 0x5A46D8)
    var body: some View {
        configuration.label.font(.vt(size: 14, weight: .semibold)).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                ZStack {
                    Capsule().fill(LinearGradient(colors: [bright, deep], startPoint: .top, endPoint: .bottom))
                    Capsule().fill(LinearGradient(colors: [Color.white.opacity(hover ? 0.34 : 0.24), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
                }
            )
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: bright.opacity(hover ? 0.65 : 0.4), radius: hover ? 16 : 11, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
            .onHover { hover = $0 }
            .pointerCursor()
    }
}
