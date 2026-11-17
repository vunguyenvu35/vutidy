import Foundation
import CoreKit

/// Giảm nhiệt cho Mac Intel bằng cách hạ Turbo Boost.
///
/// macOS không có API chính thức để tắt Turbo Boost, nên có hai đường:
/// - **Chế độ Tiết kiệm điện** (`pmset lowpowermode`): hợp lệ, không cần hạ SIP; macOS tự giảm xung nhịp/turbo.
/// - **Kext của Turbo Boost Switcher** (`DisableTurboBoost.kext`): tắt turbo thật, nhưng phải do người dùng tự cài
///   (Vutidy không đóng gói kext bên thứ ba) và cần Reduced Security. Ở đây chỉ nạp/gỡ kext đã có sẵn trên máy.
public enum TurboBoost {
    public struct Status: Sendable, Equatable {
        public var isIntel: Bool
        /// `nil` = máy không hỗ trợ Low Power Mode (vd. Mac mini/iMac Intel, macOS cũ).
        public var lowPowerMode: Bool?
        public var kextPath: String?
        public var kextLoaded: Bool
        /// Turbo đang bị hạ bằng ít nhất một cách.
        public var turboLimited: Bool { kextLoaded || lowPowerMode == true }
    }

    public static let kextBundleHint = "DisableTurboBoost"

    // MARK: Phát hiện

    public static var isIntel: Bool {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0) == 0 else { return false }
        return String(cString: buf).contains("Intel")
    }

    /// Đọc dòng `lowpowermode N` trong `pmset -g`. Không có dòng này = không hỗ trợ.
    public static func parseLowPowerMode(_ pmsetOutput: String) -> Bool? {
        for line in pmsetOutput.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[0] == "lowpowermode" { return parts[1] == "1" }
        }
        return nil
    }

    public static func isKextLoaded(_ kextstatOutput: String) -> Bool {
        kextstatOutput.split(separator: "\n").contains { $0.contains(kextBundleHint) }
    }

    /// Kext có sẵn trên máy (từ Turbo Boost Switcher hoặc cài thủ công), ưu tiên bản 64-bit.
    public static func findKext(fileManager fm: FileManager = .default,
                                roots: [String] = ["/Applications/Turbo Boost Switcher.app/Contents/Resources", "/Library/Extensions"]) -> String? {
        var found: [String] = []
        for root in roots {
            let names = (try? fm.contentsOfDirectory(atPath: root)) ?? []
            found += names.filter { $0.hasPrefix(kextBundleHint) && $0.hasSuffix(".kext") }.map { root + "/" + $0 }
        }
        return found.sorted { ($0.contains("64bits") ? 0 : 1, $0) < ($1.contains("64bits") ? 0 : 1, $1) }.first
    }

    public static func status() async -> Status {
        let intel = isIntel
        guard intel else { return Status(isIntel: false, lowPowerMode: nil, kextPath: nil, kextLoaded: false) }
        async let pm = ProcessRunner.run(["pmset", "-g"])
        async let ks = ProcessRunner.run(["kextstat", "-l"])
        let (p, k) = await (pm, ks)
        return Status(isIntel: true, lowPowerMode: parseLowPowerMode(p.stdout), kextPath: findKext(), kextLoaded: isKextLoaded(k.stdout))
    }

    // MARK: Thao tác (cần admin)

    public static func setLowPowerMode(_ on: Bool) async -> ProcessResult {
        await ProcessRunner.runPrivileged(shell: "/usr/bin/pmset -a lowpowermode \(on ? 1 : 0)")
    }

    public static func setKextLoaded(_ on: Bool, path: String) async -> ProcessResult {
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return await ProcessRunner.runPrivileged(shell: "\(on ? "/sbin/kextload" : "/sbin/kextunload") \(quoted)")
    }
}
