import Foundation
import CoreKit

/// Một app/helper đăng ký mở khi đăng nhập, theo Background Task Management của macOS (mục "Login Items" trong System Settings).
public struct LoginItemEntry: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable { case app, helper }
    public var id: String { "\(kind.rawValue)|\(identifier)|\(path ?? name)" }
    public let name: String
    public let developer: String?
    public let kind: Kind
    /// true = được phép mở khi đăng nhập (công tắc đang bật trong System Settings).
    public let enabled: Bool
    public let identifier: String
    /// Đường dẫn app (đã đổi `*` thành home); nil nếu bản ghi chỉ có đường dẫn tương đối (helper trong app).
    public let path: String?
    /// App không còn ở chỗ đó (đã xóa, đang trong Thùng rác, hay chạy từ thư mục tạm của Gatekeeper).
    public let orphaned: Bool
}

/// Đọc danh sách "mở khi đăng nhập" từ kho Background Task Management của macOS.
///
/// Không dùng `sfltool dumpbtm`: lệnh đó đòi quyền quản trị và làm macOS hiện hộp thoại mật khẩu mỗi lần chạy.
/// Thay vào đó đọc thẳng file `/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*-<UUID>.btm` của user (ai cũng đọc được,
/// chỉ đọc, không cần quyền gì). Đây là NSKeyedArchiver nên giải mã tay theo `$objects`.
public enum LoginItems {
    static let storeDir = "/private/var/db/com.apple.backgroundtaskmanagement"

    /// File của user hiện tại: `BackgroundItems-v<N>-<UUID>.btm`, UUID là GeneratedUID của tài khoản (mỗi tài khoản một file).
    /// Không khớp được thì lấy file có phiên bản lớn nhất, mới nhất (file `-v<N>.btm` không UUID là bản cũ).
    static func storeFile(userUUID: String?) -> URL? {
        let dir = URL(fileURLWithPath: storeDir)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: storeDir)) ?? []
        let cands = names.compactMap { n -> (v: Int, name: String)? in
            guard n.hasPrefix("BackgroundItems-v"), n.hasSuffix(".btm"), n.filter({ $0 == "-" }).count >= 2 else { return nil }
            let v = n.dropFirst("BackgroundItems-v".count).prefix { $0.isNumber }
            return Int(v).map { ($0, n) }
        }
        if let u = userUUID?.uppercased(), let m = cands.filter({ $0.name.uppercased().contains(u) }).max(by: { $0.v < $1.v }) {
            return dir.appendingPathComponent(m.name)
        }
        func mtime(_ n: String) -> Date { (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(n).path)[.modificationDate] as? Date) ?? .distantPast }
        return cands.max { ($0.v, mtime($0.name)) < ($1.v, mtime($1.name)) }.map { dir.appendingPathComponent($0.name) }
    }

    static func currentUserUUID() async -> String? {
        let r = await ProcessRunner.run(["dscl", ".", "-read", "/Users/" + NSUserName(), "GeneratedUID"], timeout: 10)
        return r.stdout.split(whereSeparator: { $0 == " " || $0 == "\n" }).last.map(String.init)
    }

    public static func list() async -> [LoginItemEntry] {
        guard let file = storeFile(userUUID: await currentUserUUID()) else { return [] }
        // plutil đổi plist nhị phân sang XML, trong đó tham chiếu UID là {"CF$UID": n} — dễ đọc bằng PropertyListSerialization.
        // Ghi ra file tạm rồi đọc: đầu ra qua pipe của ProcessRunner bị cắt khi dài (XML ~150 KB).
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("vutidy-btm-\(UUID().uuidString).xml")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let r = await ProcessRunner.run(["plutil", "-convert", "xml1", "-o", tmp.path, file.path], timeout: 20)
        guard r.ok, let data = try? Data(contentsOf: tmp) else { return [] }
        return parse(plistData: data)
    }

    public static func parse(plistData: Data, home: String = NSHomeDirectory(),
                             exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [LoginItemEntry] {
        guard let root = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any],
              let objs = root["$objects"] as? [Any] else { return [] }

        // Foundation đọc {CF$UID: n} thành kiểu CFKeyedArchiverUID (không phải dict); lấy n từ phần mô tả "…{value = n}".
        func uid(_ v: Any?) -> Int? {
            if let n = (v as? [String: Any])?["CF$UID"] as? Int { return n }
            guard let v, !(v is String), !(v is NSNumber) else { return nil }
            let d = String(describing: v)
            guard d.contains("UID"), let r = d.range(of: "value = ") else { return nil }
            return Int(d[r.upperBound...].prefix { $0.isNumber })
        }
        func deref(_ v: Any?) -> Any? { guard let i = uid(v), i > 0, i < objs.count else { return nil }; return objs[i] }
        func string(_ v: Any?) -> String? {
            switch deref(v) {
            case let s as String: return s.isEmpty ? nil : s
            case let d as [String: Any]: return string(d["NS.relative"])        // NSURL: lấy phần đường dẫn
            default: return nil
            }
        }
        func int(_ v: Any?) -> Int { (v as? Int) ?? 0 }

        // Gốc của kho: dict có khóa "records" (mảng ItemRecord).
        guard let store = objs.compactMap({ $0 as? [String: Any] }).first(where: { $0["records"] != nil }),
              let arr = deref(store["records"]) as? [String: Any], let items = arr["NS.objects"] as? [Any] else { return [] }

        var seen = Set<String>(), out: [LoginItemEntry] = []
        for ref in items {
            guard let r = deref(ref) as? [String: Any] else { continue }
            let type = int(r["type"])
            let kind: LoginItemEntry.Kind
            if type == 0x2 { kind = .app } else if type == 0x4 { kind = .helper } else { continue }
            guard let name = string(r["name"]) else { continue }
            var path: String? = nil
            if let u = string(r["url"]) {
                var p = u.hasPrefix("file://") ? (URL(string: u)?.path ?? String(u.dropFirst(7))) : u
                p = p.replacingOccurrences(of: "/Users/*/", with: home + "/")
                while p.count > 1, p.hasSuffix("/") { p.removeLast() }
                if p.hasPrefix("/") { path = p }
            }
            let enabled = int(r["disposition"]) & 0x1 != 0
            let orphaned = path.map { p in !exists(p) || p.contains("/.Trash/") || p.contains("/AppTranslocation/") } ?? false
            let e = LoginItemEntry(name: name, developer: string(r["developerName"]), kind: kind, enabled: enabled,
                                   identifier: string(r["identifier"]) ?? name, path: path, orphaned: orphaned)
            // Cùng một app thường được ghi nhiều lần (mỗi lần đăng ký): giữ một dòng, ưu tiên dòng đang bật.
            let key = "\(kind.rawValue)|\(path ?? name)"
            if seen.insert(key).inserted { out.append(e) }
            else if enabled, let i = out.firstIndex(where: { "\($0.kind.rawValue)|\($0.path ?? $0.name)" == key }), !out[i].enabled { out[i] = e }
        }
        return out.sorted { ($0.enabled ? 0 : 1, $0.name.lowercased()) < ($1.enabled ? 0 : 1, $1.name.lowercased()) }
    }

    /// Mở System Settings → General → Login Items (nơi macOS cho bật/tắt các mục này).
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Extension")!
}
