import Foundation
import CoreKit

public struct SpeedResult: Codable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let downMbps: Double
    public let upMbps: Double
    public let responsivenessRPM: Int?
}

public enum SpeedTest {
    /// Chạy `networkQuality -c` (macOS 12+). Không tự chạy định kỳ vì tốn băng thông.
    public static func run() async -> SpeedResult? {
        let r = await ProcessRunner.run(["networkQuality", "-c"], timeout: 120)
        guard r.ok, let j = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any] else { return nil }
        let dl = (j["dl_throughput"] as? Double) ?? Double(j["dl_throughput"] as? Int ?? 0)
        let ul = (j["ul_throughput"] as? Double) ?? Double(j["ul_throughput"] as? Int ?? 0)
        return SpeedResult(date: Date(), downMbps: dl / 1e6, upMbps: ul / 1e6, responsivenessRPM: j["responsiveness"] as? Int)
    }

    public static func history(paths: AppPaths = .default) -> [SpeedResult] {
        guard let d = try? Data(contentsOf: paths.speedHistory) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([SpeedResult].self, from: d)) ?? []
    }

    public static func append(_ r: SpeedResult, paths: AppPaths = .default, keep: Int = 20) {
        var h = history(paths: paths); h.append(r); h = Array(h.suffix(keep))
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
        try? e.encode(h).write(to: paths.speedHistory, options: .atomic)
    }
}

public struct BluetoothDevice: Identifiable, Sendable { public var id: String { name }; public let name: String; public let batteryPercent: Int }

public enum ConnectedDevices {
    /// Pin thiết bị Bluetooth qua system_profiler (chậm — chỉ gọi khi cần, nên cache).
    public static func bluetooth() async -> [BluetoothDevice] {
        let r = await ProcessRunner.run(["system_profiler", "SPBluetoothDataType", "-json"], timeout: 30)
        guard r.ok, let j = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any],
              let root = (j["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: Any]] else { return [] }
        return connected.flatMap { dict in
            dict.compactMap { (name, v) -> BluetoothDevice? in
                guard let p = v as? [String: Any] else { return nil }
                let raw = (p["device_batteryLevelMain"] as? String) ?? (p["device_batteryLevel"] as? String)
                guard let s = raw?.replacingOccurrences(of: "%", with: ""), let n = Int(s) else { return nil }
                return BluetoothDevice(name: name, batteryPercent: n)
            }
        }
    }
}
