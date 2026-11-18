import Foundation
import CoreKit
import ScanEngine

/// Một extension/plugin của bên thứ ba: hoặc là plugin file gỡ riêng được (Preference Pane, Internet Plug-In…),
/// hoặc là extension nằm trong app (`.appex`: Safari, Quick Look, Finder Sync, Share, Widget) chỉ bật/tắt được.
public struct ExtensionItem: Identifiable, Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable {
        // Plugin file, gỡ riêng được.
        case preferencePane, internetPlugin, spotlightPlugin, service, audioPlugin
        // Extension trong app (.appex), quản lý qua pluginkit.
        case safari, quickLook, finderSync, share, widget, other

        public var isAppExtension: Bool {
            switch self { case .safari, .quickLook, .finderSync, .share, .widget, .other: return true; default: return false }
        }
        public var title: String {
            switch self {
            case .preferencePane: return tr("Preference Panes")
            case .internetPlugin: return tr("Internet Plug-Ins")
            case .spotlightPlugin: return tr("Spotlight Plug-Ins")
            case .service: return tr("Services & Quick Actions")
            case .audioPlugin: return tr("Audio Plug-Ins")
            case .safari: return tr("Safari Extensions")
            case .quickLook: return tr("Quick Look")
            case .finderSync: return tr("Finder Sync")
            case .share: return tr("Share")
            case .widget: return tr("Widgets")
            case .other: return tr("Extension khác")
            }
        }
        public var symbol: String {
            switch self {
            case .preferencePane: return "gearshape"
            case .internetPlugin: return "globe"
            case .spotlightPlugin: return "magnifyingglass"
            case .service: return "bolt"
            case .audioPlugin: return "waveform"
            case .safari: return "safari"
            case .quickLook: return "eye"
            case .finderSync: return "folder"
            case .share: return "square.and.arrow.up"
            case .widget: return "square.grid.2x2"
            case .other: return "puzzlepiece.extension"
            }
        }
    }

    public var id: String { url.path }
    public var name: String
    public var kind: Kind
    public var url: URL
    public var bundleID: String?
    /// App chứa extension (chỉ với `.appex`).
    public var hostName: String?
    public var hostURL: URL?
    public var size: Int64
    /// `.appex`: chưa bị người dùng đặt "ignore" trong pluginkit. Plugin file luôn coi là bật.
    public var enabled: Bool
    /// Nằm ngoài thư mục người dùng (cần quyền admin để gỡ) hoặc trong app: không gỡ riêng từ đây.
    public var system: Bool

    public var removable: Bool { !kind.isAppExtension && !system }
}

public enum ExtensionScanner {
    // MARK: pluginkit (extension trong app)

    struct PluginKitRecord: Equatable {
        var bundleID: String
        var path: String
        var sdk: String?
        var parentPath: String?
        var displayName: String?
        var parentName: String?
        /// Dấu đầu dòng của pluginkit: "+" dùng, "-" bỏ qua, "!" dùng cho debug, "?" không rõ, rỗng = mặc định.
        var election: String
        var enabled: Bool { election != "-" }
    }

