import Foundation
import CoreKit

/// Dùng chính công cụ AI trên máy user (đã đăng nhập sẵn) làm nguồn tư vấn: không cần API key.
/// Mỗi lần gọi chạy ở thư mục tạm rỗng, tắt tool/ghi file nếu CLI cho phép, và chỉ nhận số liệu tổng hợp (xem `AdvisorInput`).
public enum AdvisorProvider: String, CaseIterable, Sendable, Identifiable {
    case auto, claudeCode, codex, antigravity, gemini, api
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return tr("Tự động")
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        case .gemini: return "Gemini CLI"
        case .api: return "Claude API"
        }
    }
    /// Tên lệnh của CLI (nil với `.auto`/`.api`).
    public var executable: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .antigravity: return "agy"
        case .gemini: return "gemini"
        case .auto, .api: return nil
        }
    }
    public static let cliOrder: [AdvisorProvider] = [.claudeCode, .codex, .antigravity, .gemini]
    public var isInstalled: Bool { executable.map { ProcessRunner.which($0) != nil } ?? true }
    /// CLI đã cài trên máy, theo thứ tự ưu tiên.
    public static var installedCLIs: [AdvisorProvider] { cliOrder.filter(\.isInstalled) }
}

public struct AdvisorAnswer: Sendable, Equatable {
    public let text: String
    public let provider: AdvisorProvider
}

enum AdvisorCLI {
    struct Invocation: Equatable {
        var argv: [String]
        var stdin: String?
        /// Codex ghi câu trả lời cuối ra file này (stdout của nó lẫn log).
        var outputFile: URL?
    }

