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

@Suite struct AdvisorCLITests {
    let scratch = URL(fileURLWithPath: "/tmp/scratch")

    @Test func claudeRunsWithoutToolsAndReadsPromptFromStdin() throws {
        let inv = try #require(AdvisorCLI.invocation(.claudeCode, prompt: "P", scratch: scratch))
        #expect(inv.argv.first == "claude" && inv.argv.contains("-p"))
        #expect(inv.stdin == "P" && !inv.argv.contains("P"))   // prompt không nằm trên dòng lệnh (ps)
        let i = try #require(inv.argv.firstIndex(of: "--tools"))
        #expect(inv.argv[i + 1] == "")                        // không cho dùng tool nào
        #expect(inv.argv.contains("--no-session-persistence"))
    }

    @Test func codexIsReadOnlyAndWritesAnswerToFile() throws {
        let inv = try #require(AdvisorCLI.invocation(.codex, prompt: "P", scratch: scratch))
        #expect(inv.argv.starts(with: ["codex", "exec"]))
        let s = try #require(inv.argv.firstIndex(of: "-s"))
        #expect(inv.argv[s + 1] == "read-only")
        #expect(inv.argv.contains("--ephemeral") && inv.argv.last == "-")
        #expect(inv.outputFile?.path == "/tmp/scratch/codex-answer.txt" && inv.stdin == "P")
    }

    @Test func antigravityAndGeminiInvocations() throws {
        let agy = try #require(AdvisorCLI.invocation(.antigravity, prompt: "P", scratch: scratch))
        #expect(agy.argv == ["agy", "-p", "P", "--mode", "plan"] && agy.stdin == nil)
        let g = try #require(AdvisorCLI.invocation(.gemini, prompt: "P", scratch: scratch))
        #expect(g.argv.first == "gemini" && g.stdin == "P")
        #expect(AdvisorCLI.invocation(.auto, prompt: "P", scratch: scratch) == nil)
        #expect(AdvisorCLI.invocation(.api, prompt: "P", scratch: scratch) == nil)
    }

    @Test func detectsUnauthenticatedOutput() {
        #expect(AdvisorCLI.looksUnauthenticated("Invalid auth method selected."))
        #expect(AdvisorCLI.looksUnauthenticated("Error: Not logged in · Please run /login"))
        #expect(!AdvisorCLI.looksUnauthenticated("segmentation fault"))
    }

    @Test func cliOrderPrefersClaudeThenCodex() {
        #expect(AdvisorProvider.cliOrder == [.claudeCode, .codex, .antigravity, .gemini])
        #expect(AdvisorProvider.api.isInstalled && AdvisorProvider.auto.isInstalled)
    }

    @Test func promptCarriesInstructionsAndData() {
        var r = SmartScanResult()
        r.cleanup = [ScanItem(url: URL(fileURLWithPath: "/Users/secretuser/x"), title: "x", allocatedSize: 1_000_000_000, category: "Node", ruleID: "r", safety: .safe)]
        let p = ScanAdvisor.cliPrompt(input: ScanAdvisor.makeInput(r, diskTotal: 1, diskFree: 1), language: "Tiếng Việt")
        #expect(p.contains("Tiếng Việt") && p.contains("\"Node\""))
        #expect(!p.contains("secretuser"))
    }
}

@Suite struct AdvisorModelTests {
    let scratch = URL(fileURLWithPath: "/tmp/scratch")

