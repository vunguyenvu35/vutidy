import Foundation
import CoreKit

public struct OutdatedApp: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let installed: String
    public let latest: String
    public let source: String
}

public enum Updater {
    /// Kiểm tra cask Homebrew (best effort). Chỉ thông báo, không tự cài.
    public static func brewOutdated() async -> [OutdatedApp] {
        guard ProcessRunner.which("brew") != nil else { return [] }
        let r = await ProcessRunner.run(["brew", "outdated", "--cask", "--greedy", "--json=v2"], timeout: 120)
        guard r.ok, let j = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any],
              let casks = j["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { c in
            guard let name = c["name"] as? String else { return nil }
            let installed = (c["installed_versions"] as? [String])?.first ?? (c["installed_versions"] as? String) ?? "?"
            return OutdatedApp(name: name, installed: installed, latest: (c["current_version"] as? String) ?? "?", source: "Homebrew")
        }
    }

    /// Ứng dụng App Store: tra iTunes Lookup theo bundle ID.
    public static func appStoreLatest(bundleID: String) async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (j["results"] as? [[String: Any]])?.first else { return nil }
        return first["version"] as? String
    }
}

public enum CloudCleanup {
    public static var iCloudDrive: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs")
    }

    /// Liệt kê file iCloud đã tải về máy (đủ lớn) — có thể evict bản local mà không xóa trên cloud.
    public static func downloadedFiles(root: URL = iCloudDrive, minBytes: Int64 = 10_000_000) -> [ScanItem] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .totalFileAllocatedSizeKey, .isRegularFileKey],
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [ScanItem] = []
        for case let u as URL in en {
            guard let v = try? u.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .totalFileAllocatedSizeKey, .isRegularFileKey]),
                  v.isRegularFile == true, v.isUbiquitousItem == true,
                  v.ubiquitousItemDownloadingStatus == .current,
                  let size = v.totalFileAllocatedSize, Int64(size) >= minBytes else { continue }
            out.append(ScanItem(url: u, title: u.lastPathComponent, allocatedSize: Int64(size), category: "iCloud Drive",
                                ruleID: "icloud-evict", safety: .safe, detail: tr("Chỉ gỡ bản local, bản trên iCloud vẫn còn")))
        }
        return out.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    public static func evict(_ items: [ScanItem]) -> [CleanOutcome] {
        items.map { i in
            do { try FileManager.default.evictUbiquitousItem(at: i.url)
                 return CleanOutcome(itemID: i.id, path: i.url.path, bytes: i.allocatedSize, status: .done, note: "evicted") }
            catch { return CleanOutcome(itemID: i.id, path: i.url.path, bytes: i.allocatedSize, status: .failed(error.localizedDescription)) }
        }
    }
}

public extension Updater {
    /// Nâng cấp một cask Homebrew. Có thể mất vài phút; một số bản cần mật khẩu quản trị nên có thể thất bại khi chạy không tương tác.
    static func upgrade(_ app: OutdatedApp) async -> ProcessResult {
        await ProcessRunner.run(["brew", "upgrade", "--cask", app.name], timeout: 1800)
    }
}
