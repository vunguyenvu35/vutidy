import SwiftUI
import AppKit
import CoreKit
import Modules
import SafetyLayer

// MARK: - Optimization

struct OptimizationView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var items: [LaunchItem] = []
    @ViewState private var consumers: [Optimization.Consumer] = []
    @ViewState private var loading = false
    @ViewState private var filter: Filter = .all
    @ViewState private var showAll = false
    @ViewState private var busy: Set<String> = []
    @ViewState private var memConsumers: [Optimization.Consumer] = []
    @ViewState private var sortMode: SortMode = .cpu
    @ViewState private var appMem: [Optimization.AppMemory] = []
    /// Các mục người dùng đã đảo trạng thái so với mặc định (mặc định: bật nếu app đang rảnh).
    @ViewState private var toggled: Set<Int32> = []
    @ViewState private var purging = false

    enum SortMode: Hashable { case cpu, ram }

    struct Reclaim: Identifiable {
        let g: Optimization.AppMemory
        let app: NSRunningApplication
        var id: Int32 { app.processIdentifier }
        var busy: Bool { g.cpu >= 15 }
    }

    /// App giao diện chịu trách nhiệm cho `pid` (đi ngược cây tiến trình: VM/helper → app chủ).
    func owningApp(_ pid: Int32) -> NSRunningApplication? {
        var cur: Int32? = pid
        for _ in 0..<8 {
            guard let c = cur, c > 1 else { return nil }
            if let a = NSRunningApplication(processIdentifier: c), a.activationPolicy == .regular { return a }
            cur = Optimization.parentPID(of: c)
        }
        return nil
    }

    /// Ứng viên để thoát: app nặng RAM THẬT (footprint, gồm cả máy ảo/helper và phần bị nén/swap), không phải app đang dùng.
    /// App đang bận CPU vẫn được liệt kê nhưng mặc định không chọn.
    var reclaimable: [Reclaim] {
        var seen = Set<Int32>()
        return appMem.compactMap { g in
            guard g.footprint >= 500_000_000, let app = owningApp(g.id), canQuit(app), !app.isActive,
                  seen.insert(app.processIdentifier).inserted else { return nil }
            return Reclaim(g: g, app: app)
        }
    }
    func isOn(_ r: Reclaim) -> Bool { r.busy == toggled.contains(r.id) }
    var selectedReclaim: [Reclaim] { reclaimable.filter(isOn) }

    enum Filter: String, CaseIterable {
        case all = "Tất cả", running = "Đang chạy", disabled = "Đã tắt", system = "Hệ thống"
        var title: String { tr(rawValue) }
    }

    var filtered: [LaunchItem] {
        items.filter { i in
            switch filter {
            case .all: return true
            case .running: return i.loaded && !i.disabled
            case .disabled: return i.disabled
            case .system: return i.requiresAdmin
            }
        }
    }
    var enabledCount: Int { items.filter { !$0.disabled }.count }
    var sortedConsumers: [Optimization.Consumer] { sortMode == .cpu ? consumers : memConsumers }
    var visibleConsumers: [Optimization.Consumer] { showAll ? Array(sortedConsumers.prefix(15)) : Array(sortedConsumers.prefix(6)) }

    /// Tên dễ hiểu: app thật dùng tên app; helper/VM hiện "App chủ · tiến trình" (ví dụ "Docker Desktop · com.apple.Virtualization…").
    func processName(_ c: Optimization.Consumer) -> String {
        if let n = NSRunningApplication(processIdentifier: c.id)?.localizedName { return n }
        if let owner = owningApp(c.owner)?.localizedName, owner != c.name { return "\(owner) · \(c.name)" }
        return c.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(caption: tr("Launch agents/daemons và tiến trình ngốn tài nguyên"), title: tr("Tối ưu"),
                       trailing: AnyView(Button { Task { await load() } } label: {
                           HStack(spacing: 6) {
                               if loading { VSpinner(size: 14, lineWidth: 2) } else { Image(systemName: "arrow.clockwise") }
                               Text(tr("Làm mới"))
                           }
                       }.buttonStyle(SecondaryButtonStyle()).disabled(loading)))
            gauges
            memoryCleaner
            processes
            startup
        }
        .smooth(items.count).smooth(consumers.count).smooth(filter).smooth(showAll)
        .task { await load() }
    }

    var gauges: some View {
        let s = state.snapshot
        let mem = s?.memory
        let used = mem.map { 1 - Double($0.available) / Double(max(1, $0.total)) } ?? 0
        let pressure = mem?.pressure ?? .normal
        let pColor: Color = pressure == .normal ? Theme.Signal.base : (pressure == .warning ? Theme.Review.base : Theme.danger)
        let pTitle = pressure == .normal ? tr("Bình thường") : (pressure == .warning ? tr("Cao") : tr("Nghiêm trọng"))
        return HStack(spacing: 16) {
            GaugeTile(title: tr("Tải CPU"), value: "\(Int((s?.cpuLoad ?? 0) * 100))%",
                      caption: consumers.first.map { trf("Cao nhất: %@", processName($0)) } ?? " ",
                      fraction: s?.cpuLoad ?? 0, color: Theme.Info.base, symbol: "cpu")
            GaugeTile(title: tr("Bộ nhớ"), value: mem.map { ByteFormat.string($0.available) + tr(" khả dụng") } ?? "—",
                      caption: trf("Áp lực bộ nhớ: %@", pTitle), fraction: used, color: pColor, symbol: "memorychip")
            GaugeTile(title: tr("Mục khởi động"), value: "\(enabledCount)",
                      caption: trf("%@ đang bật · %@ đã tắt", "\(enabledCount)", "\(items.count - enabledCount)"),
                      fraction: Double(enabledCount) / Double(max(items.count, 1)), color: Theme.orange, symbol: "power")
        }
    }

    var memoryCleaner: some View {
        let list = reclaimable
        let chosen = selectedReclaim
        let total = chosen.reduce(Int64(0)) { $0 + $1.g.footprint }
        return SectionCard(title: tr("Giải phóng bộ nhớ"),
                           subtitle: tr("App chiếm nhiều RAM thật (kể cả máy ảo và phần đã bị nén/swap). App đang bận không được chọn sẵn. Bạn xác nhận trước khi thoát."),
                           symbol: "memorychip", tint: Theme.orange,
                           trailing: {
            Button {
                Task {
                    purging = true
                    let r = await Optimization.purgeMemory()
                    if r.ok { state.notify(tr("Đã xóa cache bộ nhớ")) } else { state.notify(trf("Lỗi: %@", r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)), .error) }
                    purging = false; state.pollSystem()
                }
            } label: { Text(purging ? tr("Đang chạy…") : tr("Xóa cache (purge)")) }
                .buttonStyle(SecondaryButtonStyle()).disabled(purging)
                .help(tr("Hiệu quả ngắn hạn: macOS tự nạp lại cache khi cần. Cần quyền admin."))
        }) {
            if list.isEmpty {
                Text(tr("Không có app nào đáng thoát lúc này."))
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity).padding(24)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { idx, e in
                    let on = isOn(e)
                    ListRow(title: e.app.localizedName ?? e.g.name,
                            subtitle: ByteFormat.string(e.g.footprint) + (e.g.processCount > 1 ? " · " + trf("%@ tiến trình", "\(e.g.processCount)") : "")
                                + (e.busy ? " · " + trf("đang bận (CPU %@%%)", "\(Int(e.g.cpu))") : ""),
                            showDivider: idx < list.count - 1, leading: {
                        AppIconView(image: e.app.icon, fallback: "app.fill", size: 34)
                    }, trailing: {
                        Button { if toggled.contains(e.id) { toggled.remove(e.id) } else { toggled.insert(e.id) } } label: {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 20))
                                .foregroundStyle(on ? Theme.Signal.base : Theme.Text.tertiary)
                        }.buttonStyle(PlainPointerStyle())
                    })
                }
                HStack {
                    Text(trf("Có thể lấy lại khoảng %@", ByteFormat.string(total))).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    Spacer()
                    Button {
                        let apps = chosen.map(\.app)
                        apps.forEach { $0.terminate() }
                        state.toast = trf("Đã yêu cầu thoát %@ ứng dụng", "\(apps.count)")
                        toggled = []
                        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); await load(); state.pollSystem() }
                    } label: { Text(trf("Thoát %@ ứng dụng", "\(chosen.count)")) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(chosen.isEmpty)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    var processes: some View {
        SectionCard(title: sortMode == .cpu ? tr("Tiến trình ngốn CPU") : tr("Tiến trình ngốn RAM"),
                    subtitle: sortMode == .cpu ? tr("Sắp xếp theo mức dùng CPU") : tr("Sắp xếp theo mức dùng RAM"),
                    symbol: sortMode == .cpu ? "speedometer" : "memorychip", tint: Theme.Info.base,
                    trailing: {
            HStack(spacing: 12) {
                ChipPicker(options: [(SortMode.cpu, "CPU"), (SortMode.ram, "RAM")], selection: $sortMode)
                if sortedConsumers.count > 6 { Button(showAll ? tr("Thu gọn") : tr("Hiện tất cả")) { showAll.toggle() }.buttonStyle(TextActionStyle()) }
            }
        }) {
            if sortedConsumers.isEmpty {
                HStack(spacing: 10) { VSpinner(size: 18); Text(tr("Đang tính dung lượng…")).foregroundStyle(Theme.Text.secondary) }
                    .font(Theme.Font.caption).frame(maxWidth: .infinity).padding(28)
            }
            ForEach(Array(visibleConsumers.enumerated()), id: \.element.id) { idx, c in
                processRow(c, last: idx == visibleConsumers.count - 1)
            }
        }
    }

    func canQuit(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        return app.activationPolicy == .regular && app.bundleIdentifier != "com.apple.finder" && app.processIdentifier != getpid()
    }

    func processRow(_ c: Optimization.Consumer, last: Bool) -> some View {
        let app = NSRunningApplication(processIdentifier: c.id)
        let peak = max(100.0, consumers.first?.cpu ?? 100)
        let ramPeak = Double(max(1, memConsumers.first?.rssBytes ?? 1))
        let ram = sortMode == .ram
        return ListRow(title: processName(c),
                       subtitle: ram ? String(format: "CPU %.1f%%", c.cpu) : ByteFormat.string(c.rssBytes), showDivider: !last, leading: {
            AppIconView(image: app?.icon, fallback: "terminal.fill", size: 34)
        }, trailing: {
            // Cột nút (nếu có) → thanh đo → phần trăm: phần trăm luôn nằm sát mép phải thẻ, mọi dòng thẳng hàng.
            HStack(spacing: 14) {
                if canQuit(app) {
                    Button {
                        app?.terminate()
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); await load() }
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(diameter: 26)).help(tr("Thoát ứng dụng"))
                } else { Color.clear.frame(width: 26, height: 26) }
                MeterBar(value: ram ? Double(c.rssBytes) / ramPeak : c.cpu / peak,
                         color: ram ? Theme.orange : (c.cpu > 50 ? Theme.Review.base : Theme.Info.base), height: 8).frame(width: 190)
                Text(ram ? ByteFormat.string(c.rssBytes) : String(format: "%.1f%%", c.cpu)).font(.vt(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.Text.primary).frame(width: 70, alignment: .trailing)
            }
        })
    }

    var startup: some View {
        SectionCard(title: tr("Mục khởi động"), subtitle: tr("Bật hoặc tắt mục khởi động mà không xóa file."), symbol: "power", tint: Theme.orange,
                    trailing: { ChipPicker(options: Filter.allCases.map { ($0, $0.title) }, selection: $filter) }) {
            if filtered.isEmpty {
                Text(tr("Không có mục khởi động nào")).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
                    .frame(maxWidth: .infinity).padding(32)
            }
            ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, i in launchRow(i, last: idx == filtered.count - 1) }
        }
    }

    func launchRow(_ i: LaunchItem, last: Bool) -> some View {
        let appURL = AppLookup.bundleURL(containing: i.program)
        let title = appURL.map(AppLookup.name(forAppAt:)) ?? i.label
        let binding = Binding<Bool>(get: { !(items.first { $0.id == i.id }?.disabled ?? i.disabled) },
                                    set: { _ in Task { await toggle(i) } })
        return ListRow(title: title, subtitle: title == i.label ? (i.program ?? i.plist.path) : i.label, monoSubtitle: true, showDivider: !last, leading: {
            AppIconView(image: AppLookup.icon(forAppAt: appURL), fallback: "gearshape.fill", size: 34)
        }, trailing: {
            HStack(spacing: 10) {
                if i.requiresAdmin { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.Text.tertiary).help(tr("Cần admin")) }
                Pill(text: i.scope.rawValue)
                if i.loaded && !i.disabled { Pill(text: tr("Đang chạy"), color: Theme.Signal.text) }
                SwitchRow(isOn: binding, label: title).disabled(busy.contains(i.id))
            }
        })
    }

    func load() async {
        loading = true
        async let a = Optimization.launchItems()
        async let c = Optimization.heavyConsumers(limit: 12)
        async let m = Optimization.memoryConsumers(limit: 40)
        async let g = Optimization.memoryByApp(limit: 30)
        items = await a; consumers = await c; memConsumers = await m; appMem = await g; loading = false
    }

    func toggle(_ i: LaunchItem) async {
        busy.insert(i.id)
        let r = i.disabled ? await Optimization.enable(i) : await Optimization.disable(i)
        state.toast = r.ok ? "\(i.disabled ? tr("Đã bật") : tr("Đã tắt")) \(i.label)"
                           : trf("Lỗi: %@", r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        await load()
        busy.remove(i.id)
    }
}

