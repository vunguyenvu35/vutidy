import SwiftUI
import CoreKit
import Modules

/// Nhóm "Cập nhật" trong Cài đặt → Chung: kiểm tra, xem ghi chú bản mới, cập nhật ngay trong app.
struct UpdateSettingsGroup: View {
    @EnvironmentObject var state: AppState

    private var current: String { "\(UpdateChecker.currentVersion)" }

    private var status: (text: String, isError: Bool) {
        switch state.appUpdate {
        case .idle:
            if let d = state.lastUpdateCheck { return (trf("Kiểm tra lần cuối: %@", d.formatted(date: .abbreviated, time: .shortened)), false) }
            return (tr("Chưa kiểm tra."), false)
        case .checking: return (tr("Đang hỏi GitHub…"), false)
        case .upToDate: return (tr("Bạn đang dùng bản mới nhất."), false)
        case .available(let r): return (trf("Có bản %@ (bạn đang dùng %@).", "\(r.version)", current), false)
        case .downloading(let p): return (trf("Đang tải… %@%%", "\(Int(p * 100))"), false)
        case .installing: return (tr("Đang xác minh và cài đặt…"), false)
        case .failed(let m): return (m, true)
        }
    }

    var body: some View {
        SettingsGroup(title: tr("Cập nhật")) {
            SettingRow(title: trf("Vutidy %@", current), desc: status.text, showDivider: true) { action }
            if case .available(let r) = state.appUpdate { notes(r) }
            SettingRow(title: tr("Tự kiểm tra bản mới"),
                       desc: tr("Mỗi 24 giờ khi mở app. Chỉ tải số phiên bản mới nhất từ GitHub, không gửi gì về máy bạn."), showDivider: false) {
                SwitchRow(isOn: $state.autoCheckUpdates, label: tr("Tự kiểm tra bản mới"))
            }
        }
    }

    @ViewBuilder private var action: some View {
        switch state.appUpdate {
        case .checking, .installing:
            VSpinner(size: 18, lineWidth: 2)
        case .downloading(let p):
            MeterBar(value: p, color: .white, height: 6).frame(width: 140)
        case .available:
            Button(tr("Cập nhật và khởi động lại")) { Task { await state.installUpdate() } }.buttonStyle(PrimaryButtonStyle())
        default:
            Button(tr("Kiểm tra")) { Task { await state.checkForUpdates() } }.buttonStyle(SecondaryButtonStyle(minWidth: 120))
        }
    }

    private func notes(_ r: ReleaseInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.Border.subtle)
            Text(tr("Có gì mới")).font(.vt(size: 12, weight: .semibold)).foregroundStyle(Theme.Text.secondary)
            Text(summary(r.notes)).font(Theme.Font.caption).foregroundStyle(Theme.Text.primary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button(tr("Xem trên GitHub")) { NSWorkspace.shared.open(r.pageURL) }.buttonStyle(TextActionStyle())
            }
            Text(tr("Vutidy tải file .zip từ GitHub, kiểm tra SHA-256 và chữ ký rồi mới thay thế app. Bản chưa ký bằng Developer ID có thể cần cấp lại Full Disk Access sau khi cập nhật."))
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).fixedSize(horizontal: false, vertical: true)
        }.padding(.horizontal, 18).padding(.bottom, 14)
    }

    /// Lấy phần đầu ghi chú (bỏ tiêu đề `#`), tối đa ~12 dòng.
    private func summary(_ md: String) -> String {
        let lines = md.split(separator: "\n", omittingEmptySubsequences: true).map(String.init).filter { !$0.hasPrefix("# ") }
        let text = lines.prefix(12).joined(separator: "\n")
        return text.isEmpty ? tr("Không có ghi chú.") : text
    }
}

/// Thẻ cố định ở đáy sidebar khi có bản Vutidy mới (hoặc đang tải/cài): luôn thấy ở mọi trang, bấm để mở Cài đặt → Cập nhật.
struct UpdateBadgeCard: View {
    @EnvironmentObject var state: AppState

    private var info: (title: String, sub: String, busy: Bool)? {
        switch state.appUpdate {
        case .available(let r): return (trf("Có Vutidy %@ mới", "\(r.version)"), tr("Bấm để cập nhật"), false)
        case .downloading(let p): return (tr("Đang cập nhật…"), trf("Đang tải… %@%%", "\(Int(p * 100))"), true)
        case .installing: return (tr("Đang cập nhật…"), tr("Đang xác minh và cài đặt…"), true)
        default: return nil
        }
    }

    var body: some View {
        if let i = info {
            Button { state.openSettings(.general) } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.Signal.base.opacity(0.22))
                        if i.busy { VSpinner(size: 14, lineWidth: 2) }
                        else { Image(systemName: "arrow.down.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.Signal.base) }
                    }.frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(i.title).font(.vt(size: 12.5, weight: .semibold)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                        Text(i.sub).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Signal.base.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.Signal.base.opacity(0.35)))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainPointerStyle())
            .padding(.horizontal, 12).padding(.top, 6)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .help(tr("Cập nhật Vutidy"))
        }
    }
}
