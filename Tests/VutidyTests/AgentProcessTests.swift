import Testing
import Foundation
@testable import Modules

@Suite struct AgentProcessTests {
    typealias Row = AgentProcesses.Row
    func row(_ pid: Int32, _ ppid: Int32, _ cmd: String, cpu: Double = 0, el: TimeInterval = 60, tty: String = "??") -> Row {
        Row(pid: pid, ppid: ppid, cpu: cpu, rssBytes: 1_000_000, elapsed: el, tty: tty, command: cmd)
    }

    @Test func classifiesKnownAgents() {
        #expect(AgentProcesses.classify(command: "/Users/a/.local/bin/claude --resume") == .claude)
        #expect(AgentProcesses.classify(command: "node /opt/lib/node_modules/@openai/codex/bin/codex.js") == .codex)
        #expect(AgentProcesses.classify(command: "npm exec @modelcontextprotocol/server-filesystem /tmp") == .mcp)
        #expect(AgentProcesses.classify(command: "node /x/chrome-devtools-mcp/build/index.js") == .mcp)
        #expect(AgentProcesses.classify(command: "/usr/local/bin/ollama serve") == .ollama)
    }

    @Test func ignoresUnrelatedAndDesktopApps() {
        #expect(AgentProcesses.classify(command: "/Applications/Claude.app/Contents/MacOS/Claude") == nil)
        #expect(AgentProcesses.classify(command: "/usr/bin/ssh host") == nil)
        #expect(AgentProcesses.classify(command: "/usr/sbin/mcpd") == nil)
    }

    @Test func parsesPsOutputAndElapsed() {
        let out = "  101     1   3.5  20480 2-03:04:05 ??       /usr/local/bin/claude -p x\n bad line\n"
        let rows = AgentProcesses.parse(out)
        #expect(rows.count == 1)
        #expect(rows[0].ppid == 1 && rows[0].rssBytes == 20480 * 1024 && rows[0].tty == "??")
        #expect(rows[0].elapsed == 2 * 86400 + 3 * 3600 + 4 * 60 + 5)
        #expect(AgentProcesses.parseElapsed("05:12") == 312)
        #expect(AgentProcesses.parseElapsed("1:02:03") == 3723)
        #expect(AgentProcesses.parseElapsed("xx") == nil)
    }

    @Test func buildsTreeAndFlagsOrphans() {
        let rows = [
            row(10, 5, "claude", tty: "ttys001"),
            row(11, 10, "node /x/mcp-server-git"),                       // sub-agent của 10
            row(20, 1, "node /x/mcp-server-fetch"),                       // mồ côi
            row(30, 1, "/usr/local/bin/ollama serve"),                    // server model: không mồ côi
            row(40, 10, "claude -p sub", cpu: 95, el: 1200),              // runaway
            row(50, 5, "/usr/bin/vim"),
        ]
        let a = AgentProcesses.analyze(rows: rows, selfPID: 999)
        func p(_ id: Int32) -> AgentProcess? { a.first { $0.pid == id } }
        #expect(a.count == 5)
        #expect(p(11)?.parentAgent == 10 && p(10)?.parentAgent == nil)
        #expect(p(20)?.orphaned == true && p(20)?.canTerminate == true)
        #expect(p(30)?.orphaned == false && p(30)?.canTerminate == false)
        #expect(p(40)?.runaway == true && p(40)?.parentAgent == 10)
        #expect(p(10)?.canTerminate == false)   // agent đang chạy bình thường không bao giờ bị đề nghị kết thúc
    }

    @Test func neverListsItself() {
        let a = AgentProcesses.analyze(rows: [row(7, 1, "claude")], selfPID: 7)
        #expect(a.isEmpty)
    }
}