// MARK: - Maintenance

struct MaintenanceView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var running: String?
    @ViewState private var output: [String: String] = [:]
    @ViewState private var snapshots: [String] = []

    func style(_ id: String) -> (String, Color) {
        switch id {
        case "flush-dns": return ("network", Theme.Info.base)
        case "purge-ram": return ("memorychip", Theme.orange)
        case "reindex-spotlight": return ("magnifyingglass", Theme.apps)
        case "thin-tm": return ("clock.arrow.circlepath", Theme.teal)
        case "rebuild-ls": return ("square.stack.3d.up.fill", Theme.pink)
        default: return ("checkmark.shield.fill", Theme.Signal.base)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(caption: tr("Chỉ các tác vụ còn có ý nghĩa trên macOS hiện đại"), title: tr("Bảo trì"))
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.Info.base)
                Text(tr("Đã loại bỏ: periodic scripts (đã deprecated) và repair disk permissions (vô nghĩa từ khi có SIP). Tác vụ cần admin sẽ hiện hộp thoại mật khẩu của hệ thống."))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Info.base.opacity(0.08)))

            SectionCard(title: tr("Tác vụ bảo trì"), symbol: "wrench.and.screwdriver.fill", tint: Theme.Info.base) {
                ForEach(Array(Maintenance.tasks.enumerated()), id: \.element.id) { idx, t in
                    let (sym, tint) = style(t.id)
                    VStack(spacing: 0) {
                        ListRow(title: t.title, subtitle: t.detail, showDivider: output[t.id] == nil && idx < Maintenance.tasks.count - 1, leading: {
                            IconTile(symbol: sym, tint: tint, size: 38)
                        }, trailing: {
                            HStack(spacing: 12) {
                                if t.needsAdmin { Label(tr("Cần admin"), systemImage: "lock.fill").font(Theme.Font.label).foregroundStyle(Theme.Text.tertiary) }
                                Button { Task { await run(t) } } label: {
                                    HStack(spacing: 6) { if running == t.id { VSpinner(size: 14, lineWidth: 2) }; Text(running == t.id ? tr("Đang chạy…") : tr("Chạy")) }
                                }.buttonStyle(SecondaryButtonStyle()).disabled(running != nil)
                            }
                        }).help("$ " + t.shell)
                        if let o = output[t.id], !o.isEmpty {
                            Text(o).font(Theme.Font.mono).foregroundStyle(Theme.Text.secondary).lineLimit(6)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.Bg.code)).padding(.horizontal, 18).padding(.bottom, 12)
                            if idx < Maintenance.tasks.count - 1 { Divider().overlay(Theme.Border.subtle).padding(.leading, 18) }
                        }
                    }
                }
            }
            if !snapshots.isEmpty {
                Label(trf("Time Machine local snapshot: %@", "\(snapshots.count)"), systemImage: "externaldrive.badge.timemachine")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            }
        }.task { snapshots = await Maintenance.localSnapshots() }
    }

    func run(_ t: MaintenanceTask) async {
        running = t.id
        let r = await Maintenance.run(t)
        output[t.id] = r.ok ? (r.stdout.isEmpty ? tr("Hoàn tất.") : String(r.stdout.suffix(600))) : trf("Lỗi (%@): %@", "\(r.status)", "\(r.stderr.prefix(300))")
        running = nil
        if r.ok { state.notify(trf("%@: hoàn tất", t.title)) } else { state.notify(trf("%@: thất bại", t.title), .error) }
        snapshots = await Maintenance.localSnapshots()
        state.pollSystem()
    }
}

