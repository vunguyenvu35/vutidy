import Testing
import Foundation
import CoreKit
@testable import Modules

@Suite struct ScanAdvisorTests {
    func item(_ path: String, _ cat: String, _ size: Int64, _ safety: SafetyLevel = .safe) -> ScanItem {
        ScanItem(url: URL(fileURLWithPath: path), title: URL(fileURLWithPath: path).lastPathComponent, allocatedSize: size,
                 category: cat, ruleID: "rule-\(cat)", safety: safety)
    }
    func agent(_ pid: Int32, _ kind: AgentProcess.Kind, parent: Int32? = nil, orphan: Bool = false, runaway: Bool = false) -> AgentProcess {
        AgentProcess(pid: pid, ppid: 1, kind: kind, command: "/Users/secretuser/bin/\(kind.rawValue) --token sk-ant-SECRET",
                     cpu: 1, footprint: 100_000_000, elapsed: 60, hasTTY: false, parentAgent: parent, orphaned: orphan, runaway: runaway)
    }
    func sample() -> SmartScanResult {
        var r = SmartScanResult()
        r.cleanup = [
            item("/Users/secretuser/Projects/acme-app/node_modules", "Node", 2_000_000_000),
            item("/Users/secretuser/Projects/other/node_modules", "Node", 1_000_000_000),
            item("/Users/secretuser/Library/Caches/x", "Cache", 500_000_000, .review),
            item("/Users/secretuser/a", "/Users/secretuser/leaky/category", 1_000_000),
        ]
        r.agents = [agent(1, .claude), agent(2, .mcp, parent: 1), agent(3, .mcp, orphan: true)]
        return r
    }

    @Test func inputIsAggregatedAndAnonymous() {
        let input = ScanAdvisor.makeInput(sample(), diskTotal: 500_000_000_000, diskFree: 120_000_000_000)
        #expect(input.diskTotalGB == 500 && input.diskFreeGB == 120)
        let node = input.cleanup.first { $0.category == "Node" }
        #expect(node?.items == 2 && node?.megabytes == 3000 && node?.safety == "safe")
        #expect(input.cleanup.contains { $0.category == "Cache" && $0.safety == "review" })
        let mcp = input.agentProcesses.first { $0.kind == "MCP server" }
        #expect(mcp?.count == 2 && mcp?.orphaned == 1 && mcp?.subAgents == 1 && mcp?.megabytes == 200)
    }

    @Test func payloadNeverContainsPathsOrCommandLines() {
        let json = ScanAdvisor.json(ScanAdvisor.makeInput(sample(), diskTotal: 1, diskFree: 1))
        for leak in ["secretuser", "/Users", "acme-app", "node_modules", "sk-ant", "--token", "rule-", "leaky"] {
            #expect(!json.contains(leak), "payload lộ '\(leak)'")
        }
        #expect(json.contains("\"Other\""))   // category trông như đường dẫn bị gộp vào Other
    }

    @Test func requestIsWellFormed() throws {
        let input = ScanAdvisor.makeInput(sample(), diskTotal: 1, diskFree: 1)
        let req = try ScanAdvisor.request(input: input, apiKey: "sk-test", model: "claude-haiku-5-5", language: "Tiếng Việt")
        #expect(req.url == ScanAdvisor.endpoint && req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try #require(JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect((body["system"] as? String)?.contains("Tiếng Việt") == true)
        let msg = (body["messages"] as? [[String: Any]])?.first?["content"] as? String
        #expect(msg?.contains("\"diskTotalGB\"") == true)
        #expect(!(String(data: req.httpBody ?? Data(), encoding: .utf8) ?? "").contains("secretuser"))
    }

    @Test func parsesTextAndErrors() throws {
        let ok = Data(#"{"content":[{"type":"text","text":"  - Dọn Node trước  "},{"type":"tool_use"},{"type":"text","text":"- Xem MCP mồ côi"}]}"#.utf8)
        #expect(try ScanAdvisor.parse(data: ok, status: 200) == "- Dọn Node trước\n- Xem MCP mồ côi")

        let err = Data(#"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        #expect(throws: ScanAdvisor.AdvisorError.http(401, "invalid x-api-key")) { try ScanAdvisor.parse(data: err, status: 401) }
        #expect(throws: ScanAdvisor.AdvisorError.empty) { try ScanAdvisor.parse(data: Data(#"{"content":[]}"#.utf8), status: 200) }
        #expect(throws: ScanAdvisor.AdvisorError.empty) { try ScanAdvisor.parse(data: Data("nope".utf8), status: 200) }
        #expect(throws: ScanAdvisor.AdvisorError.http(500, "")) { try ScanAdvisor.parse(data: Data("oops".utf8), status: 500) }
    }
}
