import Foundation
import Security
import CoreKit

public struct PersistenceItem: Identifiable, Sendable, Hashable {
    public var id: String { plist.path }
    public let label: String
    public let plist: URL
    public let program: String?
    public let trust: Trust
    public let scope: Scope
    /// Lý do ngắn gọn (đã dịch) giải thích vì sao mục này cần chú ý hoặc không kiểm tra được.
    public let note: String?

    public enum Scope: String, Sendable {
        case userAgent = "User Agent", systemAgent = "System Agent", daemon = "Daemon"
        public var title: String { tr(rawValue) }
    }
    public enum Trust: String, Sendable {
        case apple = "Apple", signed = "Đã ký", unsigned = "Chưa ký / ad-hoc", missing = "Thiếu file thực thi",
             unreadable = "Không kiểm tra được", empty = "Plist rỗng", unknown = "Không xác định"
        public var title: String { tr(rawValue) }
        /// 0 = cần chú ý · 1 = chưa rõ · 2 = đã ký · 3 = của Apple (dùng để sắp xếp).
        public var severity: Int {
            switch self {
            case .unsigned, .missing: return 0
            case .unreadable, .empty, .unknown: return 1
            case .signed: return 2
            case .apple: return 3
            }
        }
    }
    public var suspicious: Bool { trust.severity == 0 }
}

/// Persistence scanner: liệt kê launch agents/daemons và kiểm tra code signature từng mục.
/// Đây KHÔNG phải antivirus — chỉ phát hiện mục lạ ở các điểm persistence phổ biến.
public enum PersistenceScanner {
    public static let dirs: [(String, PersistenceItem.Scope)] = [
        ("~/Library/LaunchAgents", .userAgent), ("/Library/LaunchAgents", .systemAgent), ("/Library/LaunchDaemons", .daemon),
    ]

    public static func trust(of path: String) -> PersistenceItem.Trust {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return .missing }
        // Tồn tại nhưng không cho đọc (ví dụ quyền --x--x--x của một số helper) → không thể kiểm tra chữ ký.
        guard fm.isReadableFile(atPath: path) else { return .unreadable }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return .unknown }
        func valid(_ req: String) -> Bool {
            var r: SecRequirement?
            guard SecRequirementCreateWithString(req as CFString, [], &r) == errSecSuccess, let r else { return false }
            return SecStaticCodeCheckValidity(code, [], r) == errSecSuccess
        }
        if valid("anchor apple") { return .apple }
        if valid("anchor apple generic") { return .signed }
        // Có chữ ký hợp lệ nhưng không do Apple cấp (ví dụ Developer ID tự động qua chain khác).
        return SecStaticCheckValidityOK(code) && hasTeamID(code) ? .signed : .unsigned
    }

    private static func SecStaticCheckValidityOK(_ code: SecStaticCode) -> Bool {
        SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    private static func hasTeamID(_ code: SecStaticCode) -> Bool {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any] else { return false }
        return d[kSecCodeInfoTeamIdentifier as String] != nil
    }

    /// Các trình thông dịch/launcher: file thực sự được chạy là tham số đường dẫn đầu tiên phía sau.
    private static let launchers: Set<String> = ["/bin/sh", "/bin/bash", "/bin/zsh", "/usr/bin/env", "/usr/bin/python3",
                                                 "/usr/bin/osascript", "/usr/bin/perl", "/usr/bin/ruby", "/usr/bin/open"]

    static func resolveProgram(_ p: [String: Any]) -> String? {
        let args = p["ProgramArguments"] as? [String] ?? []
        let program = (p["Program"] as? String) ?? args.first
        guard let program else { return nil }
        if launchers.contains(program),
           let target = args.dropFirst().first(where: { $0.hasPrefix("/") && !$0.hasPrefix("-") }) { return target }
        return program
    }

    static func note(for trust: PersistenceItem.Trust, plistUnreadable: Bool = false) -> String? {
        if plistUnreadable { return tr("Không có quyền đọc file plist (cần Full Disk Access hoặc quyền admin).") }
        switch trust {
        case .missing: return tr("Không tìm thấy file thực thi — thường là mục mồ côi của app đã gỡ.")
        case .unsigned: return tr("Không có chữ ký hợp lệ hoặc chỉ ký ad-hoc.")
        case .unreadable: return tr("File thực thi không cho phép đọc nên không kiểm tra được chữ ký.")
        case .empty: return tr("Plist rỗng, không trỏ tới chương trình nào — thường là mảnh còn sót lại.")
        case .unknown: return tr("Không xác định được chương trình mà mục này chạy.")
        case .apple, .signed: return nil
        }
    }

    public static func scan() -> [PersistenceItem] {
        var out: [PersistenceItem] = []
        for (d, scope) in dirs {
            let dir = URL(fileURLWithPath: expandTilde(d))
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "plist" {
                let fallback = f.deletingPathExtension().lastPathComponent
                guard let data = try? Data(contentsOf: f),
                      let p = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
                    // Trước đây các plist không đọc được bị bỏ qua im lặng → nay vẫn hiện, gắn nhãn "Không kiểm tra được".
                    out.append(PersistenceItem(label: fallback, plist: f, program: nil, trust: .unreadable, scope: scope,
                                               note: note(for: .unreadable, plistUnreadable: true)))
                    continue
                }
                let program = resolveProgram(p)
                let t: PersistenceItem.Trust = program.map(trust(of:)) ?? (p.isEmpty ? .empty : .unknown)
                out.append(PersistenceItem(label: (p["Label"] as? String) ?? fallback, plist: f, program: program,
                                           trust: t, scope: scope, note: note(for: t)))
            }
        }
        return out.sorted { ($0.trust.severity, $0.label.lowercased()) < ($1.trust.severity, $1.label.lowercased()) }
    }
}