    @Test func modelFlagIsPassedOnlyWhenChosen() throws {
        func argv(_ p: AdvisorProvider, _ m: String) throws -> [String] { try #require(AdvisorCLI.invocation(p, prompt: "P", model: m, scratch: scratch)).argv }
        let c = try argv(.claudeCode, "claude-haiku-5-5"); #expect(c.contains("--model") && c[c.firstIndex(of: "--model")! + 1] == "claude-haiku-5-5")
        let x = try argv(.codex, "gpt-x"); #expect(x[x.firstIndex(of: "-m")! + 1] == "gpt-x" && x.last == "-")   // -m đứng trước -o … -
        let a = try argv(.antigravity, "gemini-4-argon-high"); #expect(a.suffix(2) == ["--model", "gemini-4-argon-high"])
        let g = try argv(.gemini, "gemini-2.5-flash"); #expect(g.suffix(2) == ["-m", "gemini-2.5-flash"])
        for p in AdvisorProvider.cliOrder {
            let none = try argv(p, "  ")
            #expect(!none.contains("--model") && !none.contains("-m"), "\(p) truyền model rỗng")
        }
    }

    @Test func parsesAgyModelList() {
        let out = "Fetching available models...\ngemini-4-argon-medium\tGemini 4 Argon (Medium)\nbad line without tab\ngemini-3.8-flash-low\tGemini 3.8 Flash (Low)\n"
        #expect(AdvisorModels.parseAgy(out) == [.init(id: "gemini-4-argon-medium", name: "Gemini 4 Argon (Medium)"),
                                                .init(id: "gemini-3.8-flash-low", name: "Gemini 3.8 Flash (Low)")])
    }

    @Test func parsesCodexModelList() {
        let json = #"{"models":[{"slug":"gpt-a","display_name":"GPT A"},{"slug":"gpt-b"},{"display_name":"no slug"}]}"#
        #expect(AdvisorModels.parseCodex(json) == [.init(id: "gpt-a", name: "GPT A"), .init(id: "gpt-b", name: "gpt-b")])
        #expect(AdvisorModels.parseCodex("not json").isEmpty)
    }

    @Test func builtinListsMatchProviders() {
        #expect(AdvisorModels.builtin(for: .api) == AdvisorModels.builtin(for: .claudeCode))
        #expect(AdvisorModels.builtin(for: .codex).isEmpty && AdvisorModels.builtin(for: .auto).isEmpty)
        #expect(AdvisorModels.builtin(for: .api).contains { $0.id == ScanAdvisor.defaultModel })
    }
}

@Suite struct AdvisorPlanTests {
    func item(_ cat: String, _ size: Int64, _ safety: SafetyLevel = .safe, cmd: [String]? = nil) -> ScanItem {
        ScanItem(url: URL(fileURLWithPath: "/Users/secretuser/x"), title: "x", allocatedSize: size, category: cat, ruleID: "r", safety: safety, command: cmd)
    }
    func result() -> SmartScanResult {
        var r = SmartScanResult()
        r.cleanup = [item("Node", 2_000_000_000), item("Node", 1_000_000_000), item("Docker", 4_000_000_000, cmd: ["docker", "prune"]),
                     item("Cache", 500_000_000, .review), item("/Users/secretuser/leaky", 10_000_000)]
        r.agents = [AgentProcess(pid: 9, ppid: 1, kind: .mcp, command: "x", cpu: 0, footprint: 50_000_000, elapsed: 60, hasTTY: false,
                                 parentAgent: nil, orphaned: true, runaway: false)]
        return r
    }

    @Test func offersOnlyReversibleSafeCleansAndReviewOnlyForReviewItems() {
        let acts = AdvisorPlanner.availableActions(result())
        let ids = Set(acts.map(\.id))
        #expect(ids.contains("clean:Node") && ids.contains("terminate-agents") && ids.contains("review:Cache"))
        #expect(!ids.contains("clean:Docker"), "mục dùng lệnh docker không hoàn tác được: không cho AI tự dọn")
        #expect(!ids.contains("clean:Cache"), "mục cần xem lại không được dọn")
        let node = acts.first { $0.id == "clean:Node" }
        #expect(node?.items == 2 && node?.megabytes == 3000 && node?.kind == .clean)
        #expect(ids.contains("clean:Other") && !ids.contains { $0.contains("leaky") && !$0.hasSuffix("Other") })
    }

