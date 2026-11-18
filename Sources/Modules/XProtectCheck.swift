import Foundation
import CoreKit

/// Một lần chạy của một module XProtect Remediator (mỗi module là một họ malware: SnowBeagle, Trovi, Adload…).
public struct XProtectEvent: Sendable, Equatable {
    public let plugin: String
    public let date: Date
    public let code: Int?
    public let status: String
    /// Những gì module nêu ra làm căn cứ (đường dẫn, tên…); rỗng khi không có gì.
    public let causedBy: [String]

    /// Hai trạng thái bình thường quan sát được: "NoThreatDetected" và "Success" (module hạ tầng chạy xong). Còn lại, hoặc bất kỳ
    /// trạng thái nào kèm căn cứ, đều coi là đáng chú ý và hiện nguyên văn, vì chưa thấy mẫu "phát hiện thật" để biết chắc định dạng.
    public var isThreat: Bool { !causedBy.isEmpty || !["NoThreatDetected", "Success"].contains(status) }
}

public struct XProtectInfo: Sendable, Equatable {
    public var version: String?
    public var installed: Date?
    public var launchScans: Bool?
    public var backgroundScans: Bool?
    /// Số module Remediator có kết quả trong nhật ký và thời điểm quét gần nhất.
    public var modulesRun = 0
    public var lastScan: Date?
    public var detections: [XProtectEvent] = []

    public func updateAgeDays(now: Date = Date()) -> Int? { installed.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) } }
    public static let staleAfterDays = 45
}

/// Đọc kết quả của chính macOS: `xprotect status` và nhật ký sự kiện của các module XProtect Remediator.
/// Chỉ đọc, chạy trên máy, không gửi gì đi đâu. Nhật ký hệ thống chỉ giữ vài ngày nên có thể trống.
public enum XProtectCheck {
    static let predicate = #"subsystem == "com.apple.XProtectFramework.PluginAPI" AND category == "XPEvent.structured""#

    // MARK: Phân tích (thuần hàm)

    /// `xprotect status` + `xprotect version` (nối lại): "XProtect launch scans: enabled", "XProtect background scans: enabled", "Version: 5372 Installed: 2026-11-11 19:02:29 +0000".
    static func parseStatus(_ out: String) -> (launch: Bool?, background: Bool?, version: String?, installed: Date?) {
        func flag(_ key: String) -> Bool? {
            guard let line = out.split(separator: "\n").first(where: { $0.lowercased().contains(key) })?.lowercased() else { return nil }
            return line.contains("enabled") ? true : (line.contains("disabled") ? false : nil)
        }
        var version: String?, installed: Date?
        if let line = out.split(separator: "\n").first(where: { $0.hasPrefix("Version:") }) {
            let parts = line.split(separator: " ")
            if parts.count > 1 { version = String(parts[1]) }
            if let i = parts.firstIndex(of: "Installed:"), parts.count > i + 2 {
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
                installed = f.date(from: parts[(i + 1)...(i + 3 > parts.count - 1 ? parts.count - 1 : i + 3)].joined(separator: " "))
            }
        }
        return (flag("launch scans"), flag("background scans"), version, installed)
    }

    /// Dòng `log show --style compact`:
    /// `2026-11-17 22:07:15.103 Df XProtectRemediatorFloppyFlipper[76674:67b089] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {json}`
    static func parseEvents(_ log: String) -> [XProtectEvent] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        var out: [XProtectEvent] = []
        for line in log.split(separator: "\n") {
            guard let r = line.range(of: "XProtectRemediator"), line.contains("XPEvent.structured"),
                  let open = line.firstIndex(of: "{"), let close = line.lastIndex(of: "}"), open < close else { continue }
            let afterName = line[r.upperBound...]
            guard let bracket = afterName.firstIndex(of: "[") else { continue }
            let plugin = String(afterName[..<bracket])
            guard !plugin.isEmpty, let date = f.date(from: String(line.prefix(23))),
                  let data = String(line[open...close]).data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let status = obj["status_message"] as? String else { continue }
            let causes: [String] = ((obj["caused_by"] as? [Any]) ?? []).map { c in
                if let s = c as? String { return s }
                if let d = try? JSONSerialization.data(withJSONObject: c), let s = String(data: d, encoding: .utf8) { return s }
                return "\(c)"
            }
            out.append(XProtectEvent(plugin: plugin, date: date, code: obj["status_code"] as? Int, status: status, causedBy: causes))
        }
        return out
    }

    /// Mỗi module chỉ tính lần chạy gần nhất: một phát hiện cũ đã được xử lý ở lần sau không còn là cảnh báo.
    static func summarize(_ events: [XProtectEvent]) -> (modules: Int, last: Date?, detections: [XProtectEvent]) {
        var latest: [String: XProtectEvent] = [:]
        for e in events where latest[e.plugin].map({ $0.date < e.date }) ?? true { latest[e.plugin] = e }
        return (latest.count, latest.values.map(\.date).max(), latest.values.filter(\.isThreat).sorted { $0.plugin < $1.plugin })
    }

    /// Phát hiện của XProtect và cảnh báo "chưa cập nhật" thành mục trong báo cáo malware.
    static func findings(_ info: XProtectInfo, now: Date = Date()) -> [SecurityFinding] {
        var out: [SecurityFinding] = []
        for d in info.detections {
            let why = d.causedBy.isEmpty ? "" : " " + trf("Căn cứ: %@", d.causedBy.prefix(3).joined(separator: "; "))
            out.append(.init(severity: .high, title: trf("XProtect (%@) báo: %@", d.plugin, d.status),
                             detail: tr("Công cụ chống malware của Apple ghi kết quả khác “không có mối đe dọa”. Xem chi tiết bằng lệnh ‘xprotect logs’.") + why,
                             path: nil, source: .system, code: "xprotect.detection", subject: "\(d.plugin)|\(d.status)"))
        }
        if let age = info.updateAgeDays(now: now), age > XProtectInfo.staleAfterDays {
            out.append(.init(severity: .low, title: trf("XProtect chưa cập nhật %@ ngày", "\(age)"),
                             detail: tr("Cơ sở dữ liệu của Apple thường cập nhật vài tuần một lần. Kiểm tra Cài đặt hệ thống → Cập nhật phần mềm."),
                             path: nil, source: .system, code: "xprotect.stale"))
        }
        return out
    }

    // MARK: Chạy thật

    public static func run(days: Int = 7) async -> XProtectInfo {
        async let status = ProcessRunner.run(["xprotect", "status"], timeout: 15)
        async let version = ProcessRunner.run(["xprotect", "version"], timeout: 15)   // "Version: 5372 Installed: …" nằm ở lệnh này, không phải `status`
        async let log = ProcessRunner.run(["log", "show", "--last", "\(days)d", "--style", "compact", "--predicate", predicate], timeout: 90)
        let (s, v, l) = await (status, version, log)
        let st = parseStatus(s.stdout + "\n" + v.stdout)
        var info = XProtectInfo(version: st.version, installed: st.installed, launchScans: st.launch, backgroundScans: st.background)
        if l.ok {
            let sum = summarize(parseEvents(l.stdout))
            info.modulesRun = sum.modules; info.lastScan = sum.last; info.detections = sum.detections
        }
        return info
    }
}