// MARK: - Protection

struct ProtectionView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var items: [PersistenceItem] = []
    @ViewState private var scanning = false
    @ViewState private var scanned = false

    var flagged: Int { items.filter(\.suspicious).count }

    enum LaunchFilter: String, CaseIterable, Hashable {
        case all = "Tất cả", attention = "Cần chú ý", signed = "Đã ký"
        var title: String { tr(rawValue) }
    }
    @ViewState private var launchFilter: LaunchFilter = .all

    func matches(_ i: PersistenceItem, _ f: LaunchFilter) -> Bool {
        switch f { case .all: return true; case .attention: return i.trust.severity <= 1; case .signed: return i.trust.severity >= 2 }
    }
    var shownItems: [PersistenceItem] { items.filter { matches($0, launchFilter) } }

    var launchItemsCard: some View {
        SectionCard(title: tr("Launch items"), subtitle: tr("Mục đáng chú ý lên đầu"), symbol: "list.bullet.rectangle.fill", tint: Theme.Info.base,
                    trailing: {
            ChipPicker(options: LaunchFilter.allCases.map { f in (f, "\(f.title)  \(items.filter { matches($0, f) }.count)") }, selection: $launchFilter)
        }) {
            if shownItems.isEmpty {
                Text(items.isEmpty ? (scanning ? tr("Đang quét…") : tr("Chưa quét")) : tr("Không có mục nào trong bộ lọc này"))
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity).padding(32)
            }
            ForEach(Array(shownItems.enumerated()), id: \.element.id) { idx, i in
                PersistenceRow(item: i, showDivider: idx < shownItems.count - 1)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(caption: tr("Persistence scanner + giám sát file mới (FSEvents)"), title: tr("Bảo vệ"))
            hero
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.Review.base)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Đây không phải phần mềm diệt virus")).font(Theme.Font.heading).foregroundStyle(Theme.Review.text)
                    Text(tr("Vutidy chỉ liệt kê các điểm persistence phổ biến và kiểm tra chữ ký code. Real-time Monitor phát hiện file mới SAU KHI nó đã được ghi, không chặn được việc thực thi."))
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Review.tint))

            SectionCard(title: tr("Real-time Monitor"), symbol: "dot.radiowaves.left.and.right", tint: Theme.Signal.base) {
                ListRow(title: state.realtimeOn ? tr("Real-time bật") : tr("Real-time tắt"),
                        subtitle: state.lastScanned.map { trf("Lần quét gần nhất: %@", $0) } ?? tr("Theo dõi Downloads, Applications, LaunchAgents/Daemons…"),
                        monoSubtitle: state.lastScanned != nil, showDivider: false, leading: {
                    Circle().fill(state.realtimeOn ? Theme.Signal.base : Theme.Text.tertiary).frame(width: 10, height: 10).padding(.horizontal, 14)
                }, trailing: {
                    SwitchRow(isOn: Binding(get: { state.realtimeOn }, set: { state.setRealtime($0) }), label: tr("Real-time Monitor"))
                })
            }

            if !state.alerts.isEmpty {
                SectionCard(title: tr("Cảnh báo real-time"), symbol: "exclamationmark.triangle.fill", tint: Theme.Review.base) {
                    ForEach(Array(state.alerts.prefix(20).enumerated()), id: \.element.id) { idx, a in
                        ListRow(title: a.reason, subtitle: a.path, monoSubtitle: true, showDivider: idx < min(20, state.alerts.count) - 1, leading: {
                            IconTile(symbol: "exclamationmark", tint: Theme.Review.base, size: 34)
                        }, trailing: { EmptyView() })
                    }
                }
            }

            launchItemsCard
        }.smooth(items.count).smooth(scanned).smooth(scanning).task { if items.isEmpty { await scan() } }
    }

    var hero: some View {
        HStack(spacing: 20) {
            SolidIcon(symbol: flagged > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill",
                      tint: flagged > 0 ? Theme.Review.base : Theme.Signal.base, size: 68)
            VStack(alignment: .leading, spacing: 5) {
                Text(!scanned ? tr("Chưa quét") : (flagged == 0 ? tr("Mọi mục khởi động đều hợp lệ") : trf("%@ mục cần chú ý", "\(flagged)")))
                    .font(.vt(size: 22, weight: .bold)).foregroundStyle(Theme.Text.primary)
                Text(trf("%@ mục đã kiểm tra chữ ký", "\(items.count)")).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
            }
            Spacer()
            Button(scanning ? tr("Đang quét…") : tr("Quét persistence")) { Task { await scan() } }
                .buttonStyle(PrimaryButtonStyle()).disabled(scanning)
        }.card(hero: true)
    }

    func scan() async {
        scanning = true
        items = await Task.detached { PersistenceScanner.scan() }.value
        state.lastDeepScan = Date(); UserDefaults.standard.set(state.lastDeepScan, forKey: "lastDeepScan")
        scanning = false; scanned = true
    }
}

