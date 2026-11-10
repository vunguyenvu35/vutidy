import Foundation
import CryptoKit
import CoreKit

/// Số phiên bản dạng `1.2.3` (tag `v1.2.3` cũng được). Bản có hậu tố (`-beta`) nhỏ hơn bản chính thức cùng số.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]
    public let suffix: String

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let split = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let nums = (split.first ?? "").split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !nums.isEmpty, !nums.contains(where: { $0 == nil }) else { return nil }
        parts = nums.compactMap { $0 }
        suffix = split.count > 1 ? String(split[1]) : ""
    }

    public var description: String { parts.map(String.init).joined(separator: ".") + (suffix.isEmpty ? "" : "-" + suffix) }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        if a.suffix == b.suffix { return false }
        if a.suffix.isEmpty { return false }      // bản chính thức > bản có hậu tố
        if b.suffix.isEmpty { return true }
        return a.suffix < b.suffix
    }
}

/// Một bản phát hành trên GitHub.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let tag: String
    public let notes: String
    public let pageURL: URL
    public let zipURL: URL
    public let zipName: String
    public let sumsURL: URL?
    public let prerelease: Bool
}

public enum AppUpdateError: Error, Equatable, LocalizedError {
    case network(String)
    case badResponse
    case noPackage
    case noChecksum
    case checksumMismatch
    case badPackage(String)
    case notInstalledAsApp
    case needsApplicationsFolder
    case notWritable(String)

    public var errorDescription: String? {
        switch self {
        case .network(let m): return trf("Không kết nối được tới GitHub: %@", m)
        case .badResponse: return tr("GitHub trả về dữ liệu không hiểu được.")
        case .noPackage: return tr("Bản phát hành này chưa có file cài đặt (.zip) cho macOS.")
        case .noChecksum: return tr("Bản phát hành thiếu SHA256SUMS nên không thể xác minh file tải về. Vutidy sẽ không cài.")
        case .checksumMismatch: return tr("Mã SHA-256 của file tải về không khớp. File đã bị hủy, không cài gì cả.")
        case .badPackage(let m): return trf("File cập nhật không hợp lệ: %@", m)
        case .notInstalledAsApp: return tr("Chỉ cập nhật được khi chạy Vutidy.app. Bản swift run hãy tự build lại.")
        case .needsApplicationsFolder: return tr("Hãy kéo Vutidy vào thư mục Applications rồi mở lại từ đó trước khi cập nhật.")
        case .notWritable(let p): return trf("Không có quyền ghi vào “%@”. Hãy cập nhật thủ công bằng file .dmg.", p)
        }
    }
}

/// Kiểm tra bản mới qua GitHub Releases. Chỉ gửi một yêu cầu GET công khai; không gửi gì về máy bạn.
public enum UpdateChecker {
    public static let repository = "vunguyenvu35/vutidy"

    public static var currentVersion: AppVersion {
        let s = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        return AppVersion(s) ?? AppVersion("0.0.0")!
    }

