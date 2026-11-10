import Foundation

public enum ByteFormat {
    public static func string(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.zeroPadsFractionDigits = false
        if bytes <= 0 { return "0 KB" }
        return f.string(fromByteCount: bytes)
    }
}

/// Các vị trí lưu dữ liệu của app. Có thể trỏ sang thư mục tạm khi test.
public struct AppPaths: Sendable {
    public let base: URL
    public init(base: URL) { self.base = base }

    public static var `default`: AppPaths {
        if let override = ProcessInfo.processInfo.environment["VUTIDY_HOME"] {
            return AppPaths(base: URL(fileURLWithPath: override))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(base: support.appendingPathComponent("Vutidy"))
    }

    public var quarantine: URL { base.appendingPathComponent("Quarantine", isDirectory: true) }
    public var auditLog: URL { base.appendingPathComponent("audit.log") }
    public var userRules: URL { base.appendingPathComponent("Rules", isDirectory: true) }
    public var speedHistory: URL { base.appendingPathComponent("speedtest.json") }
}

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
}

public enum ProcessRunner {
    /// PATH mở rộng để tìm brew/go/docker khi chạy từ app GUI (PATH của GUI rất hẹp).
    public static var searchPath: String {
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/go/bin",
                     "\(NSHomeDirectory())/go/bin", "\(NSHomeDirectory())/.cargo/bin",
                     "/Applications/Docker.app/Contents/Resources/bin"]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return (extra + [current]).joined(separator: ":")
    }

    /// Tìm đường dẫn tuyệt đối của một lệnh, nil nếu không cài.
    public static func which(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchPath.split(separator: ":") {
            let p = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    public static func run(_ argv: [String], timeout: TimeInterval = 600) async -> ProcessResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runSync(argv, timeout: timeout))
            }
        }
    }

    public static func runSync(_ argv: [String], timeout: TimeInterval = 600) -> ProcessResult {
        guard let first = argv.first, let exe = which(first) else {
            return ProcessResult(status: 127, stdout: "", stderr: "command not found: \(argv.first ?? "")")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = Array(argv.dropFirst())
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return ProcessResult(status: 126, stdout: "", stderr: "\(error)")
        }
        // Đọc song song để tránh đầy pipe làm treo tiến trình con.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning {
            if Date() > deadline { p.terminate(); break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        p.waitUntilExit()
        group.wait()
        return ProcessResult(status: p.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
    }

    /// Chạy lệnh shell với quyền admin qua hộp thoại hệ thống (thay cho privileged helper ở bản dev).
    public static func runPrivileged(shell command: String) async -> ProcessResult {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return await run(["osascript", "-e", script])
    }
}

/// Quy ước đường dẫn: mở rộng `~`.
public func expandTilde(_ path: String) -> String {
    if path == "~" { return NSHomeDirectory() }
    if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst(1)) }
    return path
}
