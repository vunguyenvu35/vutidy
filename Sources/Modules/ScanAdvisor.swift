import Foundation
import Security
import CoreKit

/// Dữ liệu gửi cho AI: chỉ số liệu tổng hợp. KHÔNG có đường dẫn, tên file, tên người dùng hay dòng lệnh.
public struct AdvisorInput: Codable, Sendable, Equatable {
    public struct Group: Codable, Sendable, Equatable {
        public var category: String
        public var safety: String
        public var items: Int
        public var megabytes: Int
    }
    public struct Agents: Codable, Sendable, Equatable {
        public var kind: String
        public var count: Int
        public var megabytes: Int
        public var orphaned: Int
        public var runaway: Int
        public var subAgents: Int
    }
    public var diskTotalGB: Int
    public var diskFreeGB: Int
    public var cleanup: [Group]
    public var agentProcesses: [Agents]
    public var suspiciousLaunchItems: Int
    public var cpuHeavyProcesses: Int
    /// Hành động AI được phép chọn (xem `AdvisorPlanner`). AI chỉ trả về `id` trong danh sách này.
    public var availableActions: [ActionInfo]
    /// Nhóm AI có thể xin xem chi tiết (xem `AdvisorInspector`).
    public var inspectableGroups: [String]

    public struct ActionInfo: Codable, Sendable, Equatable {
        public var id: String
        public var items: Int
        public var megabytes: Int
    }
}

public enum ScanAdvisor {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let defaultModel = "claude-haiku-5-5"

    public enum AdvisorError: Error, Equatable {
        case noKey, http(Int, String), empty, network(String)
        /// Không có CLI nào dùng được và cũng không có API key.
        case noProvider
        /// CLI có cài nhưng chưa đăng nhập.
        case notLoggedIn(String)
        /// CLI chạy lỗi (tên, chi tiết ngắn).
        case cli(String, String)
    }

    // MARK: Dữ liệu gửi đi

    public static func makeInput(_ r: SmartScanResult, diskTotal: Int64, diskFree: Int64) -> AdvisorInput {
        let gb = { (b: Int64) in Int((Double(b) / 1_000_000_000).rounded()) }
        let mb = { (b: Int64) in Int((Double(b) / 1_000_000).rounded()) }

        struct Key: Hashable { var cat: String, safety: String }
        var acc: [Key: (n: Int, bytes: Int64)] = [:]
        for it in r.cleanup {
            // Nhóm lấy từ rule nên là tên cố định; vẫn loại mọi thứ trông như đường dẫn hoặc quá dài.
            let c = (it.category.contains("/") || it.category.count > 40) ? "Other" : it.category
            let k = Key(cat: c, safety: it.safety.rawValue)
            acc[k, default: (0, 0)].n += 1
            acc[k, default: (0, 0)].bytes += it.allocatedSize
        }
        let groups = acc.map { AdvisorInput.Group(category: $0.key.cat, safety: $0.key.safety, items: $0.value.n, megabytes: mb($0.value.bytes)) }
            .sorted { ($0.megabytes, $0.category) > ($1.megabytes, $1.category) }
            .prefix(30)

        let agents = Dictionary(grouping: r.agents, by: \.kind).map { kind, list in
            AdvisorInput.Agents(kind: kind.displayName, count: list.count, megabytes: mb(list.reduce(0) { $0 + $1.footprint }),
                                orphaned: list.filter(\.orphaned).count, runaway: list.filter(\.runaway).count,
                                subAgents: list.filter { $0.parentAgent != nil }.count)
        }.sorted { $0.kind < $1.kind }

        return AdvisorInput(diskTotalGB: gb(diskTotal), diskFreeGB: gb(diskFree), cleanup: Array(groups), agentProcesses: agents,
                            suspiciousLaunchItems: r.suspiciousCount, cpuHeavyProcesses: r.consumers.filter { $0.cpu >= 50 }.count,
                            availableActions: AdvisorPlanner.availableActions(r).map { .init(id: $0.id, items: $0.items, megabytes: $0.megabytes) },
                            inspectableGroups: AdvisorInspector.inspectableGroups(r))
    }