// MARK: - Updater

struct UpdaterView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var outdated: [OutdatedApp] = []
    @ViewState private var loading = false
    @ViewState private var checked = false
    @ViewState private var updating: Set<String> = []
    @ViewState private var errors: [String: String] = [:]
    @ViewState private var confirmAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(caption: tr("Cập nhật ứng dụng cài qua Homebrew chỉ với một cú bấm."), title: tr("Cập nhật ứng dụng"),
                       trailing: AnyView(HStack(spacing: 10) {
                           if !outdated.isEmpty {
                               Button { confirmAll = true } label: { IconLabel(title: tr("Cập nhật tất cả"), symbol: "v.updater") }
                                   .buttonStyle(PrimaryButtonStyle()).disabled(!updating.isEmpty)
                           }
                           Button(loading ? tr("Đang kiểm tra…") : tr("Kiểm tra")) { Task { await check() } }
                               .modifier(PrimaryOrSecondary(primary: outdated.isEmpty)).disabled(loading)
                       }))
            if !checked {
                ScanHero(page: .updater, title: tr("Cập nhật ứng dụng"), subtitle: tr("Hiện hỗ trợ cask Homebrew. Sparkle và App Store chưa được tích hợp trong giao diện."),
                         actionTitle: tr("Kiểm tra"), busy: loading) { Task { await check() } }
            } else if outdated.isEmpty {
                ScanHero(page: .updater, title: tr("Không có bản cập nhật nào được phát hiện"), subtitle: tr("Hiện hỗ trợ cask Homebrew. Sparkle và App Store chưa được tích hợp trong giao diện."),
                         actionTitle: tr("Kiểm tra lại")) { Task { await check() } }
            } else {
                SectionCard(title: tr("Cập nhật"), subtitle: trf("%@ mục", "\(outdated.count)"), symbol: "arrow.down.circle.fill", tint: Theme.Info.base) {
                    ForEach(Array(outdated.enumerated()), id: \.element.id) { idx, a in
                        VStack(spacing: 0) {
                            ListRow(title: a.name, subtitle: "\(a.installed) → \(a.latest)", monoSubtitle: true,
                                    showDivider: errors[a.id] == nil && idx < outdated.count - 1, leading: {
                                IconTile(symbol: "shippingbox.fill", tint: Theme.Info.base, size: 36)
                            }, trailing: {
                                HStack(spacing: 12) {
                                    Pill(text: a.source)
                                    if updating.contains(a.id) {
                                        HStack(spacing: 8) { VSpinner(size: 14, lineWidth: 2); Text(tr("Đang cập nhật…")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary) }
                                            .frame(minWidth: 130)
                                    } else {
                                        Button { Task { await upgrade(a) } } label: { IconLabel(title: tr("Cập nhật ngay"), symbol: "v.updater") }
                                            .buttonStyle(PrimaryButtonStyle()).controlSize(.small).frame(minWidth: 130)
                                    }
                                }
                            })
                            if let e = errors[a.id] {
                                Label(e, systemImage: "exclamationmark.triangle.fill").font(Theme.Font.caption).foregroundStyle(Theme.Review.text)
                                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 10)
                                if idx < outdated.count - 1 { Divider().overlay(Theme.Border.subtle).padding(.leading, 18) }
                            }
                        }
                    }
                }
            }
        }
        .smooth(checked).smooth(outdated.count).smooth(loading)
        .confirmDialog(isPresented: $confirmAll, title: trf("Cập nhật tất cả %@ ứng dụng?", "\(outdated.count)"),
                       message: tr("Vutidy sẽ chạy `brew upgrade --cask` cho từng ứng dụng. Ứng dụng đang mở có thể bị đóng và một số bản cần mật khẩu quản trị."),
                       confirmTitle: tr("Cập nhật tất cả"), symbol: "v.updater") {
            Task { for a in outdated { await upgrade(a) } }
        }
    }

    func check() async { loading = true; outdated = await Updater.brewOutdated(); loading = false; checked = true; errors = [:] }

    func upgrade(_ a: OutdatedApp) async {
        updating.insert(a.id); errors[a.id] = nil
        let r = await Updater.upgrade(a)
        state.executor.audit.append(AuditRecord(date: Date(), action: "command", path: "brew upgrade --cask \(a.name)", bytes: 0,
                                                ruleID: "updater", mode: "run", result: r.ok ? "done" : "failed: \(r.stderr.prefix(200))"))
        updating.remove(a.id)
        if r.ok {
            outdated.removeAll { $0.id == a.id }
            state.toast = trf("Đã cập nhật %@", a.name)
        } else {
            let line = r.stderr.split(separator: "\n").map(String.init).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "exit \(r.status)"
            errors[a.id] = line
            state.notify(trf("Cập nhật %@ thất bại", a.name), .error)
        }
    }
}

