import Foundation
import CoreKit
import ScanEngine

/// Ổ đĩa đang chứa gì: chia theo loại dữ liệu người dùng quen thuộc, đo từ các thư mục chuẩn của macOS.
/// Đây là ước lượng theo thư mục (không đọc metadata Spotlight); phần không thuộc loại nào được gộp vào "Khác".
public enum DiskBreakdown {
    public enum Kind: String, CaseIterable, Sendable { case audio, applications, images, documents, movies }

    public static func folders(_ kind: Kind, home: String = NSHomeDirectory()) -> [String] {
        switch kind {
        case .audio: return [home + "/Music"]
        case .applications: return ["/Applications", home + "/Applications"]
        case .images: return [home + "/Pictures"]
        case .documents: return [home + "/Documents", home + "/Desktop", home + "/Downloads"]
        case .movies: return [home + "/Movies"]
        }
    }

    /// Dung lượng từng loại (byte). Chạy song song, có thể mất vài giây trên máy nhiều file.
    public static func measure() async -> [Kind: Int64] {
        await withTaskGroup(of: (Kind, Int64).self) { group in
            for k in Kind.allCases {
                group.addTask { (k, folders(k).reduce(Int64(0)) { $0 + FileWalker.allocatedSize(of: URL(fileURLWithPath: $1)) }) }
            }
            var out: [Kind: Int64] = [:]
            for await (k, v) in group { out[k] = v }
            return out
        }
    }

    public static func trashSize() async -> Int64 {
        await Task.detached { FileWalker.allocatedSize(of: URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")) }.value
    }

    /// Tình trạng SMART của ổ khởi động theo `diskutil info /`: true = Verified, false = Failing, nil = không có (vd. ổ ngoài/ảo hóa).
    public static func parseSMART(_ diskutilOutput: String) -> Bool? {
        for line in diskutilOutput.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("SMART Status:") else { continue }
            let v = t.dropFirst("SMART Status:".count).trimmingCharacters(in: .whitespaces).lowercased()
            if v == "verified" { return true }
            if v == "failing" || v.contains("fail") { return false }
            return nil
        }
        return nil
    }

    public static func smartVerified() async -> Bool? {
        parseSMART(await ProcessRunner.run(["diskutil", "info", "/"], timeout: 10).stdout)
    }
}
