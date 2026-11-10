import Foundation
import Darwin

public enum Glob {
    /// Mở rộng pattern (hỗ trợ `~`, `*`, `?`, `{a,b}`) thành danh sách URL tồn tại.
    public static func expand(_ pattern: String) -> [URL] {
        var g = glob_t()
        defer { globfree(&g) }
        guard glob(pattern, GLOB_TILDE | GLOB_BRACE | GLOB_NOSORT, nil, &g) == 0 else { return [] }
        var out: [URL] = []
        for i in 0..<Int(g.gl_pathc) {
            if let p = g.gl_pathv[i] { out.append(URL(fileURLWithPath: String(cString: p))) }
        }
        return out
    }

    /// So khớp một đường dẫn với pattern kiểu fnmatch (không coi `/` đặc biệt).
    public static func matches(_ pattern: String, path: String) -> Bool {
        fnmatch(expandHome(pattern), path, 0) == 0
    }

    private static func expandHome(_ s: String) -> String {
        s.hasPrefix("~") ? NSHomeDirectory() + s.dropFirst() : s
    }
}