/// Chọn kiểu nút theo điều kiện (hai kiểu nút khác kiểu nên không thể dùng toán tử ba ngôi).
struct PrimaryOrSecondary: ViewModifier {
    let primary: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if primary { content.buttonStyle(PrimaryButtonStyle()) } else { content.buttonStyle(SecondaryButtonStyle()) }
    }
}

// MARK: - Quarantine

struct QuarantineView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var confirmDeleteAll = false
    @ViewState private var busyAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(caption: tr("Lưới an toàn: mọi thứ Vutidy dọn đều nằm ở đây trước"), title: "Quarantine")
            HStack(spacing: 20) {
                SolidIcon(symbol: "archivebox.fill", tint: Theme.Signal.base, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(trf("Đang giữ %@", ByteFormat.string(state.quarantineBytes))).font(.vt(size: 22, weight: .bold)).foregroundStyle(Theme.Text.primary)
                    Text(trf("%@ mục · khôi phục trong %@ ngày", "\(state.quarantineEntries.count)", "\(state.retentionDays)"))
                        .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
                }
                Spacer()
            }.card(hero: true)

            if state.quarantineEntries.isEmpty {
                ScanHero(page: .quarantine, title: tr("Quarantine trống"), subtitle: trf("Các mục đã dọn sẽ nằm ở đây %@ ngày trước khi bị xóa hẳn.", "\(state.retentionDays)"),
                         actionTitle: "") { }.opacity(0.9)
            } else {
                SectionCard(title: tr("Quarantine"), subtitle: trf("%@ mục", "\(state.quarantineEntries.count)"), symbol: "archivebox.fill", tint: Theme.Signal.base, trailing: {
                    HStack(spacing: 10) {
                        Button { Task { await restoreAll() } } label: { IconLabel(title: tr("Khôi phục tất cả"), symbol: "v.updater") }
                            .buttonStyle(SecondaryButtonStyle()).disabled(busyAll)
                        Button { confirmDeleteAll = true } label: { IconLabel(title: tr("Xóa tất cả"), symbol: "v.trash") }
                            .buttonStyle(DangerButtonStyle()).controlSize(.small).disabled(busyAll)
                    }
                }) {
                    ForEach(Array(state.quarantineEntries.enumerated()), id: \.element.id) { idx, e in
                        let days = e.daysLeft(retentionDays: state.retentionDays)
                        ListRow(title: URL(fileURLWithPath: e.originalPath).lastPathComponent,
                                subtitle: e.originalPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"), monoSubtitle: true,
                                showDivider: idx < state.quarantineEntries.count - 1, leading: {
                            AppIconView(image: NSWorkspace.shared.icon(forFile: e.storedPath), fallback: "doc", size: 34)
                        }, trailing: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Ring(segments: [.init(value: max(0.02, Double(days) / Double(max(1, state.retentionDays))), color: days <= 1 ? Theme.Review.base : Theme.Signal.base),
                                                    .init(value: 1, color: .clear)], lineWidth: 3)
                                    Text("\(days)").font(.vt(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.Text.secondary)
                                }.frame(width: 28, height: 28).help(trf("còn %@ ngày", "\(days)"))
                                Text(ByteFormat.string(e.bytes)).font(Theme.Font.body).monospacedDigit().foregroundStyle(Theme.Text.secondary).frame(width: 74, alignment: .trailing)
                                Button(tr("Khôi phục")) { Task { await state.restore(e.id) } }.buttonStyle(SecondaryButtonStyle())
                                Button { Task { await state.purge(e.id) } } label: { Image(systemName: "trash") }
                                    .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.tertiary).help(tr("Xóa vĩnh viễn"))
                            }
                        })
                    }
                }
            }
        }
        .smooth(state.quarantineEntries.count)
        .confirmDialog(isPresented: $confirmDeleteAll, title: trf("Xóa vĩnh viễn tất cả %@ mục?", "\(state.quarantineEntries.count)"),
                       message: tr("Mọi mục trong Quarantine sẽ bị xóa vĩnh viễn và không thể khôi phục."),
                       confirmTitle: tr("Xóa tất cả"), destructive: true, symbol: "v.trash") {
            Task { await deleteAll() }
        }
        .task { await state.refreshQuarantine(purgeExpired: true) }
    }
}


