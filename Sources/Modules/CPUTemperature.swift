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

    /// Nhiệt độ CPU (°C) = giá trị cao nhất của các cảm biến die (PMU tdie). nil nếu máy không có (vd. Intel).
    public static func celsius() -> Double? {
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