    /// Phân tích đầu ra của `pluginkit -mAvvv`: mỗi bản ghi mở đầu bằng "<dấu> id(phiên bản)" rồi các dòng "Khóa = giá trị", cách nhau bằng dòng trống.
    static func parsePluginKit(_ output: String) -> [PluginKitRecord] {
        var out: [PluginKitRecord] = []
        var cur: PluginKitRecord?
        func flush() { if let c = cur, !c.path.isEmpty { out.append(c) }; cur = nil }
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flush(); continue }
            if let eq = t.range(of: " = ") {
                guard cur != nil else { continue }
                let key = t[..<eq.lowerBound].trimmingCharacters(in: .whitespaces)
                let val = String(t[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "Path": cur?.path = val
                case "SDK": cur?.sdk = val
                case "Parent Bundle": cur?.parentPath = val
                case "Display Name": cur?.displayName = val
                case "Parent Name": cur?.parentName = val
                default: break
                }
            } else if let paren = t.firstIndex(of: "("), t.hasSuffix(")") {
                flush()
                var head = String(t[..<paren])
                var election = ""
                if let f = head.first, "+-!?".contains(f) { election = String(f); head = String(head.dropFirst()).trimmingCharacters(in: .whitespaces) }
                guard !head.isEmpty, !head.contains(" ") else { continue }
                cur = PluginKitRecord(bundleID: head, path: "", election: election)
            }
        }
        flush()
        return out
    }

    static func kind(forSDK sdk: String?) -> ExtensionItem.Kind {
        let s = (sdk ?? "").lowercased()
        if s.contains("safari") { return .safari }
        if s.contains("quicklook") { return .quickLook }
        if s.contains("findersync") { return .finderSync }
        if s.contains("share") { return .share }
        if s.contains("widget") { return .widget }
        return .other
    }

    /// Chỉ giữ extension của bên thứ ba (bỏ phần của Apple/hệ thống) và gộp trùng theo đường dẫn.
    static func appExtensions(from records: [PluginKitRecord]) -> [ExtensionItem] {
        var seen = Set<String>()
        return records.compactMap { r in
            guard !r.path.hasPrefix("/System/"), !r.bundleID.hasPrefix("com.apple."), seen.insert(r.path).inserted else { return nil }
            let url = URL(fileURLWithPath: r.path)
            let host = r.parentPath.map { URL(fileURLWithPath: $0) }
            return ExtensionItem(name: r.displayName ?? url.deletingPathExtension().lastPathComponent, kind: kind(forSDK: r.sdk),
                                 url: url, bundleID: r.bundleID, hostName: r.parentName ?? host?.deletingPathExtension().lastPathComponent,
                                 hostURL: host, size: 0, enabled: r.enabled, system: true)
        }
    }

    // MARK: Plugin file

    /// (thư mục, loại, đuôi file). `~` là thư mục người dùng; thư mục dưới `/Library` cần quyền admin nên chỉ liệt kê.
    static let pluginDirs: [(String, ExtensionItem.Kind, Set<String>)] = [
        ("~/Library/PreferencePanes", .preferencePane, ["prefpane"]), ("/Library/PreferencePanes", .preferencePane, ["prefpane"]),
        ("~/Library/Internet Plug-Ins", .internetPlugin, ["plugin", "webplugin"]), ("/Library/Internet Plug-Ins", .internetPlugin, ["plugin", "webplugin"]),
        ("~/Library/Spotlight", .spotlightPlugin, ["mdimporter"]), ("/Library/Spotlight", .spotlightPlugin, ["mdimporter"]),
        ("~/Library/Services", .service, ["workflow", "service"]), ("/Library/Services", .service, ["workflow", "service"]),
        ("~/Library/Audio/Plug-Ins/Components", .audioPlugin, ["component"]), ("/Library/Audio/Plug-Ins/Components", .audioPlugin, ["component"]),
        ("~/Library/Audio/Plug-Ins/VST", .audioPlugin, ["vst"]), ("/Library/Audio/Plug-Ins/VST", .audioPlugin, ["vst"]),
        ("~/Library/Audio/Plug-Ins/VST3", .audioPlugin, ["vst3"]), ("/Library/Audio/Plug-Ins/VST3", .audioPlugin, ["vst3"]),
    ]

    static func plugins(dirs: [(String, ExtensionItem.Kind, Set<String>)] = pluginDirs) -> [ExtensionItem] {
        let fm = FileManager.default
        var items: [ExtensionItem] = []
        for (dir, kind, exts) in dirs {
            let base = URL(fileURLWithPath: expandTilde(dir))
            for u in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            where exts.contains(u.pathExtension.lowercased()) {
                let b = Bundle(url: u)
                let bid = b?.bundleIdentifier
                if bid?.hasPrefix("com.apple.") == true { continue }
                let name = (b?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (b?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? u.deletingPathExtension().lastPathComponent
                items.append(ExtensionItem(name: name, kind: kind, url: u, bundleID: bid, hostName: nil, hostURL: nil,
                                           size: FileWalker.allocatedSize(of: u), enabled: true, system: !dir.hasPrefix("~")))
            }
        }
        return items
    }

    // MARK: Tổng hợp & thao tác

    public static func scan() async -> [ExtensionItem] {
        async let pk = ProcessRunner.run(["pluginkit", "-mAvvv"], timeout: 30)
        let files = await Concurrent.map([0]) { _ in plugins() }.flatMap { $0 }
        var apps = appExtensions(from: parsePluginKit(await pk.stdout))
        apps = await Concurrent.map(apps) { var a = $0; a.size = FileWalker.allocatedSize(of: a.url); return a }
        return (files + apps).sorted { ($0.kind.rawValue, $0.name.lowercased()) < ($1.kind.rawValue, $1.name.lowercased()) }
    }

    /// Bật/tắt extension trong app bằng bầu chọn của người dùng trong pluginkit (không sửa file nào).
    public static func setEnabled(_ enabled: Bool, bundleID: String) async -> Bool {
        await ProcessRunner.run(["pluginkit", "-e", enabled ? "use" : "ignore", "-i", bundleID], timeout: 30).ok
    }
}
