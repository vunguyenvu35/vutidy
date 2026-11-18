import SwiftUI
import CoreKit
import Modules

/// ClamAV tùy chọn trên trang Malware: tải cơ sở dữ liệu, quét theo yêu cầu, gộp kết quả vào danh sách phát hiện (có Cách ly như mọi mục khác).
@MainActor
extension AppState {
    func refreshClamStatus() async { clamStatus = await ClamAV.status() }

    func clamUpdateDatabase() async {
        guard clamBusy == nil else { return }
        clamBusy = tr("Đang tải cơ sở dữ liệu ClamAV…"); clamMessage = nil
        let r = await ClamAV.updateDatabase()
        clamBusy = nil
        switch r {
        case .success: clamMessage = tr("Đã cập nhật cơ sở dữ liệu ClamAV.")
        case .failure(.notInstalled): clamMessage = tr("Chưa cài ClamAV.")
        case .failure(let e): clamMessage = trf("Không tải được cơ sở dữ liệu: %@", "\(e)")
        }
        await refreshClamStatus()
    }

    func clamScan() async {
        guard clamBusy == nil else { return }
        clamBusy = tr("Đang quét bằng ClamAV… (có thể mất vài phút)"); clamMessage = nil
        let r = await ClamAV.scan()
        clamBusy = nil
        switch r {
        case .success(let found):
            if found.isEmpty { clamMessage = tr("ClamAV không thấy mối đe dọa trong các thư mục đã quét.") }
            else {
                clamMessage = trf("ClamAV có %@ phát hiện, xem ở mục Phát hiện bên dưới.", "\(found.count)")
                // Gộp vào báo cáo (loại trùng theo khóa) để dùng chung Cách ly/Bỏ qua và danh sách "mới".
                if var rep = malwareReport {
                    let known = Set(rep.findings.map(\.key)), ignored = MalwareStore.shared.ignoredKeys
                    rep.findings += found.filter { !known.contains($0.key) && !ignored.contains($0.key) }
                    rep.findings.sort { ($0.severity.rawValue, $0.title) < ($1.severity.rawValue, $1.title) }
                    malwareReport = rep
                }
            }
        case .failure(.notInstalled): clamMessage = tr("Chưa cài ClamAV.")
        case .failure(.noDatabase): clamMessage = tr("Chưa có cơ sở dữ liệu chữ ký. Hãy tải trước.")
        case .failure(let e): clamMessage = trf("ClamAV báo lỗi: %@", "\(e)")
        }
    }
}
