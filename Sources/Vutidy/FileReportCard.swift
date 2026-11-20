import SwiftUI
import AppKit
import CoreKit
import Modules

/// Kết quả "Kiểm tra file…": kết luận, lý do, chi tiết kỹ thuật và hành động (Cách ly, Hiện trong Finder, Đóng).
struct FileReportCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.fileChecking {
            SectionCard(title: tr("Kết quả kiểm tra file"), symbol: "magnifyingglass", tint: Theme.Info.base) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) { VSpinner(size: 16, lineWidth: 2); Text(tr("Đang kiểm tra…")).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary) }
                    Text(tr("App lớn có thể mất vài chục giây vì phải kiểm tra chữ ký và quét toàn bộ bên trong.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let r = state.fileReport {
            let (symbol, color, title): (String, Color, String) = {
                switch r.level {
                case .ok: return ("checkmark.seal.fill", Theme.Signal.base, tr("Không thấy dấu hiệu đáng ngờ"))
                case .review: return ("exclamationmark.triangle.fill", Theme.Review.base, tr("Nên xem lại file này"))
                case .danger: return ("xmark.octagon.fill", Theme.danger, tr("File có dấu hiệu nguy hiểm"))
                }
            }()
            SectionCard(title: tr("Kết quả kiểm tra file"), subtitle: r.path, symbol: "magnifyingglass", tint: color, trailing: {
                HStack(spacing: 10) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) } label: {
                        IconLabel(title: tr("Hiện trong Finder"), symbol: "folder")
                    }.buttonStyle(SecondaryButtonStyle())
                    Button { Task { await state.quarantineChecked() } } label: { IconLabel(title: tr("Cách ly"), symbol: "archivebox") }
                        .buttonStyle(SecondaryButtonStyle()).help(tr("Chuyển vào Quarantine, khôi phục được"))
                    Button { state.fileReport = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                        .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary).help(tr("Đóng"))
                }
            }) {
                ListRow(title: title, subtitle: r.reasons.isEmpty ? tr("Kết quả sạch không đảm bảo máy an toàn tuyệt đối — đây không phải antivirus.") : r.reasons.joined(separator: " "),
                        showDivider: true, leading: { IconTile(symbol: symbol, tint: color, size: 34) }, trailing: { EmptyView() })
                row(tr("Tên"), r.name)
                row(tr("Loại file"), r.kind.isEmpty ? "—" : r.kind)
                row(tr("Dung lượng"), ByteFormat.string(r.size))
                row(tr("Chữ ký"), signatureText(r.signature))
                if let g = r.gatekeeper { row("Gatekeeper", g) }
                row(tr("Tải về từ"), sourceText(r))
                row("ClamAV", clamText(r.clam))
                row("SHA-256", r.sha256 ?? tr("Bỏ qua (thư mục hoặc file quá lớn)"), mono: true, last: true)
            }
        }
    }

    private func row(_ label: String, _ value: String, mono: Bool = false, last: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(mono ? .system(size: 12, design: .monospaced) : Theme.Font.body).foregroundStyle(Theme.Text.primary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(Theme.Border.subtle).padding(.leading, 18) } }
    }

    private func signatureText(_ s: FileReport.Signature) -> String {
        switch s {
        case .apple: return tr("Apple")
        case .appStore: return "App Store"
        case .notarized: return tr("Developer ID, đã công chứng (notarized)")
        case .signedNotNotarized: return tr("Có chữ ký nhưng chưa công chứng")
        case .unsigned: return tr("Chưa ký hoặc ký ad-hoc")
        case .tampered: return tr("Chữ ký bị hỏng")
        case .unreadable: return tr("Không đọc được chữ ký")
        case .notApplicable: return tr("Không áp dụng (không phải app hoặc file thực thi)")
        }
    }

    private func sourceText(_ r: FileReport) -> String {
        var parts: [String] = []
        if !r.sources.isEmpty { parts.append(r.sources.joined(separator: "\n")) }
        parts.append(r.fromInternet ? tr("Có dấu tải từ Internet (macOS sẽ hỏi khi mở)") : tr("Không có dấu tải từ Internet"))
        return parts.joined(separator: "\n")
    }

    private func clamText(_ c: FileReport.Clam) -> String {
        switch c {
        case .clean: return tr("Sạch")
        case .found(let sig): return trf("Khớp chữ ký “%@”", sig)
        case .notInstalled: return tr("Chưa cài ClamAV")
        case .noDatabase: return tr("Chưa có cơ sở dữ liệu")
        case .skipped: return tr("Không quét")
        }
    }
}
