import Foundation
import Darwin
import CoreKit

/// Một tiến trình thuộc AI agent (Claude Code, Codex, MCP server, Ollama…) đang chạy trên máy của user.
public struct AgentProcess: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        case claude, codex, gemini, aider, cursorAgent, opencode, mcp, ollama

        public var displayName: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .gemini: return "Gemini CLI"
            case .aider: return "Aider"
            case .cursorAgent: return "Cursor Agent"
            case .opencode: return "OpenCode"
            case .mcp: return "MCP server"
            case .ollama: return "Ollama"
            }
        }
        /// Máy chủ model chạy nền có chủ đích: không bao giờ bị coi là mồ côi.
        public var isModelServer: Bool { self == .ollama }
    }

    public var id: Int32 { pid }
    public let pid: Int32
    public let ppid: Int32
    public let kind: Kind
    /// Dòng lệnh đã rút gọn, chỉ để hiển thị.
    public let command: String
    public let cpu: Double
    public let footprint: Int64
    public let elapsed: TimeInterval
    public let hasTTY: Bool
    /// PID của agent gần nhất phía trên trong cây tiến trình (nil nếu đây là agent gốc). Dùng để gom sub-agent.
    public let parentAgent: Int32?
    /// Cha đã chết, tiến trình bị launchd nhận nuôi.
    public let orphaned: Bool
    /// CPU cao kéo dài.
    public let runaway: Bool

    /// Chỉ cho phép kết thúc khi đáng ngờ: mồ côi hoặc ngốn CPU kéo dài.
    public var canTerminate: Bool { orphaned || runaway }
}

public enum AgentProcesses {
    /// Một dòng `ps` thô.
    struct Row: Equatable {
        var pid: Int32, ppid: Int32, cpu: Double, rssBytes: Int64, elapsed: TimeInterval, tty: String, command: String
    }

    static let runawayCPU = 80.0
    static let runawaySeconds: TimeInterval = 600

    // MARK: Nhận diện

    /// Nhận diện tiến trình AI agent qua dòng lệnh. Thuần hàm để dễ kiểm thử.
    static func classify(command: String) -> AgentProcess.Kind? {
        let lower = command.lowercased()
        guard let first = lower.split(separator: " ", maxSplits: 1).first else { return nil }
        let exe = (String(first) as NSString).lastPathComponent
        let inApp = lower.contains(".app/contents/")

        // Chỉ xét chương trình và đối số vị trí: bỏ cờ (`-x`, `--mcp-…`) và URL, nếu không `docker-agent --mcp-oauth-redirect-uri …` bị nhận nhầm.
        let positional = lower.split(separator: " ").filter { !$0.hasPrefix("-") && !$0.contains("://") }.joined(separator: " ")
        if positional.contains("modelcontextprotocol") || positional.range(of: #"(^|[\s/@_-])mcp([\s/@_.-]|@|$)"#, options: .regularExpression) != nil {
            return .mcp
        }
        if exe == "ollama" { return .ollama }
        if !inApp {
            if exe == "claude" || lower.contains("@anthropic-ai/claude-code") { return .claude }
            if exe == "codex" || lower.contains("@openai/codex") { return .codex }
            if exe == "gemini" || lower.contains("@google/gemini-cli") { return .gemini }
        }
        if exe == "aider" { return .aider }
        if exe == "cursor-agent" { return .cursorAgent }
        if exe == "opencode" { return .opencode }
        return nil
    }

    // MARK: Phân tích

    /// Parse `ps -xww -o pid=,ppid=,pcpu=,rss=,etime=,tty=,command=`.
    static func parse(_ output: String) -> [Row] {
        output.split(separator: "\n").compactMap { line in
            let p = line.split(separator: " ", maxSplits: 6, omittingEmptySubsequences: true)
            guard p.count == 7, let pid = Int32(p[0]), let ppid = Int32(p[1]), let cpu = Double(p[2]),
                  let rss = Int64(p[3]), let el = parseElapsed(String(p[4])) else { return nil }
            return Row(pid: pid, ppid: ppid, cpu: cpu, rssBytes: rss * 1024, elapsed: el, tty: String(p[5]),
                       command: String(p[6]).trimmingCharacters(in: .whitespaces))
        }
    }