    @Test func parsesPlanFromProseAndCodeFences() {
        let acts = AdvisorPlanner.availableActions(result())
        let text = """
        Here you go:
        ```json
        {"summary": "Clean Node first.", "actions": [
          {"id": "clean:Node", "reason": "Largest safe group."},
          {"id": "review:Cache", "reason": "Check by hand."}]}
        ```
        """
        let plan = AdvisorPlanner.parse(text, available: acts)
        #expect(plan?.summary == "Clean Node first.")
        #expect(plan?.steps.map(\.id) == ["clean:Node", "review:Cache"])
        #expect(plan?.steps.first?.reason == "Largest safe group.")
    }

    @Test func dropsUnknownIdsDuplicatesAndCapsAtSix() {
        let acts = AdvisorPlanner.availableActions(result())
        let json = #"{"summary":"s","actions":[{"id":"rm -rf /"},{"id":"clean:Docker"},{"id":"clean:Node"},{"id":"clean:Node"},{"id":"terminate-agents","reason":"x"}]}"#
        let plan = AdvisorPlanner.parse(json, available: acts)
        #expect(plan?.steps.map(\.id) == ["clean:Node", "terminate-agents"])
        let many = (0..<10).map { _ in #"{"id":"clean:Node"}"# }.joined(separator: ",")
        #expect(AdvisorPlanner.parse(#"{"summary":"s","actions":[\#(many)]}"#, available: acts)?.steps.count == 1)
    }

    @Test func rejectsNonJsonAndEmptyPlans() {
        let acts = AdvisorPlanner.availableActions(result())
        #expect(AdvisorPlanner.parse("- clean node\n- review cache", available: acts) == nil)
        #expect(AdvisorPlanner.parse(#"{"summary":"","actions":[{"id":"nope"}]}"#, available: acts) == nil)
        #expect(AdvisorPlanner.parse("{broken", available: acts) == nil)
        #expect(AdvisorPlanner.parse(#"{"summary":["a","b"],"actions":[]}"#, available: acts)?.summary == "a\nb")
    }

    @Test func payloadListsActionsWithoutPaths() {
        let json = ScanAdvisor.json(ScanAdvisor.makeInput(result(), diskTotal: 1, diskFree: 1))
        #expect(json.contains("\"availableActions\"") && json.contains("clean:Node") && json.contains("terminate-agents"))
        #expect(!json.contains("secretuser") && !json.contains("/Users"))
        let prompt = ScanAdvisor.systemPrompt(language: "Tiếng Việt")
        #expect(prompt.contains("ONLY a JSON object") && prompt.contains("availableActions") && prompt.contains("Tiếng Việt"))
    }
}

@Suite struct AdvisorTrashTests {
    @Test func trashIsNeverAnAction() {
        var r = SmartScanResult()
        r.cleanup = [ScanItem(url: URL(fileURLWithPath: "/x"), title: "x", allocatedSize: 72_000_000, category: "Trash", ruleID: "trash", safety: .safe),
                     ScanItem(url: URL(fileURLWithPath: "/y"), title: "y", allocatedSize: 5_000_000, category: "Cache", ruleID: "user-caches", safety: .safe)]
        let ids = AdvisorPlanner.availableActions(r).map(\.id)
        #expect(ids == ["clean:Cache"], "Thùng rác xóa vĩnh viễn, không được đề xuất như dọn vào Quarantine")
    }
}

@Suite struct AdvisorTinyGroupTests {
    @Test func tinyCleanGroupsAreNotSteps() {
        var r = SmartScanResult()
        r.cleanup = [ScanItem(url: URL(fileURLWithPath: "/a"), title: "a", allocatedSize: 3_000, category: "Logs", ruleID: "user-logs", safety: .safe),
                     ScanItem(url: URL(fileURLWithPath: "/b"), title: "b", allocatedSize: 840_000_000, category: "Cache", ruleID: "user-caches", safety: .safe)]
        #expect(AdvisorPlanner.availableActions(r).map(\.id) == ["clean:Cache"])
    }
}
