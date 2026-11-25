import SwiftUI
import CoreKit
import ServiceManagement
import SafetyLayer
import ScanEngine
import RuleEngine
import Modules

enum Page: String, CaseIterable, Identifiable {
    case smartScan, systemJunk, devJunk, ai, trash, privacy, mail, photoJunk
    case protection, malware, optimization, maintenance
    case uninstaller, extensions, updater
    case spaceLens, largeFiles, duplicates, cloud
    case quarantine
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smartScan: "Smart Scan"; case .systemJunk: tr("Rác hệ thống"); case .devJunk: "Dev Junk"; case .ai: "AI Tools"; case .trash: tr("Dọn thùng rác")
        case .mail: tr("Mail đính kèm"); case .photoJunk: tr("Rác ảnh"); case .privacy: tr("Quyền riêng tư"); case .protection: tr("Bảo vệ"); case .malware: tr("Gỡ malware"); case .optimization: tr("Tối ưu"); case .maintenance: tr("Bảo trì")
        case .uninstaller: tr("Gỡ ứng dụng"); case .extensions: tr("Tiện ích mở rộng"); case .updater: tr("Trình cập nhật"); case .spaceLens: "Space Lens"
        case .largeFiles: tr("File lớn & cũ"); case .duplicates: tr("File trùng lặp"); case .cloud: "Cloud Cleanup"; case .quarantine: tr("Quarantine")
        }
    }
    var icon: String {
        switch self {
        case .smartScan: "sparkles"; case .systemJunk: "tray.full"; case .devJunk: "hammer"; case .ai: "brain"; case .trash: "trash"
        case .mail: "envelope"; case .photoJunk: "photo"; case .privacy: "hand.raised"; case .protection: "shield"; case .malware: "v.malware"; case .optimization: "bolt"; case .maintenance: "wrench.and.screwdriver"
        case .uninstaller: "xmark.app"; case .extensions: "puzzlepiece.extension"; case .updater: "arrow.down.circle"; case .spaceLens: "chart.pie"
        case .largeFiles: "doc.badge.clock"; case .duplicates: "square.on.square"; case .cloud: "icloud"; case .quarantine: "archivebox"
        }
    }
    static var groups: [(String, [Page])] { [
        ("", [.smartScan]),
        (tr("Dọn dẹp"), [.systemJunk, .mail, .photoJunk, .devJunk, .ai, .trash, .privacy]),
        (tr("Bảo vệ"), [.protection, .malware]),
        (tr("Tốc độ"), [.optimization, .maintenance]),
        (tr("Ứng dụng"), [.uninstaller, .extensions, .updater]),
        (tr("File"), [.spaceLens, .largeFiles, .duplicates, .cloud]),
    ] }
    /// Module dọn dẹp tương ứng, nếu có.
    var cleanupID: String? {
        switch self { case .systemJunk: "system-junk"; case .devJunk: "dev-junk"; case .ai: "ai"; case .trash: "trash"; case .privacy: "privacy"; case .mail: "mail"; case .photoJunk: "photos"; default: nil }
    }
}

