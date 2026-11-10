import Foundation
import IOKit
import IOKit.ps
import Darwin

public struct DiskInfo: Sendable {
    public var total: Int64, available: Int64, availableImportant: Int64
    public var purgeable: Int64 { max(0, availableImportant - available) }
    public var freeFraction: Double { total > 0 ? Double(availableImportant) / Double(total) : 0 }
}
public struct MemoryInfo: Sendable {
    public var total: Int64, available: Int64, swapUsed: Int64, pressure: Pressure
    public enum Pressure: String, Sendable { case normal, warning, critical }
}
public struct BatteryInfo: Sendable {
    public var percent: Int, charging: Bool, cycleCount: Int?, health: Double?
}
public struct NetworkRate: Sendable { public var downBytesPerSec: Double, upBytesPerSec: Double }

public struct SystemSnapshot: Sendable {
    public var disk: DiskInfo
    public var memory: MemoryInfo
    public var cpuLoad: Double
    public var cpuTemp: Double? = nil           // °C, nil nếu không đọc được
    public var thermal: ProcessInfo.ThermalState = .nominal
    public var battery: BatteryInfo?
    public var network: NetworkRate
    public var date = Date()
}

/// Lấy số liệu hệ thống. Giữ trạng thái giữa các lần gọi để tính delta CPU/mạng.
public final class SystemMonitor: @unchecked Sendable {
    private var lastCPU: host_cpu_load_info?
    private var lastNet: (rx: UInt64, tx: UInt64, t: Date)?
    private let lock = NSLock()

    public init() {}

    public func sample() -> SystemSnapshot {
        lock.lock(); defer { lock.unlock() }
        return SystemSnapshot(disk: Self.disk(), memory: Self.memory(), cpuLoad: cpu(), cpuTemp: CPUTemperature.celsius(), thermal: ProcessInfo.processInfo.thermalState,
                              battery: Self.battery(), network: network())
    }

    public static func disk(path: String = "/") -> DiskInfo {
        let u = URL(fileURLWithPath: path)
        let v = try? u.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                                .volumeAvailableCapacityForImportantUsageKey])
        return DiskInfo(total: Int64(v?.volumeTotalCapacity ?? 0), available: Int64(v?.volumeAvailableCapacity ?? 0),
                        availableImportant: v?.volumeAvailableCapacityForImportantUsage ?? Int64(v?.volumeAvailableCapacity ?? 0))
    }

    public static func memory() -> MemoryInfo {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        let page = Int64(vm_kernel_page_size)
        let free = kr == KERN_SUCCESS ? Int64(stats.free_count + stats.inactive_count + stats.purgeable_count + stats.speculative_count) * page : 0
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        var level: Int32 = 1
        var lsize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0)
        let p: MemoryInfo.Pressure = level >= 4 ? .critical : (level >= 2 ? .warning : .normal)
        return MemoryInfo(total: Int64(ProcessInfo.processInfo.physicalMemory), available: free, swapUsed: Int64(swap.xsu_used), pressure: p)
    }

    private func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        defer { lastCPU = info }
        guard let l = lastCPU else { return 0 }
        func d(_ a: UInt32, _ b: UInt32) -> Double { Double(a &- b) }
        let user = d(info.cpu_ticks.0, l.cpu_ticks.0), sys = d(info.cpu_ticks.1, l.cpu_ticks.1)
        let idle = d(info.cpu_ticks.2, l.cpu_ticks.2), nice = d(info.cpu_ticks.3, l.cpu_ticks.3)
        let total = user + sys + idle + nice
        return total > 0 ? (user + sys + nice) / total : 0
    }

    public static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let src = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String: Any],
              let cur = desc[kIOPSCurrentCapacityKey] as? Int else { return nil }
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        var cycles: Int?, health: Double?
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if svc != 0 {
            defer { IOObjectRelease(svc) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] {
                cycles = d["CycleCount"] as? Int
                if let mx = (d["AppleRawMaxCapacity"] as? Int) ?? (d["MaxCapacity"] as? Int),
                   let design = d["DesignCapacity"] as? Int, design > 0, mx > 100 { health = Double(mx) / Double(design) }
            }
        }
        return BatteryInfo(percent: cur, charging: charging, cycleCount: cycles, health: health)
    }

    private func network() -> NetworkRate {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return NetworkRate(downBytesPerSec: 0, upBytesPerSec: 0) }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let name = String(cString: p.pointee.ifa_name)
            guard name.hasPrefix("en"), let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_LINK),
                  let data = p.pointee.ifa_data else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
        }
        let now = Date()
        defer { lastNet = (rx, tx, now) }
        guard let l = lastNet else { return NetworkRate(downBytesPerSec: 0, upBytesPerSec: 0) }
        let dt = max(0.001, now.timeIntervalSince(l.t))
        // ifi_*bytes là 32-bit nên có thể tràn; trừ có wrap.
        func delta(_ a: UInt64, _ b: UInt64) -> Double { a >= b ? Double(a - b) : Double((a &+ (1 << 32)) &- b) }
        return NetworkRate(downBytesPerSec: delta(rx, l.rx) / dt, upBytesPerSec: delta(tx, l.tx) / dt)
    }

    /// Wi-Fi SSID cần quyền Location; giữ ở đây dạng best-effort qua networksetup.
    public static func wifiName() async -> String? {
        let r = await ProcessRunner.run(["networksetup", "-getairportnetwork", "en0"])
        guard r.ok, let range = r.stdout.range(of: "Network: ") else { return nil }
        return r.stdout[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

import CoreKit