extension QuarantineView {
    func deleteAll() async {
        busyAll = true
        for e in state.quarantineEntries { await state.executor.quarantine.purge(e.id) }
        await state.refreshQuarantine()
        state.toast = tr("Đã dọn sạch Quarantine.")
        busyAll = false
    }

    func restoreAll() async {
        busyAll = true
        var ok = 0
        for e in state.quarantineEntries { if (try? await state.executor.quarantine.restore(e.id)) != nil { ok += 1 } }
        await state.refreshQuarantine()
        state.toast = trf("Đã khôi phục %@ mục", "\(ok)")
        busyAll = false
    }
}

// MARK: - Launch item row (Protection)

private struct TrustBadge: View {
    let trust: PersistenceItem.Trust
    var spec: (symbol: String, color: Color) {
        switch trust {
        case .unsigned, .missing: return ("exclamationmark.triangle.fill", Theme.Review.text)
        case .unreadable: return ("lock.fill", Theme.Text.secondary)
        case .empty, .unknown: return ("questionmark.circle.fill", Theme.Text.secondary)
        case .signed, .apple: return ("checkmark.seal.fill", Theme.Signal.text)
        }
    }
    var body: some View {
        let s = spec
        HStack(spacing: 5) {
            Image(systemName: s.symbol).font(.system(size: 10.5, weight: .semibold))
            Text(trust.title).font(Theme.Font.label)
        }
        .foregroundStyle(s.color).padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(s.color.opacity(trust.severity == 0 ? 0.16 : 0.10)))
        .fixedSize()
    }
}