    /// Lệnh chạy một lần không tương tác. Thuần hàm để kiểm thử.
    static func invocation(_ p: AdvisorProvider, prompt: String, model: String = "", scratch: URL) -> Invocation? {
        let m = model.trimmingCharacters(in: .whitespaces)
        switch p {
        case .claudeCode:
            return Invocation(argv: ["claude", "-p", "--output-format", "text", "--tools", "", "--no-session-persistence"]
                              + (m.isEmpty ? [] : ["--model", m]), stdin: prompt)
        case .codex:
            let out = scratch.appendingPathComponent("codex-answer.txt")
            return Invocation(argv: ["codex", "exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "--color", "never"]
                              + (m.isEmpty ? [] : ["-m", m]) + ["-o", out.path, "-"], stdin: prompt, outputFile: out)
        case .antigravity:
            return Invocation(argv: ["agy", "-p", prompt, "--mode", "plan"] + (m.isEmpty ? [] : ["--model", m]), stdin: nil)
        case .gemini:
            return Invocation(argv: ["gemini", "-p", "Follow the instructions given on stdin."] + (m.isEmpty ? [] : ["-m", m]), stdin: prompt)
        case .auto, .api:
            return nil
        }
    }

    /// Dấu hiệu CLI chưa đăng nhập (để báo đúng nguyên nhân thay vì lỗi chung).
    static func looksUnauthenticated(_ text: String) -> Bool {
        let t = text.lowercased()
        return ["not logged in", "please log in", "please login", "/login", "invalid auth", "not authenticated", "unauthorized",
                "sign in", "authentication required", "no auth", "401"].contains { t.contains($0) }
    }

    static func run(_ inv: Invocation, timeout: TimeInterval, cwd: URL) -> (status: Int32, out: String, err: String, timedOut: Bool) {
        guard let exe = ProcessRunner.which(inv.argv[0]) else { return (127, "", "not found", false) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = Array(inv.argv.dropFirst())
        p.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ProcessRunner.searchPath
        env["NO_COLOR"] = "1"; env["CI"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err
        p.standardInput = inv.stdin == nil ? FileHandle.nullDevice : inp
        do { try p.run() } catch { return (126, "", "\(error)", false) }
        if let s = inv.stdin {
            DispatchQueue.global().async { inp.fileHandleForWriting.write(Data(s.utf8)); try? inp.fileHandleForWriting.close() }
        }
        var outData = Data(), errData = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        var timedOut = false
        let killer = DispatchWorkItem { timedOut = true; p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        p.waitUntilExit(); killer.cancel(); g.wait()
        return (p.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self), timedOut)
    }

    /// Chạy một CLI và trả về câu trả lời, hoặc ném `AdvisorError`.
    static func ask(_ p: AdvisorProvider, prompt: String, model: String = "", timeout: TimeInterval = 120) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("vutidy-advisor-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: scratch) }
                guard let inv = invocation(p, prompt: prompt, model: model, scratch: scratch) else { cont.resume(throwing: ScanAdvisor.AdvisorError.noProvider); return }
                let r = run(inv, timeout: timeout, cwd: scratch)
                let name = p.displayName
                if r.timedOut { cont.resume(throwing: ScanAdvisor.AdvisorError.cli(name, "timeout")); return }
                var text = r.out
                if let f = inv.outputFile, let s = try? String(contentsOf: f, encoding: .utf8) { text = s }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if r.status != 0 || text.isEmpty {
                    let detail = (r.err + "\n" + r.out).trimmingCharacters(in: .whitespacesAndNewlines)
                    if looksUnauthenticated(detail) { cont.resume(throwing: ScanAdvisor.AdvisorError.notLoggedIn(name)) }
                    else { cont.resume(throwing: ScanAdvisor.AdvisorError.cli(name, String(detail.suffix(200)))) }
                    return
                }
                cont.resume(returning: text)
            }
        }
    }
}

// MARK: - Danh sách model theo nguồn

public struct AdvisorModel: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum AdvisorModels {
    /// Model Claude dùng cho cả Claude Code (`--model`) lẫn Claude API.
    public static let claude: [AdvisorModel] = [
        .init(id: "claude-fable-5-1", name: "Claude Fable 5.1"), .init(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
        .init(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"), .init(id: "claude-haiku-5-5", name: "Claude Haiku 5.5"),
    ]
    static let gemini: [AdvisorModel] = [.init(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"), .init(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash")]

    /// Danh sách có sẵn, dùng khi chưa/không lấy được từ công cụ.
    public static func builtin(for p: AdvisorProvider) -> [AdvisorModel] {
        switch p {
        case .claudeCode, .api: return claude
        case .gemini: return gemini
        case .codex, .antigravity, .auto: return []
        }
    }

    /// `agy models`: mỗi dòng `id<TAB>Tên hiển thị` (dòng "Fetching…" bị bỏ qua).
    static func parseAgy(_ out: String) -> [AdvisorModel] {
        out.split(separator: "\n").compactMap { line in
            let c = line.split(separator: "\t", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            return c.count == 2 && !c[0].isEmpty && !c[0].contains(" ") ? AdvisorModel(id: c[0], name: c[1]) : nil
        }
    }

    /// `codex debug models`: JSON `{"models":[{"slug","display_name"}]}`.
    static func parseCodex(_ out: String) -> [AdvisorModel] {
        guard let d = out.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let ms = o["models"] as? [[String: Any]] else { return [] }
        return ms.compactMap { m in
            guard let slug = m["slug"] as? String, !slug.isEmpty else { return nil }
            return AdvisorModel(id: slug, name: (m["display_name"] as? String) ?? slug)
        }
    }

    /// Lấy danh sách model của nguồn: hỏi chính công cụ nếu nó có lệnh liệt kê, không được thì dùng danh sách có sẵn.
    public static func list(for p: AdvisorProvider) async -> [AdvisorModel] {
        switch p {
        case .antigravity:
            let r = await ProcessRunner.run(["agy", "models"], timeout: 40)
            let l = r.ok ? parseAgy(r.stdout) : []
            return l.isEmpty ? builtin(for: p) : l
        case .codex:
            let r = await ProcessRunner.run(["codex", "debug", "models"], timeout: 40)
            let l = r.ok ? parseCodex(r.stdout) : []
            return l.isEmpty ? builtin(for: p) : l
        default:
            return builtin(for: p)
        }
    }
}
