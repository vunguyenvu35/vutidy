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
}

public enum ScanAdvisor {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let defaultModel = "claude-haiku-5-5"

    public enum AdvisorError: Error, Equatable {
        case noKey, http(Int, String), empty, network(String)
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
                            suspiciousLaunchItems: r.suspiciousCount, cpuHeavyProcesses: r.consumers.filter { $0.cpu >= 50 }.count)
    }

    public static func json(_ input: AdvisorInput) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: e.encode(input), encoding: .utf8)) ?? "{}"
    }

    // MARK: Yêu cầu / phản hồi

    static func systemPrompt(language: String) -> String {
        """
        You are the advisor inside Vutidy, a macOS cleaner. You receive anonymized scan totals (no paths, no file names).
        Give a short, practical plan: which cleanup groups are worth cleaning first and why, what to do about AI agent \
        processes (orphaned = parent died, runaway = high CPU for a long time; sub-agents belong to a parent agent), and \
        anything that deserves a manual look. Never suggest deleting items marked "review" without the user checking them. \
        You cannot take actions yourself; the user decides. Be concise: at most 6 short bullet points, no preamble. \
        Reply in \(language).
        """
    }

    public static func request(input: AdvisorInput, apiKey: String, model: String, language: String) throws -> URLRequest {
        var req = URLRequest(url: endpoint, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model, "max_tokens": 700, "system": systemPrompt(language: language),
            "messages": [["role": "user", "content": "Scan summary:\n" + json(input)]],
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

    /// `send` có thể thay thế khi kiểm thử.
    public static func advise(_ input: AdvisorInput, model: String, language: String,
                              send: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }) async throws -> String {
        guard let key = AdvisorKeychain.load(), !key.isEmpty else { throw AdvisorError.noKey }
        let req = try request(input: input, apiKey: key, model: model, language: language)
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