/// Nút hành động tuỳ chọn của thông báo (ngoài "Hoàn tác").
enum ToastAction: Equatable { case openUpdate, openApps, openTrash }

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
    @Published var netDownHistory: [Double] = []
    @Published var netUpHistory: [Double] = []
    /// Tổng dữ liệu đã tải/gửi từ lúc mở Vutidy (cộng dồn từ tốc độ mỗi lần đo).
    @Published var netDownTotal: Double = 0
    @Published var netUpTotal: Double = 0
    @Published var cpuUserHistory: [Double] = []
    @Published var cpuSystemHistory: [Double] = []
    @Published var recommendations: [Recommendation] = []
    @Published var alerts: [FileAlert] = []
    /// Mục người dùng đã xem và xác nhận an toàn (khoá "launch:<plist>" hoặc "file:<đường dẫn>"): không tính vào cảnh báo nữa. Lưu lại giữa các lần mở app.
    @Published var reviewedKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "reviewedItems") ?? [])
    func isReviewed(_ key: String) -> Bool { reviewedKeys.contains(key) }
    func setReviewed(_ key: String, _ on: Bool) {
        if on { reviewedKeys.insert(key) } else { reviewedKeys.remove(key) }
        UserDefaults.standard.set(Array(reviewedKeys), forKey: "reviewedItems")
        if on, key.hasPrefix("file:") { let p = String(key.dropFirst(5)); alerts.removeAll { $0.path == p } }
    }
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
    @Published var autoCheckApps: Bool = UserDefaults.standard.object(forKey: "autoCheckApps") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheckApps, forKey: "autoCheckApps"); if autoCheckApps { startAppUpdateSchedule() } }
    }
    /// Tự cài bản mới khi không dùng app (tắt mặc định: bản chưa ký bằng Developer ID có thể mất quyền Full Disk Access sau mỗi lần cập nhật).
    @Published var autoInstallUpdates: Bool = UserDefaults.standard.bool(forKey: "autoInstallUpdates") {
        didSet { UserDefaults.standard.set(autoInstallUpdates, forKey: "autoInstallUpdates") }
    }
    var selfUpdateTask: Task<Void, Never>?
    var autoInstallTried: AppVersion?
    @Published var notifyTrash: Bool = UserDefaults.standard.object(forKey: "notifyTrash") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notifyTrash, forKey: "notifyTrash") }
    }
    @Published var trashBytes: Int64 = 0
    @Published var fileReport: FileReport?
    @Published var fileChecking = false
    var trashWatchTask: Task<Void, Never>?
    @Published var outdatedApps: [OutdatedApp] = []
    @Published var outdatedLoading = false
    /// Cask đang được `brew upgrade` và lỗi của lần thử gần nhất. Giữ ở đây (không ở view) để chuyển tab rồi quay lại vẫn thấy.
    @Published var upgradingApps: Set<String> = []
    @Published var upgradeErrors: [String: String] = [:]
    @Published var lastAppsCheck: Date? = UserDefaults.standard.object(forKey: "lastAppsCheck") as? Date
    var appsCheckTask: Task<Void, Never>?
    @Published var lastUpdateCheck: Date? = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date
    /// Mặc định BẬT: giám sát file mới chạy ngay khi mở app, trừ khi bạn đã tắt trong Cài đặt (lựa chọn đó được giữ).
    @Published var realtimeAtLaunch: Bool = (UserDefaults.standard.object(forKey: "realtimeAtLaunch") as? Bool) ?? true {
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
    /// Dọn tự động ngay sau Smart Scan: chỉ mục An toàn mà hoàn tác được (vào Quarantine). Mặc định tắt.
    @Published var autoCleanAfterScan: Bool = UserDefaults.standard.bool(forKey: "autoCleanAfterScan") {
        didSet { UserDefaults.standard.set(autoCleanAfterScan, forKey: "autoCleanAfterScan") }
    }
    /// Dọn cache của app đang chạy (trình duyệt, Slack…): đóng app rồi mở lại sau khi dọn. Tắt thì các mục đó bị bỏ qua.
    @Published var quitAppsToClean: Bool = (UserDefaults.standard.object(forKey: "quitAppsToClean") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(quitAppsToClean, forKey: "quitAppsToClean") }
    }
    /// Tư vấn AI sau Smart Scan. Mặc định tắt: khi bật, số liệu tổng hợp (không đường dẫn) được gửi tới Claude API khi bạn bấm hỏi.
    @Published var aiAdvisorEnabled: Bool = UserDefaults.standard.bool(forKey: "aiAdvisorEnabled") {
        didSet { UserDefaults.standard.set(aiAdvisorEnabled, forKey: "aiAdvisorEnabled"); if !aiAdvisorEnabled { advice = nil; adviceError = nil; advicePlan = nil } }
    }
    /// Model đã chọn cho từng nguồn AI (khóa là `AdvisorProvider.rawValue`); rỗng = mặc định của công cụ.
    @Published var aiModels: [String: String] = (UserDefaults.standard.dictionary(forKey: "aiModels") as? [String: String]) ?? [:] {
        didSet { UserDefaults.standard.set(aiModels, forKey: "aiModels") }
    }
    /// Danh sách model lấy từ từng công cụ (đã tải trong phiên này).
    @Published var aiModelOptions: [String: [AdvisorModel]] = [:]
    @Published var aiProvider: AdvisorProvider = AdvisorProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(aiProvider.rawValue, forKey: "aiProvider") }
    }
    @Published var adviceSource: String?
    /// Kế hoạch hành động AI đề xuất (đã lọc theo hành động app cho phép) và các bước đã làm xong.
    @Published var advicePlan: AdvisorPlan?
    @Published var planDone: Set<String> = []
    @Published var aiHasKey: Bool = AdvisorKeychain.hasKey
    @Published var advice: String?
    @Published var adviceError: String?
    @Published var adviceLoading = false
    /// ClamAV tùy chọn (trang Malware): trạng thái cài đặt/cơ sở dữ liệu, việc đang chạy và thông báo kết quả.
    @Published var clamStatus: ClamAV.Status?
    @Published var clamBusy: String?
    @Published var clamMessage: String?
    /// Cho AI xin xem sâu một số nhóm khi cần (chi tiết chỉ-đọc, ẩn danh). Mặc định bật vì nó quyết định độ chính xác.
    @Published var aiDeepDive: Bool = (UserDefaults.standard.object(forKey: "aiDeepDive") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(aiDeepDive, forKey: "aiDeepDive") }
    }
    /// Nhóm AI đang/đã xin xem sâu và JSON chi tiết đã gửi ở vòng 2.
    @Published var adviceStatus: String?
    /// Phân tích phát hiện malware bằng AI (cùng nguồn/model với AI Advisor): kết luận theo `SecurityFinding.key`, và JSON đã gửi.
    @Published var malwareVerdicts: [String: MalwareVerdict] = [:]
    @Published var malwareAIBusy = false
    @Published var malwareAIError: String?
    @Published var malwareAISource: String?
    @Published var malwareAIPayload: String?
    // AI Advisor cho trang Protection (khóa kết quả là khóa "đã xác nhận an toàn": launch:<plist> / file:<đường dẫn>).
    @Published var protectionVerdicts: [String: MalwareVerdict] = [:]
    @Published var protectionAIBusy = false
    @Published var protectionAIError: String?
    @Published var protectionAISource: String?
    @Published var protectionAIPayload: String?
    @Published var adviceInspected: [String] = []
    @Published var adviceDetails: String?
    /// Khi dọn tự động: gồm cả mục An toàn KHÔNG hoàn tác được (lệnh docker/go/brew prune) và Thùng rác (xóa vĩnh viễn). Mặc định tắt.
    @Published var autoCleanIrreversible: Bool = UserDefaults.standard.bool(forKey: "autoCleanIrreversible") {
        didSet { UserDefaults.standard.set(autoCleanIrreversible, forKey: "autoCleanIrreversible") }
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
        Task.detached(priority: .utility) { ProcessRunner.warmUpLoginPath() }   // PATH của login shell: để thấy claude/agy/nvm… khi mở app từ Finder
        startPolling()
        SystemNotifier.shared.open = { [weak self] raw in
            guard let self, let page = Page(rawValue: raw) else { return }
            self.section = page; self.showMainWindow()
        }
        installKeyMonitor()
        renderPopoverSnapshotIfRequested()
        // Quay lại app từ System Settings → kiểm tra lại quyền để banner tự biến mất khi đã cấp.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFDA() }
        }
        if realtimeAtLaunch { setRealtime(true) }
        // Tự kiểm tra bản mới tối đa mỗi 24 giờ (cả khi app chạy lâu) và, nếu bật, tự cài lúc rảnh; chỉ khi chạy từ .app.
        if ProcessInfo.processInfo.environment["VUTIDY_PAGE"] == nil { startSelfUpdateWatch() }
        announceUpdateIfAny()
        if ProcessInfo.processInfo.environment["VUTIDY_PAGE"] == nil { startAppUpdateSchedule(); startTrashWatch() }
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
                Task { @MainActor in if id == "smart" { await self.runSmartScan(autoClean: false) } else if id == "malware" { await self.runMalwareCheck() } else { await self.scan(id) } }
            }
        }
        // Kiểm thử/chụp màn hình: VUTIDY_CHECKFILE=<đường dẫn> chạy "Kiểm tra file" ngay (không cần hộp chọn file).
        if let f = ProcessInfo.processInfo.environment["VUTIDY_CHECKFILE"] {
            Task { @MainActor in await self.checkFile(URL(fileURLWithPath: f)) }
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
                if ProcessInfo.processInfo.environment["VUTIDY_SCROLL_BOTTOM"] != nil { Self.devScrollToBottom(after: 3) }
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

    /// Bỏ cảnh báo real-time của file đã bị xoá/di chuyển (người dùng tự dọn ngoài app), các cảnh báo trùng đường dẫn,
    /// và dòng "file vừa quét" nếu file đó không còn.
    func pruneAlerts() {
        if let p = lastScanned, !FileManager.default.fileExists(atPath: p) { lastScanned = nil }
        guard !alerts.isEmpty else { return }
        var seen = Set<String>()
        let kept = alerts.filter { FileManager.default.fileExists(atPath: $0.path) && seen.insert($0.path).inserted }
        if kept.count != alerts.count { alerts = kept }
    }

    func pollSystem() {
        pruneAlerts()
        let s = sysmon.sample()
        if let prev = snapshot {
            let dt = min(10, max(0, s.date.timeIntervalSince(prev.date)))
            netDownTotal += s.network.downBytesPerSec * dt; netUpTotal += s.network.upBytesPerSec * dt
        }
        snapshot = s
        netDownHistory = Array((netDownHistory + [s.network.downBytesPerSec]).suffix(40))
        netUpHistory = Array((netUpHistory + [s.network.upBytesPerSec]).suffix(40))
        cpuHistory = Array((cpuHistory + [s.cpuLoad]).suffix(40))
        cpuUserHistory = Array((cpuUserHistory + [s.cpuUser]).suffix(40))
        cpuSystemHistory = Array((cpuSystemHistory + [s.cpuSystem]).suffix(40))
        var ctx = SystemContext(disk: s.disk, battery: s.battery)
        ctx.memory = s.memory
        ctx.devJunkSafeBytes = (results["dev-junk"] ?? []).filter { $0.safety == .safe }.reduce(0) { $0 + $1.allocatedSize }
        ctx.loginItems = smart?.launchItems.filter { $0.scope == .userAgent }.count ?? 0
        ctx.lastDeepScan = lastDeepScan
        ctx.trashBytes = trashBytes
        ctx.lastMalwareCheck = malwareReport?.date
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
        pruneAlerts()
        malwareScanning = true; malwareStatus = tr("Đang kiểm tra…")
        malwareVerdicts = [:]; malwareAIError = nil; malwareAISource = nil; malwareAIPayload = nil
        malwareReport = await MalwareCheck.run(progress: { [weak self] s in Task { @MainActor in self?.malwareStatus = s } })
        malwareScanning = false; malwareStatus = ""
        if ProcessInfo.processInfo.environment["VUTIDY_SCROLL_BOTTOM"] != nil { Self.devScrollToBottom(after: 1.5) }   // chỉ để chụp màn hình
    }

    // MARK: Xử lý phát hiện malware

    private func removeMalwareFinding(_ f: SecurityFinding) {
        malwareReport?.findings.removeAll { $0.key == f.key }
    }

    /// Chuyển file nghi ngờ vào Quarantine (khôi phục được trong 7 ngày). Launch item được tắt trước để dừng tiến trình đang chạy.
    func malwareQuarantine(_ f: SecurityFinding) async {
        guard f.canQuarantine, let path = f.path else { return }
        let url = URL(fileURLWithPath: path)
        if let why = executor.blocklist.reason(for: url) {
            notify(trf("Không thể cách ly: %@", "\(why)"), .error); return
        }
        if f.source == .launchItem, let label = f.label { _ = await Optimization.disableLaunchItem(plistPath: path, label: label) }
        let bytes = FileWalker.allocatedSize(of: url)
        do {
            try await executor.quarantine.add(url, ruleID: "malware.\(f.code)", bytes: bytes)
            executor.audit.append(AuditRecord(date: Date(), action: "quarantine", path: path, bytes: bytes,
                                              ruleID: "malware.\(f.code)", mode: "malware", result: "done"))
            removeMalwareFinding(f)
            notify(trf("Đã cách ly %@. Khôi phục tại Quarantine trong 7 ngày.", url.lastPathComponent))
        } catch {
            notify(trf("Không thể cách ly: %@", error.localizedDescription), .error)
        }
    }

    /// Cách ly file mà Real-time Monitor vừa báo. Vào Quarantine nên khôi phục được.
    func quarantineAlert(_ a: FileAlert) async {
        let url = URL(fileURLWithPath: a.path)
        if let why = executor.blocklist.reason(for: url) { notify(trf("Không thể cách ly: %@", "\(why)"), .error); return }
        let bytes = FileWalker.allocatedSize(of: url)
        do {
            try await executor.quarantine.add(url, ruleID: "realtime", bytes: bytes)
            executor.audit.append(AuditRecord(date: Date(), action: "quarantine", path: a.path, bytes: bytes, ruleID: "realtime", mode: "realtime", result: "done"))
            alerts.removeAll { $0.path == a.path }
            await refreshQuarantine()
            notify(trf("Đã chuyển %@ vào Quarantine.", url.lastPathComponent))
        } catch {
            notify(trf("Không thể cách ly: %@", error.localizedDescription), .error)
        }
    }

    /// Thu hồi quyền nhạy cảm (TCC) của một app, rồi bỏ nó khỏi danh sách.
    func revokePermissions(_ g: PermissionGrant) async {
        if let err = await TCCAudit.revoke(g) {
            notify(trf("Không thể thu hồi quyền: %@", err), .error); return
        }
        executor.audit.append(AuditRecord(date: Date(), action: "command", path: "tccutil reset \(g.rawServices.joined(separator: ",")) \(g.client)", bytes: 0,
                                          ruleID: "tcc-revoke", mode: "run", result: "done"))
        malwareReport?.permissions.removeAll { $0.id == g.id }
        notify(trf("Đã thu hồi quyền của %@", g.name))
    }

    func malwareDisable(_ f: SecurityFinding) async {
        guard f.canDisable, let path = f.path, let label = f.label else { return }
        let r = await Optimization.disableLaunchItem(plistPath: path, label: label)
        if r.ok { removeMalwareFinding(f); notify(trf("Đã tắt %@", label)) }
        else { notify(trf("Lỗi: %@", r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)), .error) }
    }

    func malwareIgnore(_ f: SecurityFinding) {
        MalwareStore.shared.ignore(f.key)
        removeMalwareFinding(f)
        malwareReport?.ignoredCount += 1
    }

    func malwareClearIgnored() async {
        MalwareStore.shared.clearIgnored()
        await runMalwareCheck()
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
        case "mail": return Cleaners.mail(rules: rules)
        case "photos": return Cleaners.photos(rules: rules)
        case "ai": return Cleaners.ai(rules: rules)
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

    /// Các app đang chạy phải đóng để dọn những mục đã chọn của `id`.
    func appsToQuit(for id: String) -> [RunningApp] {
        quitAppsToClean ? AppQuitter.running(for: (results[id] ?? []).filter(\.selected)) : []
    }

    /// `allowQuit`: false cho dọn tự động (không có người dùng): không bao giờ tự đóng app, mục cần đóng app bị bỏ qua.
    func clean(_ id: String, mode: CleanMode, quiet: Bool = false, allowQuit: Bool = true) async {
        guard !cleaning.contains(id) else { return }
        var items = results[id] ?? []
        cleaning.insert(id)

        // Mục cần app đang chạy: đóng app lịch sự (như Cmd+Q), app nào không thoát thì bỏ qua mục của nó. Xem trước không đóng gì.
        var reopen: [RunningApp] = []
        var skippedForApps: [RunningApp] = []
        if mode != .dryRun {
            let needed = AppQuitter.running(for: items.filter(\.selected))
            if !needed.isEmpty {
                if allowQuit && quitAppsToClean {
                    cleanProgress[id] = CleanProgress(done: 0, total: items.filter(\.selected).count,
                                                      current: trf("Đang đóng %@…", needed.map(\.name).joined(separator: ", ")))
                    let r = await AppQuitter.quit(needed)
                    reopen = r.quit; skippedForApps = r.refused
                } else { skippedForApps = needed }
                for i in items.indices where items[i].selected && skippedForApps.contains(where: { AppQuitter.item(items[i], needs: $0) }) {
                    items[i].selected = false
                }
            }
        }
        let selected = items.filter { $0.selected }
        cleanProgress[id] = CleanProgress(done: 0, total: selected.count, current: selected.first?.title ?? "")
        let report = await executor.clean(items, mode: mode, progress: { [weak self] done, total in
            Task { @MainActor in
                self?.cleanProgress[id] = CleanProgress(done: done, total: total, current: done < selected.count ? selected[done].title : "")
            }
        })
        cleaning.remove(id)
        cleanProgress[id] = nil
        await AppQuitter.relaunch(reopen)
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
        if !skippedForApps.isEmpty { message += " · " + trf("Bỏ qua mục của %@ vì ứng dụng chưa thoát", skippedForApps.map(\.name).joined(separator: ", ")) }
        if !quiet { notify(message, report.failures.isEmpty ? .success : .warning, undo: undo) }
        if id == "trash" { Task { await refreshTrashSize() } }
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

    /// `autoClean`: nil = theo cài đặt "Dọn tự động sau Smart Scan"; true/false = ép bật/tắt cho lần quét này.
    func runSmartScan(autoClean: Bool? = nil) async {
        guard !smartScanning else { return }
        smartScanning = true
        let rules = RuleLoader.loadAll()
        let roots = projectRoots.map { URL(fileURLWithPath: expandTilde($0)) }
        let mods: [CleanerModule] = [Cleaners.systemJunk(rules: rules), DevJunkModule(rules: rules, projectRoots: roots, staleProjectDays: staleProjectDays), Cleaners.ai(rules: rules), TrashModule()]
        // Chạy song song: dọn dẹp + persistence + tối ưu, kiểm tra malware, và phần Smart Care (ứng dụng, file lớn…).
        async let careTask = SmartCare.gather()
        async let malwareTask: Void = runMalwareCheck()
        let r = await SmartScan.run(modules: mods, progress: { [weak self] s in Task { @MainActor in self?.status["smart"] = s } })
        advice = nil; adviceError = nil; advicePlan = nil; planDone = []
        smart = r
        care = await careTask
        await malwareTask
        lastDeepScan = Date(); UserDefaults.standard.set(lastDeepScan, forKey: "lastDeepScan")
        // Chia kết quả về từng module để các màn chi tiết dùng lại.
        for id in ["system-junk", "dev-junk", "ai", "trash"] { results[id] = [] }
        for item in r.cleanup {
            results[ModuleRouting.moduleID(forRuleID: item.ruleID, rules: rules), default: []].append(item)
        }
        for id in results.keys { results[id]?.sort { $0.allocatedSize > $1.allocatedSize } }
        smartScanning = false; status["smart"] = nil
        pollSystem()
        if ProcessInfo.processInfo.environment["VUTIDY_FAKE_ADVICE"] != nil { installFakeAdvice() }
        if autoClean ?? autoCleanAfterScan { await autoCleanSafe() }
    }

    /// Dọn tất cả mục `safe` đã quét bởi Smart Scan.
    func cleanSmart(mode: CleanMode) async {
        for id in ["system-junk", "dev-junk", "ai", "trash"] {
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
                                    onAlert: { [weak self] a in Task { @MainActor in guard let self, !self.isReviewed("file:" + a.path) else { return }; self.alerts.insert(a, at: 0) } })
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
        case .openSmartScan: section = .smartScan
        case .openMalware: section = .malware
        case .openTrash: section = .trash
        }
        showMainWindow()
    }
}
