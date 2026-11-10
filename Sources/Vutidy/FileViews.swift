import SwiftUI
import CoreKit
import ScanEngine
import Modules

/// Danh sách mục tự quản lý chọn/dọn, dùng cho File lớn & cũ, Trùng lặp, Cloud.
struct ItemsPanel: View {
    @EnvironmentObject var state: AppState
    @Binding var items: [ScanItem]
    var actionTitle = tr("Chuyển vào Quarantine")
    var customAction: (([ScanItem]) async -> Void)? = nil
    @ViewState private var confirm = false
    @ViewState private var busy = false

    var selected: [ScanItem] { items.filter(\.selected) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(trf("%@ mục · đã chọn %@ (%@)", "\(items.count)", "\(selected.count)", "\(ByteFormat.string(selected.reduce(0) { $0 + $1.allocatedSize }))"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Spacer()
                Button(tr("Bỏ chọn tất cả")) { for i in items.indices { items[i].selected = false } }.buttonStyle(SecondaryButtonStyle())
                Button { confirm = true } label: {
                    if busy { HStack(spacing: 8) { VSpinner(size: 15, lineWidth: 2); Text(tr("Đang dọn…")) } } else { Text(actionTitle) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(selected.isEmpty || busy)
            }
            VStack(spacing: 0) {
                ForEach($items) { $i in
                    HStack(spacing: 12) {
                        VCheckbox(isOn: $i.selected)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).lineLimit(1)
                            Text(i.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(Theme.Font.mono)
                                .foregroundStyle(Theme.Text.secondary).lineLimit(1).truncationMode(.middle)
                            if let d = i.detail { Text(d).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).lineLimit(1) }
                        }
                        Spacer()
                        Text(ByteFormat.string(i.allocatedSize)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .contextMenu { Button(tr("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([i.url]) } }
                    Divider().overlay(Theme.Border.subtle)
                }
            }.cardFlat()
        }
        .confirmDialog(isPresented: $confirm, title: trf("%@: %@ mục?", "\(actionTitle)", "\(selected.count)"),
                       message: trf("Các mục không bị xóa vĩnh viễn; khôi phục được trong %@ ngày.", "\(state.retentionDays)"),
                       confirmTitle: actionTitle, symbol: "v.quarantine") {
            busy = true
            Task {
                if let customAction { await customAction(selected) } else { await state.cleanLocal(selected, mode: .quarantine) }
                let gone = Set(selected.map(\.id))
                items.removeAll { gone.contains($0.id) }
                busy = false
            }
        }
    }
}

extension AppState {
    /// Dọn một danh sách mục tùy ý (không thuộc module quét cố định).
    func cleanLocal(_ items: [ScanItem], mode: CleanMode) async {
        let report = await executor.execute(items, mode: mode)
        lastReport = report
        notify(trf("Đã chuyển %@ vào Quarantine", "\(ByteFormat.string(report.reclaimedBytes))") + (report.failures.isEmpty ? "" : trf(" · %@ lỗi", "\(report.failures.count)")),
               report.failures.isEmpty ? .success : .warning, undo: true)
        await refreshQuarantine()
        pollSystem()
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var items: [ScanItem] = []
    @ViewState private var minMB = 100.0
    @ViewState private var days = 0
    @ViewState private var kind: FileKind = .all
    @ViewState private var root = NSHomeDirectory()
    @ViewState private var busy = false
    @ViewState private var scanned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(caption: tr("Lọc theo dung lượng, độ cũ, loại file"), title: tr("File lớn & cũ"),
                       trailing: AnyView(Button(busy ? tr("Đang quét…") : tr("Quét")) { run() }.buttonStyle(PrimaryButtonStyle()).disabled(busy)))
            HStack(spacing: 16) {
                LabeledControl(label: tr("Loại")) {
                    VSelect(selection: $kind, options: FileKind.allCases.map { ($0, $0.title) }, width: 150)
                }
                LabeledControl(label: tr("Lớn hơn")) {
                    VSelect(selection: $minMB, options: [(50.0, "50 MB"), (100.0, "100 MB"), (500.0, "500 MB"), (1000.0, "1 GB")], width: 120)
                }
                LabeledControl(label: tr("Chưa mở")) {
                    VSelect(selection: $days, options: [(0, tr("Bất kỳ")), (30, tr("30 ngày")), (90, tr("90 ngày")), (365, tr("1 năm"))], width: 130)
                }
                Button(trf("Thư mục: %@", "\(URL(fileURLWithPath: root).lastPathComponent)")) {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { root = u.path }
                }.buttonStyle(SecondaryButtonStyle())
            }.card()
            if busy { LoadingCard(title: tr("Đang quét…"), subtitle: tr("Có thể mất vài phút với thư mục lớn.")) }
            else if scanned && items.isEmpty { EmptyStateView(icon: "checkmark.seal", title: tr("Không có file phù hợp"), subtitle: tr("Thử giảm ngưỡng dung lượng.")) }
            else if !items.isEmpty { ItemsPanel(items: $items) }
        }
    }

    func run() {
        busy = true
        let f = LargeOldFilesFinder(roots: [URL(fileURLWithPath: root)], minBytes: Int64(minMB * 1_000_000), olderThanDays: days, kind: kind)
        Task.detached {
            let r = f.find()
            await MainActor.run { withAnimation(.easeInOut(duration: 0.3)) { items = r; busy = false; scanned = true } }
        }
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var groups: [DuplicateGroup] = []
    @ViewState private var items: [ScanItem] = []
    @ViewState private var busy = false
    @ViewState private var scanned = false
    @ViewState private var status = ""
    @ViewState private var root = NSHomeDirectory() + "/Downloads"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(caption: tr("size → hash 8KB đầu/cuối → hash toàn bộ (SHA-256)"),
                       title: groups.isEmpty ? tr("File trùng lặp") : trf("Lãng phí %@", "\(ByteFormat.string(groups.reduce(0) { $0 + $1.wasted }))"),
                       trailing: AnyView(HStack {
                           Button(trf("Thư mục: %@", "\(URL(fileURLWithPath: root).lastPathComponent)")) {
                               let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                               if p.runModal() == .OK, let u = p.url { root = u.path }
                           }.buttonStyle(SecondaryButtonStyle())
                           Button(busy ? tr("Đang quét…") : tr("Quét")) { run() }.buttonStyle(PrimaryButtonStyle()).disabled(busy)
                       }))
            Text(tr("Mỗi nhóm giữ lại bản đầu tiên theo đường dẫn; các bản còn lại được liệt kê và không tự chọn. Lưu ý: bản sao APFS (clone) chưa được nhận diện riêng nên dung lượng 'lãng phí' có thể bị ước tính cao."))
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            if busy { LoadingCard(title: tr("Đang quét…"), subtitle: status) }
            else if scanned && items.isEmpty { EmptyStateView(icon: "checkmark.seal", title: tr("Không có file trùng"), subtitle: "") }
            else if !items.isEmpty { ItemsPanel(items: $items) }
        }
    }

    func run() {
        busy = true
        let finder = DuplicateFinder(roots: [URL(fileURLWithPath: root)])
        Task {
            let g = await finder.find(progress: { s in Task { @MainActor in status = s } })
            withAnimation(.easeInOut(duration: 0.3)) { groups = g; items = DuplicateFinder.items(from: g); busy = false; scanned = true }
        }
    }
}

struct CloudView: View {
    @ViewState private var items: [ScanItem] = []
    @ViewState private var busy = false
    @ViewState private var scanned = false
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(caption: tr("Gỡ bản local, giữ nguyên trên cloud"), title: "Cloud Cleanup",
                       trailing: AnyView(Button(busy ? tr("Đang quét…") : tr("Quét iCloud Drive")) { run() }.buttonStyle(PrimaryButtonStyle()).disabled(busy)))
            if busy { LoadingCard(title: tr("Đang quét…"), subtitle: "iCloud Drive") }
            else if scanned && items.isEmpty { EmptyStateView(icon: "icloud", title: tr("Không có file iCloud lớn nào đã tải về"), subtitle: tr("Cần Full Disk Access để quét iCloud Drive.")) }
            else if !items.isEmpty {
                ItemsPanel(items: $items, actionTitle: tr("Gỡ bản local")) { sel in
                    let out = CloudCleanup.evict(sel)
                    state.toast = trf("Đã gỡ bản local của %@ file (vẫn còn trên iCloud)", "\(out.filter { $0.status == .done }.count)")
                }
            }
        }
    }
    func run() {
        busy = true
        Task.detached { let r = CloudCleanup.downloadedFiles(); await MainActor.run { withAnimation(.easeInOut(duration: 0.3)) { items = r; busy = false; scanned = true } } }
    }
}