    /// Phân tích JSON của `GET /repos/{repo}/releases`; bỏ bản nháp, chọn bản có số lớn nhất.
    /// Không dùng `/releases/latest` vì nó bỏ qua pre-release, mà mọi bản dưới 1.0.0 là pre-release.
    public static func parse(_ data: Data) throws -> ReleaseInfo? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw AppUpdateError.badResponse }
        var best: ReleaseInfo?
        for r in arr {
            if r["draft"] as? Bool == true { continue }
            guard let tag = r["tag_name"] as? String, let v = AppVersion(tag),
                  let page = (r["html_url"] as? String).flatMap(URL.init(string:)) else { continue }
            let assets = (r["assets"] as? [[String: Any]] ?? []).compactMap { a -> (String, URL)? in
                guard let n = a["name"] as? String, let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
                return (n, u)
            }
            // Ưu tiên file có số phiên bản trong tên; bỏ qua bản sao "vutidy-macos.zip" nếu đã có.
            guard let zip = assets.first(where: { $0.0 == "vutidy-\(v)-macos.zip" }) ?? assets.first(where: { $0.0.hasSuffix("-macos.zip") && $0.0 != "vutidy-macos.zip" }) else {
                continue
            }
            let sums = assets.first { $0.0 == "SHA256SUMS" }?.1
            let info = ReleaseInfo(version: v, tag: tag, notes: r["body"] as? String ?? "", pageURL: page, zipURL: zip.1, zipName: zip.0,
                                   sumsURL: sums, prerelease: r["prerelease"] as? Bool ?? false)
            if best == nil || v > best!.version { best = info }
        }
        return best
    }

    /// Bản mới hơn bản đang chạy, hoặc nil.
    public static func newer(than current: AppVersion, in data: Data) throws -> ReleaseInfo? {
        guard let r = try parse(data), r.version > current else { return nil }
        return r
    }

    public static func fetchLatest(session: URLSession = .shared) async throws -> ReleaseInfo? {
        // VUTIDY_UPDATE_FEED: a local JSON file (file://...) to try the update flow without a real release.
        let feed = ProcessInfo.processInfo.environment["VUTIDY_UPDATE_FEED"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=10")!
        var req = URLRequest(url: feed)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Vutidy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw AppUpdateError.badResponse }
            return try newer(than: currentVersion, in: data)
        } catch let e as AppUpdateError { throw e }
        catch { throw AppUpdateError.network(error.localizedDescription) }
    }
}

