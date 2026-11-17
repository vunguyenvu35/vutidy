import SwiftUI
import CoreKit
import Modules

struct SmartScanView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var confirm = false
    @ViewState private var showDetails = true  // mở sẵn: người dùng luôn thấy sẽ dọn gì trước khi bấm Dọn

    var body: some View {
        let cleanable = state.smart?.cleanableBytes ?? 0
        VStack(alignment: .leading, spacing: 24) {
            SmartScanDashboard(onClean: { confirm = true }, details: cleanable > 0 && state.cleaning.isEmpty && !state.smartScanning ? AnyView(detailsPanel) : nil,
                               advisor: state.smart != nil && state.cleaning.isEmpty && !state.smartScanning ? AnyView(AIAdvisorCard()) : nil)
            AgentsPanel()
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .smooth(showDetails).smooth(state.smartScanning).smooth(state.smart == nil).smooth(state.cleaning.isEmpty)
            .confirmDialog(isPresented: $confirm, title: trf("Dọn %@?", ByteFormat.string(cleanable)),
                           message: breakdownLine + quitNotice + "\n\n" + trf("Chỉ các mục an toàn. Bạn có thể khôi phục trong %@ ngày. Thùng rác sẽ được dọn vĩnh viễn và mục dùng lệnh CLI (docker, go, brew) không hoàn tác được.", "\(state.retentionDays)"),
                           confirmTitle: tr("Chuyển vào Quarantine"), symbol: "v.smartScan") {
                Task { await state.cleanSmart(mode: .quarantine) }
            }
    }

    // MARK: Chi tiết những gì sẽ được dọn

    /// Các mục `safe` mà nút Dọn sẽ xử lý, gom theo nhóm (cùng quy tắc với `cleanSmart`).
    var safeGroups: [(name: String, module: String, count: Int, size: Int64)] {
        var out: [(String, String, Int, Int64)] = []
        for id in ["system-junk", "dev-junk", "trash"] {
            let safe = (state.results[id] ?? []).filter { $0.safety == .safe }
            for (cat, items) in Dictionary(grouping: safe, by: \.category) {
                out.append((cat, id, items.count, items.reduce(0) { $0 + $1.allocatedSize }))
            }
        }
        return out.sorted { $0.3 > $1.3 }
    }

    /// Một dòng tóm tắt cho hộp thoại xác nhận: "Cache 2,44 GB · Docker 7,18 GB · …" (6 nhóm lớn nhất).
    /// Các app đang chạy phải đóng để dọn cache của chúng (rồi tự mở lại).
    var quitNotice: String {
        let names = Set(["system-junk", "dev-junk", "trash"].flatMap { state.appsToQuit(for: $0).map(\.name) }).sorted()
        return names.isEmpty ? "" : "\n\n" + trf("Sẽ đóng rồi mở lại: %@. Lưu công việc của bạn trước.", names.joined(separator: ", "))
    }

    var breakdownLine: String {
        let g = safeGroups
        let top = g.prefix(6).map { "\($0.name) \(ByteFormat.string($0.size))" }.joined(separator: " · ")
        return g.count > 6 ? top + trf(" · +%@ nhóm khác", "\(g.count - 6)") : top
    }

    var detailsPanel: some View {
        let groups = safeGroups
        let total = max(1, groups.reduce(0) { $0 + $1.size })
        return VStack(alignment: .leading, spacing: 0) {
            Button { showDetails.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Sẽ dọn những gì")).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                        Text(tr("Chỉ mục an toàn. Mục \"Cần xem lại\" không bị đụng tới.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                        .rotationEffect(.degrees(showDetails ? 180 : 0))
                }
                .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
            }.buttonStyle(PlainPointerStyle())
            if showDetails { ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                Divider().overlay(Theme.Border.subtle)
                Button { state.section = g.module == "system-junk" ? .systemJunk : (g.module == "dev-junk" ? .devJunk : .trash) } label: {
                    HStack(spacing: 14) {
                        Text(g.name).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(Theme.Text.primary).frame(width: 150, alignment: .leading)
                        MeterBar(value: Double(g.size) / Double(total), color: Color.white.opacity(0.85), height: 4).frame(maxWidth: 220)
                        Text(trf("%@ mục", "\(g.count)")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                        Spacer()
                        Text(ByteFormat.string(g.size)).font(.vt(size: 13.5, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(PlainPointerStyle())
            } }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