// MARK: - Real-time monitor (FSEvents)

public struct FileAlert: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let reason: String
    public let trust: PersistenceItem.Trust?
    public let date = Date()
}

/// Theo dõi file mới ở các vị trí nhạy cảm bằng FSEvents. CHỈ phát hiện sau khi file đã được ghi,
/// không chặn được việc thực thi (cần Endpoint Security — để dành cho v2).
public final class RealtimeMonitor: @unchecked Sendable {
    public static let defaultPaths = ["~/Downloads", "~/Desktop", "/Applications", "~/Applications",
                                      "~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons",
                                      "/Library/PrivilegedHelperTools"]
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "vutidy.realtime", qos: .utility)
    private let paths: [String]
    private let onAlert: @Sendable (FileAlert) -> Void
    private let onScan: @Sendable (String) -> Void
    private var pending: [String: DispatchWorkItem] = [:]
    public private(set) var isRunning = false
    public var maxFileBytes: Int64 = 500_000_000

    public init(paths: [String] = defaultPaths, onScan: @escaping @Sendable (String) -> Void = { _ in },
                onAlert: @escaping @Sendable (FileAlert) -> Void) {
        self.paths = paths.map(expandTilde).filter { FileManager.default.fileExists(atPath: $0) }
        self.onAlert = onAlert
        self.onScan = onScan
    }

    public func start() {
        guard !isRunning, !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            let me = Unmanaged<RealtimeMonitor>.fromOpaque(info!).takeUnretainedValue()
            let arr = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            for i in 0..<count {
                let f = flags[i]
                if f & UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified) != 0,
                   f & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 || f & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 {
                    me.schedule(arr[i])
                }
            }
        }
        stream = FSEventStreamCreate(nil, cb, &ctx, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        isRunning = true
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil; isRunning = false
    }

    // Debounce: đợi file ngừng được ghi.
    private func schedule(_ path: String) {
        pending[path]?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.evaluate(path) }
        pending[path] = w
        queue.asyncAfter(deadline: .now() + 2.0, execute: w)
    }

    func evaluate(_ path: String) {
        pending[path] = nil
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name.hasSuffix(".crdownload") || name.hasSuffix(".download") { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return }
        if let size = attrs[.size] as? Int64, size > maxFileBytes { return }
        onScan(path)

        let ext = url.pathExtension.lowercased()
        let quarantined = getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
        let reasonSuffix = quarantined ? tr(" (tải từ Internet)") : ""

        // File mới trong LaunchAgents/Daemons luôn được cảnh báo, kể cả khi sạch.
        if path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") {
            if ext == "plist" { onAlert(FileAlert(path: path, reason: tr("Persistence mới: launch item vừa được thêm"), trust: nil)) }
            return
        }
        guard ["app", "dmg", "pkg", "mpkg", "sh", "command", "dylib"].contains(ext) || isMachO(path) else { return }
        let trust = PersistenceScanner.trust(of: path)
        if trust == .unsigned || ["dmg", "pkg", "sh", "command"].contains(ext) {
            onAlert(FileAlert(path: path, reason: trf("File thực thi/cài đặt mới%@ — %@", "\(reasonSuffix)", "\(trust.title)"), trust: trust))
        }
    }

    private func isMachO(_ path: String) -> Bool {
        guard let h = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        let magic = d.withUnsafeBytes { $0.load(as: UInt32.self) }
        return [0xFEEDFACF, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }
}