public enum UpdateVerifier {
    /// Đọc `SHA256SUMS` dạng `<hash>  <tên file>` (cũng nhận `*tên` của chế độ nhị phân).
    public static func parseSums(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard f.count == 2, f[0].count == 64 else { continue }
            out[String(f[1]).trimmingCharacters(in: CharacterSet(charactersIn: " *"))] = String(f[0]).lowercased()
        }
        return out
    }

    public static func sha256(of url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Tải, xác minh, giải nén và thay thế app đang chạy.
public enum AppInstaller {
    /// Tải file về thư mục tạm, báo tiến độ 0…1. Trả về đường dẫn file.
    public static func download(_ url: URL, to dir: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        let loader = Downloader(dest: dest, progress: progress)
        return try await loader.start(url)
    }

    private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let dest: URL, progress: @Sendable (Double) -> Void
        var cont: CheckedContinuation<URL, Error>?
        var session: URLSession?
        init(dest: URL, progress: @escaping @Sendable (Double) -> Void) { self.dest = dest; self.progress = progress }

        func start(_ url: URL) async throws -> URL {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
                cont = c
                let s = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
                session = s
                s.downloadTask(with: url).resume()
            }
        }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite t: Int64) {
            if t > 0 { progress(min(1, Double(w) / Double(t))) }
        }
        func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo tmp: URL) {
            if let h = downloadTask.response as? HTTPURLResponse, h.statusCode != 200 { finish(.failure(AppUpdateError.badResponse)); return }
            do { try? FileManager.default.removeItem(at: dest); try FileManager.default.moveItem(at: tmp, to: dest); finish(.success(dest)) }
            catch { finish(.failure(AppUpdateError.network(error.localizedDescription))) }
        }
        func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError e: Error?) {
            if let e { finish(.failure(AppUpdateError.network(e.localizedDescription))) }
        }
        private func finish(_ r: Result<URL, Error>) {
            guard let c = cont else { return }
            cont = nil; session?.finishTasksAndInvalidate()
            c.resume(with: r)
        }
    }

    /// Kiểm tra hash của zip theo SHA256SUMS. Bắt buộc phải có; thiếu thì từ chối.
    public static func verify(zip: URL, name: String, sums: String?) throws {
        guard let sums, let expected = UpdateVerifier.parseSums(sums)[name] else { throw AppUpdateError.noChecksum }
        guard try UpdateVerifier.sha256(of: zip) == expected else { throw AppUpdateError.checksumMismatch }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func teamID(of app: URL) -> String? {
        let r = run("/usr/bin/codesign", ["-dv", "--verbose=2", app.path])
        guard let line = r.out.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else { return nil }
        let id = line.dropFirst("TeamIdentifier=".count)
        return id == "not set" ? nil : String(id)
    }

    /// Giải nén zip và kiểm tra: đúng bundle ID, đúng phiên bản, chữ ký hợp lệ, và (nếu bản đang chạy có Team ID)
    /// cùng Team ID — để một file lạ không thể thay Vutidy thật.
    public static func extract(zip: URL, into dir: URL, expecting version: AppVersion, current: URL) throws -> URL {
        let out = dir.appendingPathComponent("extracted"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path]).status == 0 else { throw AppUpdateError.badPackage(tr("không giải nén được")) }
        guard let app = try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else {
            throw AppUpdateError.badPackage(tr("không thấy Vutidy.app"))
        }
        let mine = Bundle(url: current)?.bundleIdentifier
        guard info["CFBundleIdentifier"] as? String == mine else { throw AppUpdateError.badPackage(tr("sai bundle ID")) }
        guard let v = (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), v == version else {
            throw AppUpdateError.badPackage(tr("sai số phiên bản"))
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0 else { throw AppUpdateError.badPackage(tr("chữ ký không hợp lệ")) }
        if let team = teamID(of: current), teamID(of: app) != team { throw AppUpdateError.badPackage(tr("khác nhà phát triển (Team ID)")) }
        return app
    }

    /// Kiểm tra app đang chạy có thay thế được không (là .app, không ở trong DMG/translocation, thư mục cha ghi được).
    public static func checkInstallable(_ app: URL = Bundle.main.bundleURL) throws {
        guard app.pathExtension == "app" else { throw AppUpdateError.notInstalledAsApp }
        if app.path.hasPrefix("/Volumes/") || app.path.contains("/AppTranslocation/") { throw AppUpdateError.needsApplicationsFolder }
        let parent = app.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else { throw AppUpdateError.notWritable(parent) }
    }

    /// Chép bản mới cạnh app hiện tại (cùng ổ đĩa) rồi chạy script nền: đợi Vutidy thoát, hoán đổi, mở lại.
    /// Nếu hoán đổi lỗi, script khôi phục bản cũ và mở lại nó. Gọi xong thì app phải thoát.
    public static func stageAndSwap(newApp: URL, current: URL = Bundle.main.bundleURL) throws {
        try checkInstallable(current)
        let staged = current.deletingLastPathComponent().appendingPathComponent(".Vutidy-update.app")
        try? FileManager.default.removeItem(at: staged)
        guard run("/usr/bin/ditto", [newApp.path, staged.path]).status == 0 else { throw AppUpdateError.badPackage(tr("không chép được bản mới")) }
        let script = """
        #!/bin/sh
        exec >> "${TMPDIR:-/tmp}/vutidy-update.log" 2>&1
        pid="$1"; new="$2"; dst="$3"; bak="$3.old"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$bak"
        if mv "$dst" "$bak" && mv "$new" "$dst"; then
          xattr -dr com.apple.quarantine "$dst" 2>/dev/null
          rm -rf "$bak"
        else
          [ -d "$bak" ] && [ ! -d "$dst" ] && mv "$bak" "$dst"
          rm -rf "$new"
        fi
        /usr/bin/open -n "$dst" || { sleep 1; /usr/bin/open -n "$dst"; }
        rm -f "$0"
        """
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("vutidy-swap-\(UUID().uuidString).sh")
        try script.write(to: path, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [path.path, "\(ProcessInfo.processInfo.processIdentifier)", staged.path, current.path]
        try p.run()
    }
}
