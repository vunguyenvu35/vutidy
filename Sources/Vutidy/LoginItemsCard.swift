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
    @ViewState private var collapsed: Set<String> = ["apple"]

    enum Filter: Hashable, CaseIterable {
        case on, off, orphaned, all
        var title: String {
            switch self { case .on: return tr("Đang bật"); case .off: return tr("Đã tắt"); case .orphaned: return tr("Không còn file"); case .all: return tr("Tất cả") }
        }
    }

    func matches(_ e: LoginItemEntry, _ f: Filter) -> Bool {
        switch f { case .all: return true; case .on: return e.enabled; case .off: return !e.enabled; case .orphaned: return e.orphaned }
    }
    var filtered: [LoginItemEntry] { items.filter { matches($0, filter) } }

    struct Group: Identifiable {
        let id: String
        let name: String
        let items: [LoginItemEntry]
        var isOther: Bool { id == "__other__" }
    }

    /// Nhà phát triển có từ 2 mục trở lên thành nhóm riêng (nhiều mục đang bật trước, Apple cuối); phần lẻ gom vào "Khác".
    var groups: [Group] {
        let byKey = Dictionary(grouping: filtered, by: { $0.vendor.key })
        var out: [Group] = []
        var singles: [LoginItemEntry] = []
        for (key, list) in byKey {
            if key.isEmpty || (list.count < 2 && key != "apple") { singles += list }
            else { out.append(Group(id: key, name: list.first!.vendor.name, items: list)) }
        }
        func on(_ g: Group) -> Int { g.items.filter(\.enabled).count }
        out.sort { a, b in
            if (a.id == "apple") != (b.id == "apple") { return b.id == "apple" }
            return (on(a), b.name) > (on(b), a.name)
        }
        if !singles.isEmpty { out.insert(Group(id: "__other__", name: tr("Khác"), items: singles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }), at: out.firstIndex { $0.id == "apple" } ?? out.endIndex) }
        return out
    }

    func tint(_ key: String) -> Color {
        let palette: [Color] = [Theme.Info.base, Theme.apps, Theme.teal, Theme.pink, Theme.orange, Theme.Review.base, Theme.Signal.base]
        return palette[Int(key.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 1000 }) % palette.count]
    }
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
            if filtered.isEmpty {
                Text(loaded ? tr("Không có mục nào trong bộ lọc này") : tr("Đang đọc danh sách…"))
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity).padding(32)
            }
            ForEach(groups) { g in
                let open = !collapsed.contains(g.id)
                let on = g.items.filter(\.enabled).count
                GroupHeader(name: g.name, subtitle: trf("%@ mục", "\(g.items.count)"),
                            trailing: on > 0 ? trf("%@ đang bật", "\(on)") : nil,
                            tint: tint(g.id), muted: g.isOther || g.id == "apple", open: open) {
                    if open { collapsed.insert(g.id) } else { collapsed.remove(g.id) }
                }
                if open {
                    ForEach(Array(g.items.enumerated()), id: \.element.id) { idx, e in row(e, last: idx == g.items.count - 1) }
                }
            }
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