    /// `[[dd-]hh:]mm:ss` → giây.
    static func parseElapsed(_ s: String) -> TimeInterval? {
        var days = 0.0, rest = s
        if let dash = s.firstIndex(of: "-") {
            guard let d = Double(s[..<dash]) else { return nil }
            days = d; rest = String(s[s.index(after: dash)...])
        }
        let parts = rest.split(separator: ":").map { Double($0) }
        guard (2...3).contains(parts.count), !parts.contains(where: { $0 == nil }) else { return nil }
        let nums = parts.compactMap { $0 }
        let secs = nums.count == 3 ? nums[0] * 3600 + nums[1] * 60 + nums[2] : nums[0] * 60 + nums[1]
        return days * 86400 + secs
    }

    static func analyze(rows: [Row], footprint: (Int32) -> Int64? = { _ in nil }, selfPID: Int32 = getpid()) -> [AgentProcess] {
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var kinds: [Int32: AgentProcess.Kind] = [:]
        for r in rows where r.pid != selfPID { if let k = classify(command: r.command) { kinds[r.pid] = k } }

        func agentAncestor(of pid: Int32) -> Int32? {
            var cur = byPID[pid]?.ppid ?? 0, depth = 0
            while cur > 1, depth < 64 {
                if kinds[cur] != nil { return cur }
                cur = byPID[cur]?.ppid ?? 0; depth += 1
            }
            return nil
        }

        return rows.compactMap { r -> AgentProcess? in
            guard let kind = kinds[r.pid] else { return nil }
            let hasTTY = r.tty != "??" && r.tty != "?"
            let orphaned = r.ppid == 1 && !kind.isModelServer && !hasTTY
            let runaway = r.cpu >= runawayCPU && r.elapsed >= runawaySeconds && !kind.isModelServer
            let cmd = r.command.count > 140 ? String(r.command.prefix(140)) + "…" : r.command
            return AgentProcess(pid: r.pid, ppid: r.ppid, kind: kind, command: cmd, cpu: r.cpu,
                                footprint: footprint(r.pid) ?? r.rssBytes, elapsed: r.elapsed, hasTTY: hasTTY,
                                parentAgent: agentAncestor(of: r.pid), orphaned: orphaned, runaway: runaway)
        }
        .sorted { ($0.orphaned || $0.runaway ? 1 : 0, $0.footprint) > ($1.orphaned || $1.runaway ? 1 : 0, $1.footprint) }
    }

    /// Quét các tiến trình AI agent của user hiện tại.
    public static func scan() async -> [AgentProcess] {
        let r = await ProcessRunner.run(["ps", "-xww", "-o", "pid=,ppid=,pcpu=,rss=,etime=,tty=,command="], timeout: 20)
        guard r.ok else { return [] }
        return analyze(rows: parse(r.stdout), footprint: { Optimization.footprint(of: $0) })
    }

    // MARK: Kết thúc

    public enum TerminateError: Error { case gone, changed, notAllowed, failed(Int32) }

    /// Gửi SIGTERM tới một agent đáng ngờ. Quét lại ngay trước khi gửi để chắc PID chưa bị tái sử dụng cho tiến trình khác.
    public static func terminate(_ agent: AgentProcess) async -> Result<Void, TerminateError> {
        guard agent.canTerminate else { return .failure(.notAllowed) }
        let now = await scan()
        guard let cur = now.first(where: { $0.pid == agent.pid }) else { return .failure(.gone) }
        guard cur.kind == agent.kind, cur.command == agent.command, cur.canTerminate else { return .failure(.changed) }
        return kill(agent.pid, SIGTERM) == 0 ? .success(()) : .failure(.failed(errno))
    }
}
