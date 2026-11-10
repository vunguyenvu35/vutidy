import SwiftUI
import CoreKit
import ServiceManagement
import SafetyLayer
import ScanEngine
import RuleEngine
import Modules

enum Page: String, CaseIterable, Identifiable {
    case smartScan, systemJunk, devJunk, trash, privacy
    case protection, malware, optimization, maintenance
    case uninstaller, updater
    case spaceLens, largeFiles, duplicates, cloud
    case quarantine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smartScan: "Smart Scan"; case .systemJunk: tr("Rác hệ thống"); case .devJunk: "Dev Junk"; case .trash: tr("Thùng rác")
        case .privacy: tr("Quyền riêng tư"); case .protection: tr("Bảo vệ"); case .malware: "Malware"; case .optimization: tr("Tối ưu"); case .maintenance: tr("Bảo trì")
        case .uninstaller: tr("Gỡ ứng dụng"); case .updater: tr("Cập nhật"); case .spaceLens: "Space Lens"
        case .largeFiles: tr("File lớn & cũ"); case .duplicates: tr("File trùng lặp"); case .cloud: "Cloud Cleanup"; case .quarantine: tr("Quarantine")
        }
    }
    var icon: String {
        switch self {
        case .smartScan: "sparkles"; case .systemJunk: "tray.full"; case .devJunk: "hammer"; case .trash: "trash"
        case .privacy: "hand.raised"; case .protection: "shield"; case .malware: "v.malware"; case .optimization: "bolt"; case .maintenance: "wrench.and.screwdriver"
        case .uninstaller: "xmark.app"; case .updater: "arrow.down.circle"; case .spaceLens: "chart.pie"
        case .largeFiles: "doc.badge.clock"; case .duplicates: "square.on.square"; case .cloud: "icloud"; case .quarantine: "archivebox"
        }
    }
    static var groups: [(String, [Page])] { [
        ("", [.smartScan]),
        (tr("Dọn dẹp"), [.systemJunk, .devJunk, .trash, .privacy]),
        (tr("Bảo vệ"), [.protection, .malware]),
        (tr("Tốc độ"), [.optimization, .maintenance]),
        (tr("Ứng dụng"), [.uninstaller, .updater]),
        (tr("File"), [.spaceLens, .largeFiles, .duplicates, .cloud]),
    ] }
    /// Module dọn dẹp tương ứng, nếu có.
    var cleanupID: String? {
        switch self { case .systemJunk: "system-junk"; case .devJunk: "dev-junk"; case .trash: "trash"; case .privacy: "privacy"; default: nil }
    }
}

/// Nút hành động tuỳ chọn của thông báo (ngoài "Hoàn tác").
enum ToastAction: Equatable { case openUpdate }

struct AppToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let kind: ToastKind
    let undo: Bool
    var action: ToastAction? = nil
}

