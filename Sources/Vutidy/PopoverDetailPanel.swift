import SwiftUI
import AppKit
import CoreKit
import Modules

/// Panel thông tin nằm cạnh popover thanh menu (bên trái), mở khi bấm "Giải phóng" ở ô Ổ đĩa / Bộ nhớ.
@MainActor
final class PopoverDetailPanel {
    static let shared = PopoverDetailPanel()
    enum Kind { case memory, disk, cpu, battery, network, devices }

    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    /// Theo dõi popover chính: panel phụ chỉ có nghĩa khi popover còn hiện, nên đóng ngay khi nó biến mất (bấm ra ngoài, sang cửa sổ khác, đổi app…).
    private var watchdog: Timer?
    static let width: CGFloat = 372

    /// Khung của panel phụ khi đang hiện (để biết một cú bấm nằm trong hay ngoài).
    var panelFrame: NSRect? { panel.flatMap { $0.isVisible ? $0.frame : nil } }

    static var popoverWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.canBecomeMain && String(describing: type(of: $0)).contains("MenuBarExtra") }
    }

    func show(_ kind: Kind, state: AppState, autoRun: Bool = false, devices: [BluetoothDevice] = []) {
        guard let pop = Self.popoverWindow else { return }
        close(animated: false)
        let host = NSHostingView(rootView: DetailPanelView(kind: kind, state: state, autoRun: autoRun, devices: devices, close: { [weak self] in self?.close() })
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
        // Đóng cùng popover. Thông báo "mất phím" cho phản ứng nhanh; bộ theo dõi định kỳ là lưới an toàn, vì popover có thể ẩn
        // chậm hơn mốc kiểm tra của thông báo hoặc không phát thông báo (khi chuyển sang cửa sổ chính của app), để lại panel mồ côi.
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: pop, queue: .main) { [weak self, weak pop] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { if pop?.isVisible != true { self?.close() } }
            }
        }
        // Hai nhịp liên tiếp không thấy popover mới đóng: popover có thể bị ẩn thoáng qua rồi được hiện lại.
        var misses = 0
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                misses = Self.popoverWindow == nil ? misses + 1 : 0
                if misses >= 2 { self?.close() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
    }

    /// Đóng panel: mặc định bay sang phải (về phía popover) và mờ dần rồi mới ẩn.
    func close(animated: Bool = true) {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        watchdog?.invalidate(); watchdog = nil
        guard let p = panel else { return }
        panel = nil
        guard animated, p.isVisible else { p.orderOut(nil); return }
        var f = p.frame
        f.origin.x += 60
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(f, display: true)
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

private struct DetailPanelView: View {
    let kind: PopoverDetailPanel.Kind
    @ObservedObject var state: AppState
    let autoRun: Bool
    var devices: [BluetoothDevice] = []
    let close: () -> Void
    @ViewState private var apps: [Optimization.AppMemory] = []
    @ViewState private var loadedApps = false
    @ViewState private var speed: SpeedResult?
    @ViewState private var testing = false
    @ViewState private var wifi: String?
    @ViewState private var cpuApps: [Optimization.AppMemory] = []
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
            switch kind { case .memory: memory; case .disk: disk; case .cpu: cpu; case .battery: battery; case .network: network; case .devices: devicesPanel }
        }
        .padding(14)
        .frame(width: PopoverDetailPanel.width, alignment: .top)
        .background(ZStack { PageBackground(page: .smartScan); Color.black.opacity(0.18) })
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .task {
            await reload()
            // Bấm "Giải phóng" ở ô: mở panel và chạy luôn. Bộ nhớ → purge; ổ đĩa → quét rác (không tự xóa), kết quả ở Dọn rác hệ thống.
            guard autoRun else { return }
            if kind == .memory { await purge() }
            else if kind == .network { await runSpeed() }
            else if kind == .disk { await state.runSmartScan(autoClean: false); await reload() }
        }
    }

    func reload() async {
        breakdown = SystemMonitor.memoryBreakdown()
        if kind == .memory { apps = await Optimization.memoryByApp(limit: 5); loadedApps = true; return }
        if kind == .network { wifi = await SystemMonitor.wifiName(); return }
        if kind == .cpu { cpuApps = await Optimization.cpuByApp(limit: 12); loadedApps = true; return }
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
            IconTile(symbol: kind == .memory ? "v.ram" : (kind == .cpu ? "v.chip" : (kind == .battery ? "v.bolt" : (kind == .network ? "v.wifi" : (kind == .devices ? "v.command" : "v.drive")))),
                     tint: (kind == .memory ? Page.optimization : (kind == .cpu ? Page.updater : (kind == .battery ? Page.protection : (kind == .network ? Page.cloud : (kind == .devices ? Page.privacy : Page.systemJunk))))).palette.glow, size: 24)
            Text(kind == .memory ? tr("Bộ nhớ") : (kind == .cpu ? SystemMonitor.cpuBrand : (kind == .battery ? tr("Pin") : (kind == .network ? tr("Mạng") : (kind == .devices ? tr("Thiết bị kết nối") : Self.volumeName)))))
                .lineLimit(1).minimumScaleFactor(0.7).font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
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


    // MARK: CPU

    var cpu: some View {
        let s = state.snapshot
        let user = s?.cpuUser ?? 0, sys = s?.cpuSystem ?? 0
        let temp = s?.cpuTemp
        let up = ProcessInfo.processInfo.systemUptime
        let upText = up >= 86400 ? "\(Int(up / 86400))d \(Int(up / 3600) % 24)h" : (up >= 3600 ? "\(Int(up / 3600))h \(Int(up / 60) % 60)m" : "\(Int(up / 60))m")
        let upNote = up < 3600 ? tr("Bạn vừa khởi động máy.") : (up < 7 * 86400 ? tr("Máy đã chạy ổn định.") : tr("Máy đã chạy lâu, nên khởi động lại."))
        let hot = (temp ?? 0) >= 85 || (s?.thermal ?? .nominal) == .serious || (s?.thermal ?? .nominal) == .critical
        let warm = (temp ?? 0) >= 70 || (s?.thermal ?? .nominal) == .fair
        let tColor: Color = hot ? Theme.danger : (warm ? Theme.Review.base : Theme.Signal.base)
        let tNote = hot ? tr("Máy đang nóng, hãy thoát bớt app nặng.") : (warm ? tr("Máy hơi nóng nhưng vẫn trong mức bình thường.") : tr("Nhiệt độ bình thường."))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                cpuChart.frame(height: 100).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 10) {
                    cpuStat(String(format: "%.1f %%", max(0, 1 - user - sys) * 100), tr("Rảnh"), Color.white.opacity(0.35))
                    cpuStat(String(format: "%.1f %%", user * 100), "User", blue)
                    cpuStat(String(format: "%.1f %%", sys * 100), "System", Color(red: 1.0, green: 0.42, blue: 0.5))
                }.frame(width: 96, alignment: .leading)
            }
            .padding(14).glassSurface(radius: 14, strong: false)
            HStack(spacing: 10) {
                statCard(tr("Thời gian chạy"), badge: upText, badgeColor: Theme.Text.primary, meter: nil, meterColor: .clear, note: upNote, minHeight: 0)
                statCard(tr("Nhiệt độ"), badge: temp.map { String(format: "%.0f°C", $0) } ?? cpuThermalLabel(s?.thermal ?? .nominal),
                         badgeColor: tColor, meter: nil, meterColor: .clear, note: tNote, minHeight: 0)
            }
            cpuConsumers
        }
    }

    func cpuThermalLabel(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return tr("Bình thường"); case .fair: return tr("Hơi nóng")
        case .serious: return tr("Nóng"); case .critical: return tr("Quá nóng")
        @unknown default: return "—"
        }
    }

    func cpuStat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Capsule().fill(color).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.vt(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                Text(label).font(.vt(size: 11.5)).foregroundStyle(Theme.Text.secondary)
            }
        }
    }

    /// Biểu đồ lịch sử: tổng tải (xanh, tô mờ) và phần System (đỏ), trục 0–100%.
    var cpuChart: some View {
        func line(_ v: [Double], _ size: CGSize) -> Path {
            Path { p in
                guard v.count > 1 else { return }
                for (i, x) in v.enumerated() {
                    let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(v.count - 1), y: size.height * (1 - CGFloat(min(1, max(0, x)))))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }
        }
        let total = zip(state.cpuUserHistory, state.cpuSystemHistory).map { $0 + $1 }
        return GeometryReader { g in
            ZStack {
                Path { p in
                    for i in 1..<4 { let y = g.size.height * CGFloat(i) / 4; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y)) }
                }.stroke(Color.white.opacity(0.07), lineWidth: 1)
                line(total, g.size).stroke(blue, lineWidth: 1.5)
                line(state.cpuSystemHistory, g.size).stroke(Color(red: 1.0, green: 0.42, blue: 0.5), lineWidth: 1.5)
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.18)))
    }

    var cpuConsumers: some View {
        let rows = Array(cpuApps.compactMap { c -> (Optimization.AppMemory, NSRunningApplication)? in
            // Gộp tiến trình về app đang chạy (bỏ daemon/helper không có app) để có tên + biểu tượng + nút Thoát.
            guard let a = NSRunningApplication(processIdentifier: c.id), a.activationPolicy == .regular else { return nil }
            return (c, a)
        }.prefix(5))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(tr("Ngốn CPU nhất")).textCase(.uppercase)
                Spacer()
                Text(tr("Mức dùng, %")).textCase(.uppercase)
                Color.clear.frame(width: 56, height: 1)
            }
            .font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.element.0.id) { i, r in
                let canQuit = r.1.bundleIdentifier != "com.apple.finder" && r.1.processIdentifier != getpid()
                HStack(spacing: 10) {
                    AppIconView(image: r.1.icon, fallback: "terminal.fill", size: 26)
                    Text(r.1.localizedName ?? r.0.name).font(.vt(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(String(format: "%.1f", r.0.cpu)).font(.vt(size: 12.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(r.0.cpu >= 20 ? Theme.Review.base : Theme.Text.secondary)
                    Group {
                        if canQuit {
                            Button(tr("Thoát")) { r.1.terminate(); Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await reload() } }
                                .buttonStyle(MiniButtonStyle())
                        } else { Color.clear }
                    }.frame(width: 56, alignment: .trailing)
                }
                .padding(.horizontal, 14).frame(height: 40)
                if i < rows.count - 1 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 52) }
            }
            if rows.isEmpty {
                HStack(spacing: 8) { if !loadedApps { VSpinner(size: 14, lineWidth: 2) }; Text(loadedApps ? "—" : tr("Đang tính dung lượng…")) }
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity, minHeight: 40 * 5)
            }
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 40 * 5 + 40, alignment: .topLeading)
        .glassSurface(radius: 14, strong: false)
    }

    // MARK: Pin

    var battery: some View {
        let b = state.snapshot?.battery
        let pct = b?.percent ?? 0
        let full = pct >= 100 && b?.charging != true
        let color: Color = pct < 20 && b?.pluggedIn != true ? Theme.danger : (pct < 40 && b?.pluggedIn != true ? Theme.Review.base : Theme.Signal.base)
        let status = full ? tr("Đã đầy pin") : (b?.charging == true ? tr("Đang sạc") : tr("Đang dùng pin"))
        var note = b?.pluggedIn == true ? tr("Bạn đang dùng điện từ bộ sạc.") : tr("Bạn đang dùng điện từ pin.")
        if let m = b?.minutesRemaining, !full { note = trf("Còn khoảng %@", m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m") }
        let cycles = b?.cycleCount
        let health = b?.health.map { Int(($0 * 100).rounded()) }
        let hNote = health.map { $0 >= 80 ? tr("Pin còn tốt.") : ($0 >= 60 ? tr("Pin tốt nhưng đã mất một phần dung lượng.") : tr("Pin đã chai nhiều, nên cân nhắc thay.")) } ?? tr("Không đọc được sức khỏe pin.")
        let temp = b?.tempC
        let tHot = (temp ?? 0) >= 40
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                segmentedRing(fraction: Double(pct) / 100, color: color, label: "\(pct)%")
                VStack(alignment: .leading, spacing: 6) {
                    Text(status).font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(note).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
                    if let cycles {
                        Text("\(cycles) / 1000").font(.vt(size: 14, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white).padding(.top, 4)
                        Text(tr("chu kỳ sạc")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14).glassSurface(radius: 14, strong: false)
            HStack(spacing: 10) {
                statCard(tr("Sức khỏe"), badge: health.map { "\($0)%" } ?? "—", badgeColor: (health ?? 100) >= 80 ? Theme.Signal.base : Theme.Review.base,
                         meter: nil, meterColor: .clear, note: hNote, minHeight: 0)
                statCard(tr("Nhiệt độ"), badge: temp.map { String(format: "%.0f°C", $0) } ?? "—", badgeColor: tHot ? Theme.Review.base : Theme.Signal.base,
                         meter: nil, meterColor: .clear,
                         note: temp == nil ? tr("Không đọc được nhiệt độ pin.") : (tHot ? tr("Pin hơi nóng, tránh để máy trong nơi kín.") : tr("Nhiệt độ pin đang ở mức lý tưởng.")), minHeight: 0)
            }
        }
    }

    /// Vòng chia đoạn (40 vạch) tô theo phần trăm.
    func segmentedRing(fraction: Double, color: Color, label: String) -> some View {
        let n = 40
        let lit = Int((fraction * Double(n)).rounded())
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                Capsule().fill(i < lit ? color : Color.white.opacity(0.1)).frame(width: 5, height: 13)
                    .offset(y: -52).rotationEffect(.degrees(Double(i) / Double(n) * 360))
            }
            Text(label).font(.vt(size: 24, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
        }
        .frame(width: 128, height: 128)
        .shadow(color: color.opacity(0.35), radius: 6)
    }

    // MARK: Mạng

    func runSpeed() async {
        guard !testing else { return }
        testing = true
        if let r = await SpeedTest.run() { speed = r; SpeedTest.append(r) }
        testing = false
    }

    var network: some View {
        let n = state.snapshot?.network
        let ip = SystemMonitor.localIP()
        let isWifi = wifi != nil
        func rate(_ b: Double?) -> String { ByteFormat.string(Int64(b ?? 0)) + "/s" }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isWifi ? "wifi" : (ip == nil ? "wifi.slash" : "network")).font(.system(size: 22, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(wifi ?? (ip == nil ? tr("Chưa kết nối") : tr("Kết nối có dây"))).font(.vt(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    Text(isWifi ? tr("Kết nối Wi-Fi") : tr("Mạng")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
                Spacer(minLength: 8)
                if let ip { Text(ip).font(.vt(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white) }
            }
            .padding(14).frame(maxWidth: .infinity).glassSurface(radius: 14, strong: false)
            HStack(spacing: 10) {
                netCard(tr("Tải xuống"), total: state.netDownTotal, rate: rate(n?.downBytesPerSec), values: state.netDownHistory, color: blue)
                netCard(tr("Tải lên"), total: state.netUpTotal, rate: rate(n?.upBytesPerSec), values: state.netUpHistory, color: Color(red: 1.0, green: 0.42, blue: 0.5))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Kiểm tra kết nối")).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
                HStack(spacing: 16) {
                    Button { Task { await runSpeed() } } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.08))
                            if testing { VSpinner(size: 22, lineWidth: 2.5) }
                            else if let speed {
                                VStack(spacing: 0) {
                                    Text(String(format: "%.0f", speed.downMbps)).font(.vt(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                                    Text("Mbps ↓").font(.vt(size: 11)).foregroundStyle(Theme.Text.secondary)
                                }
                            } else { Text(tr("Đo tốc độ")).font(.vt(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.primary) }
                        }
                        .frame(width: 96, height: 96).contentShape(Circle())
                    }.buttonStyle(.plain).disabled(testing).pointerCursor()
                    VStack(alignment: .leading, spacing: 4) {
                        if let speed {
                            Text(String(format: "↓ %.0f  ↑ %.0f Mbps", speed.downMbps, speed.upMbps)).font(.vt(size: 13.5, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            if let r = speed.responsivenessRPM { Text(trf("Độ phản hồi: %@ RPM", "\(r)")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary) }
                        }
                        Text(tr("Vutidy dùng công cụ networkQuality của macOS để đo mạng của bạn.")).font(Theme.Font.caption)
                            .foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 14, strong: false)
        }
    }

    func netCard(_ title: String, total: Double, rate: String, values: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
            HStack {
                Text(ByteFormat.string(Int64(total))).font(.vt(size: 14, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(rate).font(.vt(size: 11.5)).monospacedDigit().foregroundStyle(Theme.Text.secondary)
            }.lineLimit(1).minimumScaleFactor(0.7)
            Sparkline(values: values, color: color).frame(height: 40)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading).glassSurface(radius: 14, strong: false)
    }

    // MARK: Thiết bị kết nối

    struct ExternalDrive: Identifiable { let id: URL; let name: String; let total: Int64; let available: Int64 }

    static func externalDrives() -> [ExternalDrive] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsInternal == false,
                  v.volumeIsRemovable == true || v.volumeIsEjectable == true, let t = v.volumeTotalCapacity, t > 0 else { return nil }
            return ExternalDrive(id: u, name: v.volumeName ?? u.lastPathComponent, total: Int64(t), available: Int64(v.volumeAvailableCapacity ?? 0))
        }
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

    func deviceCard(_ d: BluetoothDevice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                    if let b = d.batteryPercent {
                        Circle().trim(from: 0, to: CGFloat(b) / 100).stroke(b <= 20 ? Theme.danger : Theme.Signal.base, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Image(systemName: deviceSymbol(d.kind)).font(.system(size: 15)).foregroundStyle(.white)
                }.frame(width: 38, height: 38)
                Spacer(minLength: 4)
                if let b = d.batteryPercent { Text("\(b)%").font(.vt(size: 17, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white) }
                else { Text(tr("Không có dữ liệu pin")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).multilineTextAlignment(.trailing) }
            }
            Text(d.name).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
            Text(d.kind.isEmpty ? "Bluetooth" : d.kind).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading).glassSurface(radius: 14, strong: false)
    }

    var devicesPanel: some View {
        let drives = Self.externalDrives()
        return VStack(alignment: .leading, spacing: 12) {
            if devices.isEmpty {
                Text(tr("Không có thiết bị Bluetooth nào đang kết nối.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80).glassSurface(radius: 14, strong: false)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(devices) { deviceCard($0) }
                }
            }
            Text(tr("Ổ đĩa ngoài")).font(.vt(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.secondary).textCase(.uppercase).padding(.top, 4)
            if drives.isEmpty {
                Text(tr("Khi cắm ổ đĩa ngoài, chúng sẽ hiện ở đây.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 70).glassSurface(radius: 14, strong: false)
            } else {
                ForEach(drives) { dr in
                    let used = 1 - Double(dr.available) / Double(max(1, dr.total))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "externaldrive.fill").foregroundStyle(.white)
                            Text(dr.name).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer()
                            Button(tr("Tháo")) { try? NSWorkspace.shared.unmountAndEjectDevice(at: dr.id); Task { try? await Task.sleep(nanoseconds: 1_000_000_000); close() } }
                                .buttonStyle(MiniButtonStyle())
                        }
                        MeterBar(value: used, color: used > 0.9 ? Theme.danger : Color.white.opacity(0.9), height: 5)
                        Text(trf("Còn trống: %@ / %@", ByteFormat.string(dr.available), ByteFormat.string(dr.total))).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassSurface(radius: 14, strong: false)
                }
            }
        }
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