private struct PersistenceRow: View {
    let item: PersistenceItem
    let showDivider: Bool
    @ViewState private var hover = false

    var body: some View {
        let appURL = AppLookup.bundleURL(containing: item.program).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        let title = appURL.map(AppLookup.name(forAppAt:)) ?? item.label
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                AppIconView(image: AppLookup.icon(forAppAt: appURL), fallback: fallbackSymbol, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.vt(size: 13.5, weight: .medium)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                        Text(item.scope.title).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).lineLimit(1)
                    }
                    Text(item.program ?? item.plist.path).font(Theme.Font.mono.leading(.tight)).foregroundStyle(Theme.Text.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    if let note = item.note, item.trust.severity <= 1 {
                        Text(note).font(Theme.Font.caption).foregroundStyle(item.suspicious ? Theme.Review.text : Theme.Text.tertiary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                TrustBadge(trust: item.trust)
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: {
                    Image(systemName: "folder").font(.system(size: 13))
                }.buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary).help(tr("Hiện trong Finder"))
            }
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(hover ? Color.white.opacity(0.035) : .clear)
            .onHover { hover = $0 }
            if showDivider { Divider().overlay(Theme.Border.subtle).padding(.leading, 18) }
        }
    }

    var fallbackSymbol: String {
        switch item.trust {
        case .unsigned, .missing: return "exclamationmark.triangle.fill"
        case .unreadable: return "lock.fill"
        case .empty, .unknown: return "questionmark.folder.fill"
        case .signed, .apple: return "gearshape.fill"
        }
    }
}