/// Trạng thái cập nhật chính Vutidy.
enum UpdateState: Equatable {
    case idle, checking, upToDate
    case available(ReleaseInfo)
    case downloading(Double)
    case installing
    case failed(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var section: Page = .smartScan
    @Published var results: [String: [ScanItem]] = [:]
    @Published var scanning: Set<String> = []
    /// Các trang đang dọn (khóa nút, hiện tiến độ).
    @Published var cleaning: Set<String> = []
    @Published var cleanProgress: [String: CleanProgress] = [:]
    /// Lần quét hoàn tất gần nhất của từng trang — để nói rõ "đã kiểm tra lúc …" khi không có gì để dọn.
    @Published var lastChecked: [String: Date] = [:]
    /// Kết quả lần dọn gần nhất của từng trang (hiện thành màn hoàn tất thay vì nhảy về "gọn gàng").
    @Published var cleanSummary: [String: CleanSummary] = [:]
    @Published var status: [String: String] = [:]
    @Published var language: Language = L10n.preference {
        didSet { L10n.preference = language; pollSystem() }
    }
    @Published var mode: CleanMode = .quarantine
    @Published var lastReport: CleanReport?
    /// Hàng đợi thông báo: cũ ở trên, mới nhất ở dưới cùng (góc phải-dưới).
    @Published var toasts: [AppToast] = []
    static let maxToasts = 4

    /// Giữ cú pháp cũ: gán chuỗi = thêm một thông báo thành công; gán nil = xóa tất cả.
    var toast: String? {
        get { toasts.last?.text }
        set { if let t = newValue { notify(t) } else { toasts.removeAll() } }
    }

    /// Hiện thông báo với loại (thành công/cảnh báo/lỗi) và tuỳ chọn nút "Hoàn tác".
    func notify(_ text: String, _ kind: ToastKind = .success, undo: Bool = false, action: ToastAction? = nil) {
        toasts.removeAll { $0.text == text }                      // trùng nội dung → làm mới thay vì xếp chồng
        toasts.append(AppToast(text: text, kind: kind, undo: undo, action: action))
        if toasts.count > Self.maxToasts { toasts.removeFirst(toasts.count - Self.maxToasts) }
    }

    func dismissToast(_ id: UUID) { toasts.removeAll { $0.id == id } }
    @Published var quarantineEntries: [QuarantineEntry] = []
    @Published var quarantineBytes: Int64 = 0

    @Published var smart: SmartScanResult?
    @Published var smartScanning = false
    /// Trang đang hiện thanh hành động ghim ở đáy (không phải trang dọn dẹp) → chồng thông báo tránh đè lên.
    @Published var pinnedBarVisible = false
    @Published var snapshot: SystemSnapshot?
    @Published var cpuHistory: [Double] = []
    @Published var recommendations: [Recommendation] = []
    @Published var alerts: [FileAlert] = []
    @Published var lastScanned: String?
    @Published var realtimeOn = false
    @Published var confirmBeforeClean: Bool = UserDefaults.standard.object(forKey: "confirmBeforeClean") as? Bool ?? true {
        didSet { UserDefaults.standard.set(confirmBeforeClean, forKey: "confirmBeforeClean") }
    }
    /// "" = phông hệ thống (mặc định).
    @Published var fontFamily: String = FontPrefs.family ?? "" {
        didSet {
            UserDefaults.standard.set(fontFamily, forKey: "fontFamily")
            FontPrefs.family = fontFamily.isEmpty ? nil : fontFamily
        }
    }
    @Published var fontScale: Double = Double(FontPrefs.scale) {
        didSet {
            UserDefaults.standard.set(fontScale, forKey: "fontScale")
            FontPrefs.scale = CGFloat(fontScale)
        }
    }
    /// Đổi một trong hai → dựng lại toàn bộ giao diện để mọi chữ lấy phông/cỡ mới.
    var typographyKey: String { "\(fontFamily)|\(fontScale)" }

    @Published var reduceMotion: Bool = UserDefaults.standard.bool(forKey: "reduceMotion") {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion") }
    }
    /// Cập nhật Vutidy: chỉ hỏi GitHub số phiên bản mới nhất (không gửi gì về máy bạn).
    @Published var appUpdate: UpdateState = .idle
    @Published var autoCheckUpdates: Bool = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates") }
    }
    @Published var lastUpdateCheck: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
    @Published var realtimeAtLaunch: Bool = UserDefaults.standard.bool(forKey: "realtimeAtLaunch") {
        didSet { UserDefaults.standard.set(realtimeAtLaunch, forKey: "realtimeAtLaunch") }
    }
    /// Khởi động cùng macOS (đăng nhập). Trạng thái lấy trực tiếp từ hệ thống, không lưu riêng.
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            toast = tr("Không thể thay đổi mục khởi động cùng máy.")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if on && SMAppService.mainApp.status == .requiresApproval {
            toast = tr("Hãy cho phép Vutidy trong Cài đặt hệ thống → Mục đăng nhập.")
        }
    }
    @Published var staleProjectDays: Int = UserDefaults.standard.object(forKey: "staleProjectDays") as? Int ?? 60 {
        didSet { UserDefaults.standard.set(staleProjectDays, forKey: "staleProjectDays") }
    }
    @Published var defaultMode: CleanMode = CleanMode(rawValue: UserDefaults.standard.string(forKey: "defaultMode") ?? "") ?? .quarantine {
        didSet { UserDefaults.standard.set(defaultMode.rawValue, forKey: "defaultMode"); mode = defaultMode }
    }
    /// Tâm 3 nút đèn giao thông tính từ mép trên cửa sổ (pt) — để logo thẳng hàng với chúng.
    @Published var titleBarCenter: CGFloat = 15
    /// Hộp thoại xác nhận đang hiển thị (xem `confirmDialog`).
    @Published var confirmRequest: ConfirmRequest?
    @Published var settingsOpen = false
    @Published var settingsPage: SettingsPage = .general
    @Published var paletteOpen = false {
        didSet { if paletteOpen { paletteQuery = ""; paletteIndex = 0 } }
    }
    @Published var paletteQuery = ""
    @Published var paletteIndex = 0
    let shortcuts = ShortcutStore()
    var keyMonitor: Any?
    /// Do PopoverView gán (cần `openWindow` của SwiftUI) để mở lại cửa sổ chính khi app đang ẩn ở menu bar.
    var openMainWindow: (() -> Void)?
    @Published var hasFDA = true
    /// Thùng rác của user không đọc được (thiếu Full Disk Access) → không hiển thị số 0 gây hiểu nhầm.
    @Published var trashBlocked = false
    /// Cửa sổ chính đang ở chế độ full screen (không có nút đèn giao thông, không có toolbar).
    @Published var isFullScreen = false
    /// Kết quả kiểm tra malware gần nhất — giữ ở đây để không mất khi chuyển trang.
    @Published var malwareReport: MalwareReport?
    @Published var malwareScanning = false
    /// Phần Smart Care ngoài dọn dẹp (cập nhật app, app ít dùng, file lớn và cũ, mục mở khi đăng nhập) — chỉ để xem.
    @Published var care: SmartCareSummary?
    @Published var malwareStatus = ""
    @Published var fdaDismissed = false
    @Published var lastDeepScan: Date? = UserDefaults.standard.object(forKey: "lastDeepScan") as? Date

    @Published var projectRoots: [String] = UserDefaults.standard.stringArray(forKey: "projectRoots") ?? [] {
        didSet { UserDefaults.standard.set(projectRoots, forKey: "projectRoots") }
    }
    @Published var retentionDays: Int = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 7 {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
            executor = ActionExecutor(paths: .default, retentionDays: retentionDays)
            Task { await refreshQuarantine() }
        }
    }

    private(set) var executor: ActionExecutor
    let sysmon = SystemMonitor()
    let dismissStore = DismissStore()
    private var realtime: RealtimeMonitor?
    private var timer: Timer?

    init() {
        let days = UserDefaults.standard.object(forKey: "retentionDays") as? Int ?? 7
        executor = ActionExecutor(paths: .default, retentionDays: days)
        mode = defaultMode
        checkFDA()
        Task { await refreshQuarantine(purgeExpired: true) }
        startPolling()
        installKeyMonitor()
        renderPopoverSnapshotIfRequested()
        // Quay lại app từ System Settings → kiểm tra lại quyền để banner tự biến mất khi đã cấp.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFDA() }
        }
        if realtimeAtLaunch { setRealtime(true) }
        // Tự kiểm tra bản mới tối đa mỗi 24 giờ, chỉ khi chạy từ .app (bản swift run không tự cập nhật được).
        if autoCheckUpdates, AppDelegate.canRelaunch, ProcessInfo.processInfo.environment["VUTIDY_PAGE"] == nil,
           Date().timeIntervalSince(lastUpdateCheck ?? .distantPast) > 24 * 3600 {
            Task { @MainActor in try? await Task.sleep(nanoseconds: 4_000_000_000); await self.checkForUpdates(silent: true) }
        }
        // Thử luồng cập nhật: VUTIDY_UPDATE_FEED=file://… (xem UpdateChecker) + VUTIDY_UPDATE_AUTOINSTALL=1 tự cài khi có bản mới.
        if ProcessInfo.processInfo.environment["VUTIDY_UPDATE_FEED"] != nil {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.checkForUpdates()
                if ProcessInfo.processInfo.environment["VUTIDY_UPDATE_AUTOINSTALL"] != nil { await self.installUpdate() }
                if case .failed(let m) = self.appUpdate { FileHandle.standardError.write(Data("UPDATE FAILED: \(m)\n".utf8)) }
            }
        }
        // Dùng cho kiểm thử/chụp màn hình: VUTIDY_PAGE=<trang>, VUTIDY_OPEN=palette|settings|shortcuts|support
        if let p = ProcessInfo.processInfo.environment["VUTIDY_PAGE"], let page = Page(rawValue: p) { section = page }
        switch ProcessInfo.processInfo.environment["VUTIDY_OPEN"] {
        case "palette": paletteOpen = true
        case "confirm": confirmRequest = ConfirmRequest(title: "Clean 5,9 MB?", message: "This action cannot be undone.", confirmTitle: "Delete permanently", destructive: true, symbol: "v.trash", action: {})
        case "settings": settingsOpen = true
        case "shortcuts": settingsPage = .shortcuts; settingsOpen = true
        case "support": settingsPage = .support; settingsOpen = true
        default: break
        }
        // Chụp tài liệu: VUTIDY_SCAN=smart|<id,id…> tự chạy quét; VUTIDY_OPEN=popover mở popover thanh menu thành cửa sổ rời.
        if let ids = ProcessInfo.processInfo.environment["VUTIDY_SCAN"] {
            for id in ids.split(separator: ",").map(String.init) {
                Task { @MainActor in if id == "smart" { await self.runSmartScan() } else { await self.scan(id) } }
            }
        }
        if let sp = ProcessInfo.processInfo.environment["VUTIDY_SETTINGS"], let p = SettingsPage(rawValue: sp) { settingsPage = p; settingsOpen = true }
        if ProcessInfo.processInfo.environment["VUTIDY_OPEN"] == "fdaguide" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in PermissionGuide.shared.show(state: self, openSettings: false) }
        }
        if ProcessInfo.processInfo.environment["VUTIDY_OPEN"] == "popover" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                let host = NSHostingView(rootView: PopoverView().environmentObject(self).environmentObject(shortcuts).preferredColorScheme(.dark))
                let w = NSWindow(contentRect: NSRect(x: 80, y: 120, width: 380, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host; w.isOpaque = false; w.backgroundColor = .clear; w.level = .floating
                w.setContentSize(host.fittingSize); w.makeKeyAndOrderFront(nil)
                Self.docPopoverWindow = w
            }
        }
    }

    static var docPopoverWindow: NSWindow?

    // MARK: - Hệ thống

    func startPolling() {
        timer?.invalidate()
        _ = sysmon.sample()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSystem() }
        }
        pollSystem()
    }

    func pollSystem() {
        let s = sysmon.sample()
        snapshot = s
        cpuHistory = Array((cpuHistory + [s.cpuLoad]).suffix(40))
        var ctx = SystemContext(disk: s.disk, battery: s.battery)
        ctx.memory = s.memory
        ctx.devJunkSafeBytes = (results["dev-junk"] ?? []).filter { $0.safety == .safe }.reduce(0) { $0 + $1.allocatedSize }
        ctx.loginItems = smart?.launchItems.filter { $0.scope == .userAgent }.count ?? 0
        ctx.lastDeepScan = lastDeepScan
        recommendations = RecommendationEngine().cards(for: ctx, dismissed: dismissStore)
    }

    /// Thử mở các file chỉ Full Disk Access mới đọc được. `true` = đã cấp, `false` = bị từ chối (EPERM/EACCES),
    /// `nil` = không kết luận được (file không tồn tại) — tránh báo thiếu quyền chỉ vì máy không có thư mục Safari.
    nonisolated static func probeFullDiskAccess() -> Bool? {
        let home = NSHomeDirectory()
        let candidates = [
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Safari/History.db",
            home + "/Library/Mail",
        ]
        for p in candidates {
            let fd = open(p, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { return false }
        }
        return nil
    }

    func runMalwareCheck() async {
        guard !malwareScanning else { return }
        malwareScanning = true; malwareStatus = tr("Đang kiểm tra…")
        malwareReport = await MalwareCheck.run(progress: { [weak self] s in Task { @MainActor in self?.malwareStatus = s } })
        malwareScanning = false; malwareStatus = ""
    }

    func checkFDA() {
        // VUTIDY_FAKE_NOFDA: chỉ để chụp tài liệu / thử giao diện "chưa cấp quyền", không đụng tới quyền thật.
        hasFDA = ProcessInfo.processInfo.environment["VUTIDY_FAKE_NOFDA"] != nil ? false : (Self.probeFullDiskAccess() ?? true)
        trashBlocked = TrashModule.isBlocked
    }

    // MARK: - Quét & dọn

    func module(for id: String) -> CleanerModule {
        let rules = RuleLoader.loadAll()
        let roots = projectRoots.map { URL(fileURLWithPath: expandTilde($0)) }
        switch id {
        case "dev-junk": return DevJunkModule(rules: rules, projectRoots: roots, staleProjectDays: staleProjectDays)
        case "trash": return TrashModule()
        case "privacy": return Cleaners.privacy(rules: rules)
        default: return Cleaners.systemJunk(rules: rules)
        }
    }

    func scan(_ id: String) async {
        guard !scanning.contains(id) else { return }
        // Quét lại: GIỮ nguyên kết quả đang hiển thị (không xóa về nil) → màn hình không nháy sang màn "đang quét" rồi quay lại.
        // Chỉ lần quét đầu tiên mới hiện màn đang quét toàn trang.
        scanning.insert(id); cleanSummary[id] = nil
        let started = Date()
        let m = module(for: id)
        let items = (try? await m.scan(progress: { [weak self] s in Task { @MainActor in self?.status[id] = s } })) ?? []
        // Quét quá nhanh (ví dụ Thùng rác trống) thì người dùng không thấy gì xảy ra → giữ trạng thái "đang quét" tối thiểu ~0,8 giây.
        let elapsed = Date().timeIntervalSince(started)
        if elapsed < 0.8 { try? await Task.sleep(nanoseconds: UInt64((0.8 - elapsed) * 1_000_000_000)) }
        withAnimation(.easeInOut(duration: 0.3)) {
            results[id] = items.sorted { $0.allocatedSize > $1.allocatedSize }
        }
        lastChecked[id] = Date()
        scanning.remove(id); status[id] = nil
        pollSystem()
    }

    func toggle(_ id: String, itemID: UUID) {
        guard let i = results[id]?.firstIndex(where: { $0.id == itemID }) else { return }
        results[id]![i].selected.toggle()
    }

    func setGroup(_ id: String, category: String, selected: Bool) {
        guard var arr = results[id] else { return }
        for i in arr.indices where arr[i].category == category { arr[i].selected = selected }
        results[id] = arr
    }

    func selectedBytes(_ id: String) -> Int64 {
        (results[id] ?? []).filter(\.selected).reduce(0) { $0 + $1.allocatedSize }
    }

    func clean(_ id: String, mode: CleanMode) async {
        guard !cleaning.contains(id) else { return }
        let items = results[id] ?? []
        let selected = items.filter { $0.selected }
        cleaning.insert(id)
        cleanProgress[id] = CleanProgress(done: 0, total: selected.count, current: selected.first?.title ?? "")
        let report = await executor.clean(items, mode: mode, progress: { [weak self] done, total in
            Task { @MainActor in
                self?.cleanProgress[id] = CleanProgress(done: done, total: total, current: done < selected.count ? selected[done].title : "")
            }
        })
        cleaning.remove(id)
        cleanProgress[id] = nil
        lastReport = report
        let done = Set(report.outcomes.filter { $0.status == .done }.map(\.itemID))
        // Các mục đã dọn mờ đi và co lại có hoạt ảnh; kết quả được ghi lại để hiện màn hoàn tất thay vì bật đột ngột.
        withAnimation(.easeInOut(duration: 0.4)) {
            results[id] = items.filter { !done.contains($0.id) }
            if mode != .dryRun {
                cleanSummary[id] = CleanSummary(bytes: report.reclaimedBytes, done: report.doneCount,
                                                failed: report.failures.count, skipped: report.skipped.count, mode: mode)
            }
        }
        await refreshQuarantine()
        var message: String
        var undo = false
        switch mode {
        case .dryRun: message = trf("Xem trước: sẽ giải phóng %@", "\(ByteFormat.string(report.reclaimedBytes))")
        case .quarantine:
            message = trf("Đã chuyển %@ vào Quarantine · hoàn tác trong %@ ngày", "\(ByteFormat.string(report.reclaimedBytes))", "\(retentionDays)")
            undo = true
        case .moveToTrash: message = trf("Đã chuyển %@ vào Thùng rác", "\(ByteFormat.string(report.reclaimedBytes))")
        case .permanent: message = trf("Đã xóa %@", "\(ByteFormat.string(report.reclaimedBytes))")
        }
        if !report.failures.isEmpty { message += trf(" · %@ lỗi", "\(report.failures.count)") }
        notify(message, report.failures.isEmpty ? .success : .warning, undo: undo)
        pollSystem()
    }

    func refreshQuarantine(purgeExpired: Bool = false) async {
        if purgeExpired { await executor.quarantine.purgeExpired() }
        quarantineEntries = await executor.quarantine.entries()
        quarantineBytes = await executor.quarantine.totalBytes()
    }

    func restore(_ id: UUID) async {
        do { let u = try await executor.quarantine.restore(id); toast = trf("Đã khôi phục: %@", "\(u.lastPathComponent)") }
        catch { notify(trf("Không khôi phục được: %@", "\(error.localizedDescription)"), .error) }
        await refreshQuarantine()
    }

    func purge(_ id: UUID) async { await executor.quarantine.purge(id); await refreshQuarantine() }

    // MARK: - Smart Scan

    func runSmartScan() async {
        guard !smartScanning else { return }
        smartScanning = true
        let rules = RuleLoader.loadAll()
        let roots = projectRoots.map { URL(fileURLWithPath: expandTilde($0)) }
        let mods: [CleanerModule] = [Cleaners.systemJunk(rules: rules), DevJunkModule(rules: rules, projectRoots: roots, staleProjectDays: staleProjectDays), TrashModule()]
        // Chạy song song: dọn dẹp + persistence + tối ưu, kiểm tra malware, và phần Smart Care (ứng dụng, file lớn…).
        async let careTask = SmartCare.gather()
        async let malwareTask: Void = runMalwareCheck()
        let r = await SmartScan.run(modules: mods, progress: { [weak self] s in Task { @MainActor in self?.status["smart"] = s } })
        smart = r
        care = await careTask
        await malwareTask
        lastDeepScan = Date(); UserDefaults.standard.set(lastDeepScan, forKey: "lastDeepScan")
        // Chia kết quả về từng module để các màn chi tiết dùng lại.
        for id in ["system-junk", "dev-junk", "trash"] { results[id] = [] }
        for item in r.cleanup {
            results[ModuleRouting.moduleID(forRuleID: item.ruleID, rules: rules), default: []].append(item)
        }
        for id in results.keys { results[id]?.sort { $0.allocatedSize > $1.allocatedSize } }
        smartScanning = false; status["smart"] = nil
        pollSystem()
    }

    /// Dọn tất cả mục `safe` đã quét bởi Smart Scan.
    func cleanSmart(mode: CleanMode) async {
        for id in ["system-junk", "dev-junk", "trash"] {
            guard var arr = results[id] else { continue }
            for i in arr.indices { arr[i].selected = arr[i].safety == .safe }
            results[id] = arr
            await clean(id, mode: id == "trash" && mode != .dryRun ? .permanent : mode)
        }
        var r = smart ?? SmartScanResult()
        r.cleanup = results.values.flatMap { $0 }
        smart = r
    }

    // MARK: - Real-time monitor

    func setRealtime(_ on: Bool) {
        realtimeOn = on
        if on {
            let m = RealtimeMonitor(onScan: { [weak self] p in Task { @MainActor in self?.lastScanned = p } },
                                    onAlert: { [weak self] a in Task { @MainActor in self?.alerts.insert(a, at: 0) } })
            m.start(); realtime = m
        } else { realtime?.stop(); realtime = nil }
    }

    func perform(_ a: RecommendationAction) {
        switch a {
        case .openCleanup, .thinSnapshots: section = .maintenance
        case .openSpaceLens: section = .spaceLens
        case .openDevJunk: section = .devJunk
        case .openUpdater: section = .updater
        case .openUninstaller: section = .uninstaller
        case .openOptimization, .openBattery: section = .optimization
        case .runDeepScan: section = .protection
        }
        showMainWindow()
    }
}
