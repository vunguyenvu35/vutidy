import SwiftUI
import CoreKit
import Modules

/// Năm nhóm của Smart Care: Dọn dẹp · Bảo vệ · Hiệu năng · Ứng dụng · File lớn & cũ.
/// Mỗi nhóm có một dòng tóm tắt và trạng thái (chưa quét / ổn / cần chú ý) để dải thẻ ở Smart Scan hiển thị kết quả.
/// Chỉ nhóm Dọn dẹp có nút Dọn; các nhóm còn lại chỉ báo cáo, không tự làm gì.
@MainActor
struct CareGroups {
    let state: AppState

    enum Status { case pending, ok, attention }
    struct Group: Identifiable {
        let id: String
        let page: Page
        let title: String
        let summary: String
        let status: Status
        var review: Page
    }

    var scanned: Bool { state.smart != nil }

    var groups: [Group] {
        [cleanup, protection, performance, applications, clutter]
    }

    // MARK: Từng nhóm

    var cleanup: Group {
        let safe = state.smart?.cleanableBytes ?? 0, review = state.smart?.reviewBytes ?? 0
        let s: String, st: Status
        if !scanned { s = tr("Chưa quét"); st = .pending }
        else if safe == 0 && review == 0 { s = tr("Không có gì cần dọn"); st = .ok }
        else { s = trf("%@ an toàn để dọn · %@ cần xem lại", ByteFormat.string(safe), ByteFormat.string(review)); st = safe > 0 ? .attention : .ok }
        return Group(id: "cleanup", page: .systemJunk, title: tr("Dọn dẹp"), summary: s, status: st, review: .systemJunk)
    }

    var protection: Group {
        let unsigned = state.smart?.suspiciousCount ?? 0
        var s: String, st: Status
        if !scanned { s = tr("Chưa quét"); st = .pending }
        else if let r = state.malwareReport {
            let n = r.findings.count
            if n == 0 && r.postureIssues == 0 { s = tr("Không thấy dấu hiệu đáng ngờ"); st = .ok }
            else if n == 0 { s = trf("%@ cài đặt bảo mật nên bật", "\(r.postureIssues)"); st = .attention }
            else { s = trf("%@ phát hiện cần xem", "\(n)"); st = .attention }
            if unsigned > 0 { s += " · " + trf("%@ launch item chưa ký", "\(unsigned)") }
        } else {
            s = state.malwareScanning ? tr("Đang kiểm tra malware…") : tr("Chưa kiểm tra malware"); st = .pending
        }
        return Group(id: "protection", page: .protection, title: tr("Bảo vệ"), summary: s, status: st, review: state.malwareReport == nil ? .protection : .malware)
    }

    var performance: Group {
        guard scanned else { return Group(id: "performance", page: .optimization, title: tr("Hiệu năng"), summary: tr("Chưa quét"), status: .pending, review: .optimization) }
        var parts: [String] = []
        if let m = state.snapshot?.memory { parts.append(ByteFormat.string(m.available) + tr(" khả dụng")) }
        let on = state.care?.loginOn ?? 0
        if state.care != nil { parts.append(trf("%@ app mở khi đăng nhập", "\(on)")) }
        let missing = state.care?.loginMissing ?? 0
        if missing > 0 { parts.append(trf("%@ mục không còn file", "\(missing)")) }
        let heavy = (state.smart?.consumers.filter { $0.cpu >= 50 }.count) ?? 0
        if heavy > 0 { parts.append(trf("%@ tiến trình ngốn CPU", "\(heavy)")) }
        let attention = missing > 0 || heavy > 0
        return Group(id: "performance", page: .optimization, title: tr("Hiệu năng"), summary: parts.joined(separator: " · "),
                     status: attention ? .attention : .ok, review: .optimization)
    }

    var applications: Group {
        guard let c = state.care else {
            return Group(id: "applications", page: .updater, title: tr("Ứng dụng"), summary: scanned ? tr("Đang kiểm tra…") : tr("Chưa quét"), status: .pending, review: .updater)
        }
        if c.updates.isEmpty && c.unusedApps.isEmpty {
            return Group(id: "applications", page: .updater, title: tr("Ứng dụng"), summary: tr("Mọi app đều mới và đang được dùng"), status: .ok, review: .updater)
        }
        var parts: [String] = []
        if !c.updates.isEmpty { parts.append(trf("%@ bản cập nhật", "\(c.updates.count)")) }
        if !c.unusedApps.isEmpty { parts.append(trf("%@ app lâu không mở (%@)", "\(c.unusedApps.count)", ByteFormat.string(c.unusedBytes))) }
        return Group(id: "applications", page: .updater, title: tr("Ứng dụng"), summary: parts.joined(separator: " · "),
                     status: .attention, review: c.updates.isEmpty ? .uninstaller : .updater)
    }

    var clutter: Group {
        guard let c = state.care else {
            return Group(id: "clutter", page: .largeFiles, title: tr("File lớn & cũ"), summary: scanned ? tr("Đang kiểm tra…") : tr("Chưa quét"), status: .pending, review: .largeFiles)
        }
        if c.clutter.isEmpty {
            return Group(id: "clutter", page: .largeFiles, title: tr("File lớn & cũ"), summary: tr("Không có file lớn lâu không mở trong Downloads"), status: .ok, review: .largeFiles)
        }
        return Group(id: "clutter", page: .largeFiles, title: tr("File lớn & cũ"),
                     summary: trf("%@ file lớn lâu không mở trong Downloads (%@)", "\(c.clutter.count)", ByteFormat.string(c.clutterBytes)),
                     status: .attention, review: .largeFiles)
    }
}
