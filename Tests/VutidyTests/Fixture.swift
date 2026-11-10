import Foundation

/// Cây thư mục giả trong temp dir.
struct Fixture {
    let root: URL
    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vutidy-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    @discardableResult
    func file(_ rel: String, bytes: Int = 10_000, fill: UInt8 = 0x41) -> URL {
        let u = root.appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(repeating: fill, count: bytes).write(to: u)
        return u
    }
    func dir(_ rel: String) -> URL {
        let u = root.appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
