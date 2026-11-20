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

public struct BluetoothDevice: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let batteryPercent: Int?
    /// Loại thiết bị theo macOS ("Mouse", "Keyboard", "Headphones"…); rỗng nếu không rõ.
    public let kind: String
    public init(name: String, batteryPercent: Int?, kind: String = "") { self.name = name; self.batteryPercent = batteryPercent; self.kind = kind }
}

public enum ConnectedDevices {
    /// Pin thiết bị Bluetooth qua system_profiler (chậm — chỉ gọi khi cần, nên cache).
    public static func bluetooth() async -> [BluetoothDevice] {
        let r = await ProcessRunner.run(["system_profiler", "SPBluetoothDataType", "-json"], timeout: 30)
        guard r.ok, let j = try? JSONSerialization.jsonObject(with: Data(r.stdout.utf8)) as? [String: Any],
              let root = (j["SPBluetoothDataType"] as? [[String: Any]])?.first else { return [] }
        let connected = (root["device_connected"] as? [[String: Any]]) ?? []
        let nearby = nearbyAppleDevices(root["device_not_connected"] as? [[String: Any]] ?? [])
        // Liệt kê mọi thiết bị đang kết nối. system_profiler chỉ báo pin của AirPods, bàn phím/chuột Apple…; chuột, bàn phím
        // Logitech và nhiều phụ kiện khác báo pin qua nguồn điện của macOS (IOKit) nên ghép thêm từ đó. Thiếu cả hai thì để nil.
        func pct(_ v: Any?) -> Int? { (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
        let extra = await accessoryBatteries()
        return merge(connected.flatMap { dict in
            dict.compactMap { (name, v) -> BluetoothDevice? in
                guard let p = v as? [String: Any] else { return nil }
                let sides = [pct(p["device_batteryLevelLeft"]), pct(p["device_batteryLevelRight"])].compactMap { $0 }
                let battery = pct(p["device_batteryLevelMain"]) ?? pct(p["device_batteryLevel"]) ?? sides.min()
                return BluetoothDevice(name: name, batteryPercent: battery, kind: (p["device_minorType"] as? String) ?? "")
            }
        } + nearby, with: extra).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Pin của phụ kiện (chuột, bàn phím, tay cầm…) do macOS báo như một nguồn điện: tên → phần trăm.
    /// IOKit công khai chỉ liệt kê pin trong máy nên đọc `pmset -g accps` (chạy tức thì, không cần quyền đặc biệt).
    static func accessoryBatteries() async -> [String: Int] {
        let r = await ProcessRunner.run(["pmset", "-g", "accps"], timeout: 10)
        return r.ok ? parseAccps(r.stdout) : [:]
    }

    /// Mỗi dòng có dạng ` -MX Anywhere 3S (id=50336671)\t85%; discharging; ...`. Bỏ pin trong máy (`InternalBattery-0`).
    static func parseAccps(_ out: String) -> [String: Int] {
        var res: [String: Int] = [:]
        for raw in out.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("-"), let idRange = line.range(of: " (id=") else { continue }
            let name = String(line[line.index(after: line.startIndex)..<idRange.lowerBound])
            guard !name.hasPrefix("InternalBattery"), !name.isEmpty,
                  let pctEnd = line.range(of: "%", range: idRange.upperBound..<line.endIndex) else { continue }
            let digits = line[idRange.upperBound..<pctEnd.lowerBound].reversed().prefix { $0.isNumber }.reversed()
            if let v = Int(String(digits)), (0...100).contains(v) { res[name] = v }
        }
        return res
    }

    /// Điền pin còn thiếu theo tên thiết bị (không phân biệt hoa thường). Không ghi đè pin đã có.
    static func merge(_ devices: [BluetoothDevice], with batteries: [String: Int]) -> [BluetoothDevice] {
        let byName = Dictionary(batteries.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        return devices.map { d in
            guard d.batteryPercent == nil, let b = byName[d.name.lowercased()] else { return d }
            return BluetoothDevice(name: d.name, batteryPercent: b, kind: d.kind)
        }
    }

    /// iPhone/iPad/Apple Watch đã ghép đôi và đang ở gần (có `device_rssi`) được tính là đang kết nối qua Continuity,
    /// dù Bluetooth báo "chưa kết nối". macOS không cho đọc pin của chúng bằng API công khai nên không có phần trăm pin.
    static func nearbyAppleDevices(_ notConnected: [[String: Any]]) -> [BluetoothDevice] {
        notConnected.flatMap { dict in
            dict.compactMap { (name, v) -> BluetoothDevice? in
                guard let p = v as? [String: Any], p["device_rssi"] != nil else { return nil }
                let n = name.lowercased()
                let kind = n.contains("iphone") ? "iPhone" : (n.contains("ipad") ? "iPad" : (n.contains("watch") ? "Watch" : ""))
                return kind.isEmpty ? nil : BluetoothDevice(name: name, batteryPercent: nil, kind: kind)
            }
        }
    }
}