    public static func json(_ input: AdvisorInput) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: e.encode(input), encoding: .utf8)) ?? "{}"
    }

    // MARK: Yêu cầu / phản hồi

    static func systemPrompt(language: String) -> String {
        """
        You are the advisor inside Vutidy, a macOS cleaner. You receive anonymized scan totals (no paths, no file names) \
        and "availableActions": the only things the app can do for the user right now.
        Decide what is worth doing and in which order. Orphaned agent processes lost their parent; runaway ones burned \
        high CPU for a long time; sub-agents belong to a parent agent (do not touch healthy agents). Actions: \
        "clean:<group>" moves that group's safe items to Quarantine (undoable); "tool:<group>" runs the tool's own cleanup \
        command (e.g. docker image/build-cache prune, go clean, brew cleanup): it removes only re-creatable data but CANNOT \
        be undone, and it is often where most of the space is, so do not ignore it when it is large; "terminate-agents" \
        quits orphaned or runaway agent processes; "review:<group>" only opens the page so the user can check items \
        themselves. Never pick an id that is not in availableActions, and never use clean or tool for something that needs review. \
        Rank by space freed. In the summary say plainly which actions are undoable and which are not.
        If the totals are not enough to judge a large group (for example what is inside Docker, a big Go or dependency cache, \
        or whether items are old and unused), you may ask once to look inside up to \(AdvisorInspector.maxGroups) groups from \
        "inspectableGroups" by replying with ONLY {"inspect": ["<group>", ...]}. You then get read-only, anonymized details \
        (name, size, age, days idle, location, the tool command that would run, and for Docker the image list with inUse) and \
        must answer with the final plan. Ask only when it changes your decision; otherwise answer directly.
        Otherwise reply with ONLY a JSON object, no prose, no code fences:
        {"summary": "<2-4 short lines of plain text>", "actions": [{"id": "<id from availableActions>", "reason": "<one short sentence>"}]}
        Put the most valuable action first, at most 6 actions, skip actions that are not worth it. \
        Write summary and reasons in \(language).
        """
    }
    public static func request(input: AdvisorInput, apiKey: String, model: String, language: String, details: String? = nil) throws -> URLRequest {
        var req = URLRequest(url: endpoint, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": 700, "system": systemPrompt(language: language),
            "messages": [["role": "user", "content": userContent(input, details: details)]],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    public static func parse(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
            throw AdvisorError.http(status, msg)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else { throw AdvisorError.empty }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        if text.isEmpty { throw AdvisorError.empty }
        return text
    }

    /// Prompt đầy đủ cho CLI (không có kênh system riêng): hướng dẫn + số liệu.
    static func cliPrompt(input: AdvisorInput, language: String, details: String? = nil) -> String {
        systemPrompt(language: language) + "\n\n" + userContent(input, details: details)
    }

    /// Vòng 1: số liệu tổng hợp. Vòng 2 (sau khi AI xin xem sâu): thêm chi tiết các nhóm đó và yêu cầu kế hoạch cuối.
    static func userContent(_ input: AdvisorInput, details: String?) -> String {
        var s = "Scan summary:\n" + json(input)
        if let details {
            s += "\n\nYou asked to look inside these groups. Read-only, anonymized details:\n" + details
            s += "\n\nNow reply with the FINAL plan JSON only ({\"summary\", \"actions\"}). Do not ask to inspect again."
        }
        return s
    }

    /// Chọn nguồn tư vấn: CLI đã đăng nhập trên máy trước, API key (nếu có) là phương án cuối. `.auto` thử lần lượt đến khi có câu trả lời.
    /// `models`: model đã chọn cho từng nguồn (khóa là `AdvisorProvider.rawValue`); rỗng = mặc định của công cụ.
    public static func advise(_ input: AdvisorInput, provider: AdvisorProvider, models: [String: String], language: String, details: String? = nil) async throws -> AdvisorAnswer {
        func model(_ p: AdvisorProvider) -> String { (models[p.rawValue] ?? "").trimmingCharacters(in: .whitespaces) }
        let apiModel = model(.api).isEmpty ? defaultModel : model(.api)
        let prompt = cliPrompt(input: input, language: language, details: details)
        switch provider {
        case .api:
            return AdvisorAnswer(text: try await advise(input, model: apiModel, language: language, details: details), provider: .api)
        case .auto:
            var firstError: Error?
            for p in AdvisorProvider.installedCLIs {
                do { return AdvisorAnswer(text: try await AdvisorCLI.ask(p, prompt: prompt, model: model(p)), provider: p) }
                catch { firstError = firstError ?? error }
            }
            if AdvisorKeychain.hasKey { return AdvisorAnswer(text: try await advise(input, model: apiModel, language: language, details: details), provider: .api) }
            throw firstError ?? AdvisorError.noProvider
        default:
            guard provider.isInstalled else { throw AdvisorError.noProvider }
            return AdvisorAnswer(text: try await AdvisorCLI.ask(provider, prompt: prompt, model: model(provider)), provider: provider)
        }
    }

    public struct DeepAnswer: Sendable {
        public let answer: AdvisorAnswer
        /// Các nhóm AI đã xin xem sâu (rỗng nếu trả lời ngay từ số liệu tổng hợp).
        public let inspected: [String]
        /// JSON chi tiết đã gửi ở vòng 2, để người dùng xem lại đúng dữ liệu đã đi đâu.
        public let details: String?
    }

    /// Đào sâu theo yêu cầu: vòng 1 chỉ có số liệu tổng hợp; nếu AI xin xem một số nhóm (`deep` bật), app đọc chi tiết trên máy
    /// (chỉ-đọc, ẩn danh) rồi hỏi vòng 2 để lấy kế hoạch cuối. Tối đa hai lần gọi, cùng một nguồn AI.
    public static func adviseDeep(_ input: AdvisorInput, result: SmartScanResult, provider: AdvisorProvider, models: [String: String],
                                  language: String, deep: Bool, onStatus: @Sendable (String) -> Void = { _ in }) async throws -> DeepAnswer {
        let first = try await advise(input, provider: provider, models: models, language: language)
        guard deep, let groups = AdvisorPlanner.parseInspectRequest(first.text, allowed: input.inspectableGroups) else {
            return DeepAnswer(answer: first, inspected: [], details: nil)
        }
        onStatus(groups.joined(separator: ", "))
        let json = AdvisorInspector.json(await AdvisorInspector.inspect(groups, in: result))
        let second = try await advise(input, provider: first.provider, models: models, language: language, details: json)
        return DeepAnswer(answer: second, inspected: groups, details: json)
    }

    /// `send` có thể thay thế khi kiểm thử.
    public static func advise(_ input: AdvisorInput, model: String, language: String, details: String? = nil,
                              send: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) async throws -> String {
        guard let key = AdvisorKeychain.load(), !key.isEmpty else { throw AdvisorError.noKey }
        let req = try request(input: input, apiKey: key, model: model, language: language, details: details)
        do {
            let (data, resp) = try await send(req)
            return try parse(data: data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0)
        } catch let e as AdvisorError { throw e }
        catch { throw AdvisorError.network(error.localizedDescription) }
    }
}

/// API key nằm trong Keychain của user, không bao giờ vào UserDefaults hay log.
public enum AdvisorKeychain {
    private static let service = "app.vutidy.advisor"
    private static let account = "anthropic-api-key"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public static func load() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    public static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        delete()
        guard !trimmed.isEmpty else { return true }
        var q = base
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() { SecItemDelete(base as CFDictionary) }
    public static var hasKey: Bool { load()?.isEmpty == false }
}
