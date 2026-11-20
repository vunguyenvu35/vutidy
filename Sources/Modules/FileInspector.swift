import Foundation
import CryptoKit
import CoreKit
import ScanEngine

/// Kết quả kiểm tra một file do người dùng chọn: chữ ký code, nguồn tải về, Gatekeeper, SHA-256 và (nếu có) ClamAV.
/// Mọi thứ chạy ngay trên máy; không gửi file hay mã băm đi đâu.
public struct FileReport: Identifiable, Sendable, Equatable {
    public enum Signature: Sendable, Equatable { case apple, appStore, notarized, signedNotNotarized, unsigned, tampered, unreadable, notApplicable }
    public enum Level: Sendable, Equatable { case ok, review, danger }
    public enum Clam: Sendable, Equatable { case clean, found(String), notInstalled, noDatabase, skipped }

    public var id: String { path }
    public let path: String
    public let name: String
    public let size: Int64
    public let kind: String
    public let signature: Signature
    /// macOS đã gắn dấu "tải từ Internet" (com.apple.quarantine): lần đầu mở sẽ có hộp thoại Gatekeeper.
    public let fromInternet: Bool
    public let sources: [String]
    /// nil = không áp dụng/không đánh giá được. Ví dụ "accepted · Notarized Developer ID".
    public let gatekeeper: String?
    public let gatekeeperRejected: Bool
    /// nil = bỏ qua (thư mục/app hoặc file quá lớn).
    public let sha256: String?
    public let clam: Clam
    public let level: Level
    public let reasons: [String]
}

public enum FileInspector {
    /// File lớn hơn mức này không băm SHA-256 để khỏi treo máy.
    static let hashLimit: Int64 = 1_000_000_000

    /// Quy tắc đánh giá (thuần, dễ test). Chỉ báo "xem lại" khi file thực thi/script/trình cài có dấu hiệu rủi ro đi kèm nguồn Internet.
    public static func assess(signature: FileReport.Signature, fromInternet: Bool, isScript: Bool, isInstaller: Bool,
                              gatekeeperRejected: Bool, clam: FileReport.Clam) -> (FileReport.Level, [String]) {
        var level = FileReport.Level.ok
        var reasons: [String] = []
        if signature == .tampered {
            level = .danger; reasons.append(tr("Chữ ký không còn khớp nội dung file: file đã bị sửa sau khi ký."))
        }
        if case .found(let sig) = clam {
            level = .danger; reasons.append(trf("ClamAV khớp chữ ký “%@”. Có thể là báo nhầm: kiểm tra trước khi xóa.", sig))
        }
        if fromInternet {
            if signature == .unsigned { reasons.append(tr("File thực thi chưa ký, tải từ Internet.")) }
            else if signature == .signedNotNotarized { reasons.append(tr("Có chữ ký nhưng Apple chưa công chứng (notarize), tải từ Internet.")) }
            else if isScript { reasons.append(tr("Script tải từ Internet: đọc nội dung trước khi chạy.")) }
            if gatekeeperRejected && (isInstaller || signature != .unsigned) { reasons.append(tr("Gatekeeper từ chối file này.")) }
        }
        if level == .ok && !reasons.isEmpty { level = .review }
        return (level, reasons)
    }

    public static func inspect(_ url: URL, useClamAV: Bool) async -> FileReport {
        let path = url.path
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let dir = isDir.boolValue
        let ext = url.pathExtension.lowercased()
        let isApp = ext == "app" && dir

        var kind = String((await ProcessRunner.run(["file", "-b", path], timeout: 10)).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        if isApp { kind = tr("Ứng dụng macOS (app bundle)") } else if dir { kind = tr("Thư mục") }
        let k = kind.lowercased()
        let machO = k.contains("mach-o")
        let isScript = k.contains("script") || k.contains("executable") && !machO
        let isInstaller = ["pkg", "mpkg", "dmg"].contains(ext)
        let hasCode = isApp || machO

        // Các bước nặng (băm cả bundle, spctl, ClamAV, đo dung lượng) chạy song song: app lớn như Chrome mất vài chục giây nếu làm lần lượt.
        async let sizeTask: Int64 = Task.detached(priority: .utility) {
            dir ? FileWalker.allocatedSize(of: url) : Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }.value
        async let signatureTask: FileReport.Signature = Task.detached(priority: .utility) {
            guard hasCode else { return .notApplicable }
            switch MalwareCheck.verdict(for: url) {
            case .apple: return .apple
            case .appStore: return .appStore
            case .notarized: return .notarized
            case .signedNotNotarized: return .signedNotNotarized
            case .adHocOrUnsigned: return .unsigned
            case .tampered: return .tampered
            case .unreadable: return .unreadable
            }
        }.value
        async let gatekeeperTask: (String?, Bool) = gatekeeper(path: path, ext: ext, hasCode: hasCode)
        async let clamTask: FileReport.Clam = (useClamAV && (!dir || isApp)) ? ClamAV.scan(file: path) : .skipped

        let size = await sizeTask
        let sha: String? = (dir || size > hashLimit) ? nil : await Task.detached(priority: .utility) { sha256(of: url) }.value
        let signature = await signatureTask
        let (gk, rejected) = await gatekeeperTask
        let clam = await clamTask

        let fromInternet = xattrSize("com.apple.quarantine", at: path) != nil
        let sources = (xattr("com.apple.metadata:kMDItemWhereFroms", at: path)
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String] }) ?? []

        let (level, reasons) = assess(signature: signature, fromInternet: fromInternet, isScript: isScript, isInstaller: isInstaller,
                                      gatekeeperRejected: rejected, clam: clam)
        return FileReport(path: path, name: url.lastPathComponent, size: size, kind: kind, signature: signature, fromInternet: fromInternet,
                          sources: sources, gatekeeper: gk, gatekeeperRejected: rejected, sha256: sha, clam: clam,
                          level: level, reasons: reasons)
    }

    /// Gatekeeper (spctl): app/Mach-O = execute, pkg = install, dmg = open. nil = không áp dụng.
    static func gatekeeper(path: String, ext: String, hasCode: Bool) async -> (String?, Bool) {
        var args: [String]?
        if hasCode { args = ["spctl", "--assess", "--type", "execute", "-vv", path] }
        else if ext == "pkg" || ext == "mpkg" { args = ["spctl", "--assess", "--type", "install", "-vv", path] }
        else if ext == "dmg" { args = ["spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "-vv", path] }
        guard let args else { return (nil, false) }
        let r = await ProcessRunner.run(args, timeout: 30)
        let text = r.stdout + "\n" + r.stderr
        let rejected = text.contains(": rejected")
        let verdict = rejected ? tr("Bị từ chối") : tr("Được chấp nhận")
        if let src = text.split(separator: "\n").first(where: { $0.hasPrefix("source=") }) {
            return (verdict + " · " + String(src.dropFirst("source=".count)), rejected)
        }
        return (rejected || text.contains(": accepted") ? verdict : nil, rejected)
    }

    // MARK: Thuộc tính mở rộng và băm

    static func xattrSize(_ name: String, at path: String) -> Int? {
        let n = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        return n >= 0 ? n : nil
    }

    static func xattr(_ name: String, at path: String) -> Data? {
        guard let n = xattrSize(name, at: path), n > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: n)
        let r = getxattr(path, name, &buf, n, 0, XATTR_NOFOLLOW)
        return r > 0 ? Data(buf.prefix(r)) : nil
    }

    static func sha256(of url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
