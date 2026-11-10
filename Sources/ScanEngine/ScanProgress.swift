import Foundation

public struct ScanSnapshot: Sendable {
    public var files = 0
    public var bytes: Int64 = 0
    public var current = ""
    public init() {}
}

/// Bộ đếm tiến độ dùng chung giữa nhiều luồng quét. Cộng dồn theo lô để tránh tranh chấp khóa.
public final class ScanProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var files = 0
    private var bytes: Int64 = 0
    private var current = ""

    public init() {}

    public func add(files f: Int, bytes b: Int64) { lock.lock(); files += f; bytes += b; lock.unlock() }
    public func setCurrent(_ p: String) { lock.lock(); current = p; lock.unlock() }

    public var snapshot: ScanSnapshot {
        lock.lock(); defer { lock.unlock() }
        var s = ScanSnapshot(); s.files = files; s.bytes = bytes; s.current = current
        return s
    }
}
