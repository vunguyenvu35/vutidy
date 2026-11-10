import SwiftUI
import AppKit
import CoreKit
import Modules

/// "Mở khi đăng nhập": app nào tự mở khi bạn đăng nhập macOS, theo System Settings → General → Login Items.
/// Đọc từ kho Background Task Management (không cần quyền admin). macOS chỉ cho đổi công tắc trong System Settings,
/// nên mỗi dòng có nút **Quản lý** mở đúng trang đó.
struct LoginItemsCard: View {
    @ViewState private var items: [LoginItemEntry] = []
    @ViewState private var loaded = false
    @ViewState private var filter: Filter = .on

    enum Filter: Hashable, CaseIterable {
        case on, off, orphaned, all
        var title: String {
            switch self { case .on: return tr("Đang bật"); case .off: return tr("Đã tắt"); case .orphaned: return tr("Không còn file"); case .all: return tr("Tất cả") }
        }
    }

    func matches(_ e: LoginItemEntry, _ f: Filter) -> Bool {
        switch f { case .all: return true; case .on: return e.enabled; case .off: return !e.enabled; case .orphaned: return e.orphaned }
    }
    var shown: [LoginItemEntry] { items.filter { matches($0, filter) } }
    var onCount: Int { items.filter(\.enabled).count }

    var body: some View {
        SectionCard(title: tr("Mở khi đăng nhập"),
                    subtitle: loaded ? trf("%@ mục đang bật. Bật/tắt trong System Settings → Mục đăng nhập.", "\(onCount)") : tr("Đang đọc danh sách…"),
                    symbol: "person.crop.circle.badge.checkmark", tint: Theme.Signal.base,
                    trailing: {
            HStack(spacing: 10) {
                ChipPicker(options: Filter.allCases.map { f in (f, "\(f.title)  \(items.filter { matches($0, f) }.count)") }, selection: $filter)
                Button { NSWorkspace.shared.open(LoginItems.settingsURL) } label: { IconLabel(title: tr("Mở Login Items"), symbol: "gearshape") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }) {
            if shown.isEmpty {
                Text(loaded ? tr("Không có mục nào trong bộ lọc này") : tr("Đang đọc danh sách…"))
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity).padding(32)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, e in row(e, last: idx == shown.count - 1) }
        }
        .task { items = await LoginItems.list(); loaded = true }
    }

    func row(_ e: LoginItemEntry, last: Bool) -> some View {
        let url = e.path.map { URL(fileURLWithPath: $0) }
        let icon = url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? AppLookup.icon(forAppAt: $0) : nil }
        let sub = [e.developer, e.kind == .helper ? tr("Tiến trình phụ của app") : e.path.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }]
            .compactMap { $0 }.joined(separator: " · ")
        return ListRow(title: e.name, subtitle: sub, monoSubtitle: e.kind == .app, showDivider: !last, leading: {
            AppIconView(image: icon, fallback: e.kind == .helper ? "gearshape.fill" : "app.dashed", size: 34)
        }, trailing: {
            HStack(spacing: 10) {
                if e.orphaned { Pill(text: tr("Không còn file"), color: Theme.Review.text).help(tr("App đã bị xóa, nằm trong Thùng rác hoặc chạy từ thư mục tạm. Nên tắt mục này.")) }
                Pill(text: e.enabled ? tr("Đang bật") : tr("Đã tắt"), color: e.enabled ? Theme.Signal.text : Theme.Text.secondary)
                Button(tr("Quản lý")) { NSWorkspace.shared.open(LoginItems.settingsURL) }
                    .buttonStyle(TextActionStyle()).help(tr("Mở System Settings → Mục đăng nhập để bật hoặc tắt"))
            }
        })
    }
}
