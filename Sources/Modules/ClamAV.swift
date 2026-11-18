import Foundation
import CoreKit

/// ClamAV tùy chọn: quét file bằng cơ sở dữ liệu chữ ký công khai, chạy hoàn toàn trên máy.
/// Chỉ dùng khi người dùng đã cài `clamscan`/`freshclam` (ví dụ `brew install clamav`) và tự bấm. Tải cơ sở dữ liệu là lần duy nhất cần mạng
/// (chỉ tải về, không gửi file nào đi). Cơ sở dữ liệu nằm trong thư mục riêng của Vutidy nên không đụng cấu hình ClamAV của hệ thống.
public enum ClamAV {
    public struct Status: Sendable, Equatable {
        public var installed: Bool
        public var version: String?
        public var hasDatabase: Bool
        /// Tuổi của cơ sở dữ liệu (ngày), theo thời điểm tải gần nhất.
        public var databaseAgeDays: Int?
        public static let missing = Status(installed: false, version: nil, hasDatabase: false, databaseAgeDays: nil)
    }

    public static var dataDir: URL { AppPaths.default.base.appendingPathComponent("clamav", isDirectory: true) }
    static var configFile: URL { dataDir.appendingPathComponent("freshclam.conf") }
    public static let installCommand = "brew install clamav"
    public static var hasHomebrew: Bool { ProcessRunner.which("brew") != nil }
    /// Nơi quét: các chỗ malware hay xuất hiện (tải về, cài đặt, persistence). Không quét Documents (riêng tư, cần cấp quyền thêm).
    public static let scanTargets = ["~/Downloads", "~/Desktop", "/Applications", "~/Applications",
                                     "~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"]
    /// Cơ sở dữ liệu cũ hơn mức này thì nên cập nhật trước khi quét.
    public static let staleAfterDays = 7
    /// Trước khi quét, tự cập nhật cơ sở dữ liệu nếu đã cũ từ ngần này ngày (chữ ký mới ra hằng ngày).
    public static let refreshBeforeScanDays = 1

    // MARK: Phân tích (thuần hàm)

    /// `clamscan --version`: "ClamAV 1.5.4/27812/Tue Nov 18 07:25:28 2026" (hoặc chỉ "ClamAV 1.5.4" khi chưa có cơ sở dữ liệu).
    static func parseVersion(_ out: String) -> String? {
        guard let line = out.split(separator: "\n").first(where: { $0.hasPrefix("ClamAV ") }) else { return nil }
        return line.dropFirst("ClamAV ".count).split(separator: "/").first.map(String.init)
    }

    /// Dòng kết quả của `clamscan --infected`: `<đường dẫn>: <tên chữ ký> FOUND`.
    static func parseFound(_ out: String) -> [(path: String, signature: String)] {
        out.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard line.hasSuffix(" FOUND") else { return nil }
            let body = line.dropLast(" FOUND".count)
            guard let sep = body.range(of: ": ", options: .backwards) else { return nil }
            let path = String(body[..<sep.lowerBound]), sig = String(body[sep.upperBound...])
            return path.hasPrefix("/") && !sig.isEmpty ? (path, sig) : nil
        }
    }

    /// Lệnh quét: chỉ các thư mục tồn tại, bỏ qua file rất lớn để không treo máy.
    static func scanArguments(database: URL, targets: [String], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String] {
        ["clamscan", "-r", "--infected", "--no-summary", "--database=\(database.path)", "--max-filesize=100M", "--max-scansize=300M", "--cross-fs=no"]
            + targets.map(expandTilde).filter(exists)
    }

    static func findings(_ found: [(path: String, signature: String)]) -> [SecurityFinding] {
        found.map { f in
            .init(severity: .high, title: trf("ClamAV: %@", f.signature),
                  detail: trf("ClamAV khớp chữ ký “%@” trong file này. Có thể là báo nhầm: kiểm tra trước khi xóa.", f.signature),
                  path: f.path, source: .file, code: "clamav", subject: f.signature)
        }
    }

    // MARK: Trạng thái, cập nhật, quét

    static func databaseFiles() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { ["cvd", "cld"].contains($0.pathExtension) }
    }

    /// Có nên cập nhật cơ sở dữ liệu trước khi quét không: chưa có, hoặc đã từ `refreshBeforeScanDays` ngày trở lên.
    public static func needsRefresh(_ s: Status) -> Bool {
        s.installed && (!s.hasDatabase || (s.databaseAgeDays ?? 0) >= refreshBeforeScanDays)
    }

    public static func status(now: Date = Date()) async -> Status {
        guard ProcessRunner.which("clamscan") != nil else { return .missing }
        let v = await ProcessRunner.run(["clamscan", "--version"], timeout: 20)
        let files = databaseFiles()
        let newest = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
        return Status(installed: true, version: parseVersion(v.stdout), hasDatabase: !files.isEmpty,
                      databaseAgeDays: newest.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) })
    }

    public enum Failure: Error, Equatable { case notInstalled, noDatabase, noHomebrew, failed(String) }

    /// Cài ClamAV bằng Homebrew (`brew install clamav`). Cần mạng; không cần quyền admin vì Homebrew cài vào thư mục của người dùng.
    public static func install() async -> Result<Void, Failure> {
        guard hasHomebrew else { return .failure(.noHomebrew) }
        let r = await ProcessRunner.run(["brew", "install", "clamav"], timeout: 1_800)
        return r.ok ? .success(()) : .failure(.failed(String((r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))))
    }

    /// Tải/cập nhật cơ sở dữ liệu bằng freshclam vào thư mục riêng (lần đầu khoảng vài trăm MB).
    public static func updateDatabase() async -> Result<Void, Failure> {
        guard ProcessRunner.which("freshclam") != nil else { return .failure(.notInstalled) }
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let conf = "DatabaseDirectory \(dataDir.path)\nDatabaseMirror database.clamav.net\n"
        guard (try? conf.write(to: configFile, atomically: true, encoding: .utf8)) != nil else { return .failure(.failed("config")) }
        let r = await ProcessRunner.run(["freshclam", "--config-file=\(configFile.path)", "--datadir=\(dataDir.path)"], timeout: 1_800)
        return r.ok ? .success(()) : .failure(.failed(String((r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))))
    }

    /// Quét các thư mục trong `scanTargets`. Mã thoát của clamscan: 0 sạch, 1 có phát hiện, còn lại là lỗi.
    public static func scan() async -> Result<[SecurityFinding], Failure> {
        guard ProcessRunner.which("clamscan") != nil else { return .failure(.notInstalled) }
        guard !databaseFiles().isEmpty else { return .failure(.noDatabase) }
        let args = scanArguments(database: dataDir, targets: scanTargets)
        let r = await ProcessRunner.run(args, timeout: 3_600)
        switch r.status {
        case 0, 1: return .success(findings(parseFound(r.stdout)))
        default: return .failure(.failed(String((r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines).suffix(300))))
        }
    }
}
