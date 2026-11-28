import Foundation
import CoreKit

/// Phát hiện pin đang tụt nhanh (giống cảnh báo "Your battery is draining faster" của macOS):
/// đang dùng pin, thời lượng còn lại thấp và có app ngốn CPU.
public enum BatteryDrain {
    public struct Consumer: Sendable, Hashable { public let name: String; public let cpu: Double }

    /// Ngưỡng: còn ≤ 45 phút và app nặng nhất ≥ 25% một nhân.
    public static let maxMinutes = 45
    public static let minCPU = 25.0

    /// Pin chỉ đáng báo khi đang xả, ước tính còn ít phút.
    public static func isLow(_ b: BatteryInfo?) -> Bool {
        guard let b, !b.pluggedIn, !b.charging, let m = b.minutesRemaining else { return false }
        return m <= maxMinutes
    }

    /// Có đủ lý do để báo: pin xả nhanh và có ít nhất một app ngốn CPU.
    public static func shouldAlert(_ b: BatteryInfo?, consumers: [Consumer]) -> Bool {
        isLow(b) && (consumers.first?.cpu ?? 0) >= minCPU
    }

    /// `ps -Ax -o pcpu=,comm=` → gộp theo app (tiến trình trong cùng .app cộng dồn), nặng nhất trước.
    public static func parse(_ output: String, limit: Int = 3) -> [Consumer] {
        var byApp: [String: Double] = [:]
        for line in output.split(separator: "\n") {
            let p = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard p.count == 2, let cpu = Double(p[0]), cpu > 0 else { continue }
            let path = String(p[1]).trimmingCharacters(in: .whitespaces)
            let name: String
            if let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app") : nil) {
                // Lấy app ngoài cùng: "/Applications/Foo.app/Contents/…/Foo Helper" → "Foo".
                name = String(path[..<r.lowerBound]).split(separator: "/").last.map(String.init) ?? path
            } else {
                let last = path.split(separator: "/").last.map(String.init) ?? path
                if ["kernel_task", "WindowServer", "ps", "mds", "mds_stores", "mdworker_shared"].contains(last) { continue }
                name = last
            }
            byApp[name, default: 0] += cpu
        }
        return byApp.map { Consumer(name: $0.key, cpu: $0.value) }.sorted { $0.cpu > $1.cpu }.prefix(limit).map { $0 }
    }

    public static func topConsumers(limit: Int = 3) async -> [Consumer] {
        let r = await ProcessRunner.run(["ps", "-Ax", "-o", "pcpu=,comm="])
        guard r.ok else { return [] }
        return parse(r.stdout, limit: limit)
    }
}
