import Foundation
import IOKit

// API HID không công khai nhưng IOKit vẫn xuất symbol (các app giám sát hệ thống dùng chung cách này).
// Đọc cảm biến nhiệt PMU trên Apple Silicon, không cần quyền root.
@_silgen_name("IOHIDEventSystemClientCreate") private func hidClientCreate(_ allocator: CFAllocator?) -> UnsafeMutableRawPointer?
@_silgen_name("IOHIDEventSystemClientSetMatching") private func hidSetMatching(_ client: UnsafeMutableRawPointer, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") private func hidCopyServices(_ client: UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent") private func hidCopyEvent(_ service: UnsafeMutableRawPointer, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> UnsafeMutableRawPointer?
@_silgen_name("IOHIDServiceClientCopyProperty") private func hidCopyProperty(_ service: UnsafeMutableRawPointer, _ key: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") private func hidFloatValue(_ event: UnsafeMutableRawPointer, _ field: Int32) -> Double

public enum CPUTemperature {
    private static let kTemperatureEvent: Int64 = 15
    private static let client: UnsafeMutableRawPointer? = {
        guard let c = hidClientCreate(kCFAllocatorDefault) else { return nil }
        // Usage page 0xFF00 / usage 5 = cảm biến nhiệt của Apple.
        _ = hidSetMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        return c
    }()

    /// Nhiệt độ CPU (°C): Apple Silicon đọc cảm biến PMU tdie, Mac Intel đọc cảm biến lõi qua SMC. nil nếu không đọc được.
    public static func celsius() -> Double? { hidCelsius() ?? IntelSMC.cpuCelsius() }

    private static func hidCelsius() -> Double? {
        guard let client, let arr = hidCopyServices(client)?.takeRetainedValue() else { return nil }
        var best: Double?
        for i in 0..<CFArrayGetCount(arr) {
            guard let raw = CFArrayGetValueAtIndex(arr, i) else { continue }
            let service = UnsafeMutableRawPointer(mutating: raw)
            guard let name = hidCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String,
                  name.lowercased().contains("tdie"),
                  let event = hidCopyEvent(service, kTemperatureEvent, 0, 0) else { continue }
            let t = hidFloatValue(event, Int32(kTemperatureEvent << 16))
            Unmanaged<AnyObject>.fromOpaque(event).release()
            if t > 0 && t < 150 { best = max(best ?? 0, t) }
        }
        return best
    }
}

/// Đọc cảm biến nhiệt của Mac Intel qua AppleSMC (IOKit, không cần quyền root).
enum IntelSMC {
    private struct Version { var a: UInt8 = 0, b: UInt8 = 0, c: UInt8 = 0, d: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    /// 12 byte như bản C (có đệm cuối); thiếu đệm thì cả cấu trúc chỉ 76 byte và SMC từ chối.
    private struct KeyInfo { var size: UInt32 = 0, type: UInt32 = 0, attr: UInt8 = 0, p1: UInt8 = 0, p2: UInt8 = 0, p3: UInt8 = 0 }
    private typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                               UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct KeyData {
        var key: UInt32 = 0
        var vers = Version()
        var pLimit = PLimit()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static let connection: io_connect_t? = {
        guard MemoryLayout<KeyData>.size == 80 else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var conn: io_connect_t = 0
        return IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS ? conn : nil
    }()
    private static let lock = NSLock()

    private static func call(_ input: inout KeyData, _ conn: io_connect_t) -> KeyData? {
        var out = KeyData(); var size = MemoryLayout<KeyData>.size
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.size, &out, &size)   // 2 = kSMCHandleYPCEvent
        return r == KERN_SUCCESS && out.result == 0 ? out : nil
    }

    static func read(_ key: String) -> Double? {
        guard let conn = connection else { return nil }
        lock.lock(); defer { lock.unlock() }
        var q = KeyData(); q.key = fourCC(key); q.command = 9                                        // 9 = đọc thông tin khóa
        guard let info = call(&q, conn) else { return nil }
        var r = KeyData(); r.key = fourCC(key); r.info.size = info.info.size; r.command = 5          // 5 = đọc giá trị
        guard let out = call(&r, conn) else { return nil }
        let b = withUnsafeBytes(of: out.bytes) { Array($0) }
        switch info.info.type {
        case fourCC("sp78"): return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case fourCC("flt "): return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        default: return nil
        }
    }

    /// Lõi nóng nhất (TC1C…TC8C); không có thì cảm biến gói CPU (TCXC, TC0P, TC0D).
    static func cpuCelsius() -> Double? {
        func valid(_ v: Double?) -> Double? { v.flatMap { $0 > 0 && $0 < 150 ? $0 : nil } }
        let cores = (1...8).compactMap { valid(read("TC\($0)C")) }
        if let hot = cores.max() { return hot }
        return ["TCXC", "TC0P", "TC0D", "TC0E"].lazy.compactMap { valid(read($0)) }.first
    }
}
