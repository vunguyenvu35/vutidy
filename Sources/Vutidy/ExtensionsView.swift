import SwiftUI
import AppKit
import CoreKit
import Modules

/// Quản lý extension của bên thứ ba: plugin file (gỡ vào Quarantine) và extension trong app (bật/tắt qua pluginkit).
struct ExtensionsView: View {
    enum Filter: Hashable { case all, plugins, apps }

    @EnvironmentObject var state: AppState
    @ViewState private var items: [ExtensionItem] = []
    @ViewState private var loading = false
    @ViewState private var query = ""
    @ViewState private var filter: Filter = .all
    @ViewState private var removing: ExtensionItem?
    @ViewState private var toggling: Set<String> = []

    var filtered: [ExtensionItem] {
        items.filter { i in
            (filter == .all || (filter == .apps) == i.kind.isAppExtension)
                && (query.isEmpty || i.name.localizedCaseInsensitiveContains(query)
                    || (i.hostName?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    var sections: [(ExtensionItem.Kind, [ExtensionItem])] {
        ExtensionItem.Kind.allCases.compactMap { k in
            let rows = filtered.filter { $0.kind == k }
            return rows.isEmpty ? nil : (k, rows)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(caption: tr("Plugin và extension của bên thứ ba: gỡ plugin, bật/tắt extension trong app"), title: tr("Tiện ích mở rộng"),
                       trailing: AnyView(HStack(spacing: 10) {
                           ChipPicker(options: [(Filter.all, tr("Tất cả")), (.plugins, tr("Plugin")), (.apps, tr("Trong app"))], selection: $filter)
                           VTextField(placeholder: tr("Tìm extension"), text: $query, width: 220)
                       }))
            if loading { LoadingCard(title: tr("Đang liệt kê extension…")) }
            else if items.isEmpty {
                EmptyStateView(icon: "puzzlepiece.extension", title: tr("Không có extension của bên thứ ba"),
                               subtitle: tr("Plugin và extension do Apple cung cấp được ẩn."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        ForEach(sections, id: \.0) { kind, rows in
                            sectionHeader(kind, count: rows.count)
                            ForEach(rows) { row($0) }
                        }
                    }.vtScroller()
                }
                .cardFlat().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 20)
        .smooth(loading).smooth(items.count).smooth(filter)
        .task { if items.isEmpty { await reload() } }
        .confirmDialog(isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                       title: trf("Gỡ %@?", removing?.name ?? ""),
                       message: tr("Plugin được chuyển vào Quarantine, bạn có thể khôi phục trong vài ngày."),
                       confirmTitle: tr("Gỡ"), destructive: true, symbol: "v.trash") {
            if let r = removing { Task { await remove(r) } }
        }
    }

    func sectionHeader(_ kind: ExtensionItem.Kind, count: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.Text.secondary)
                Text(kind.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                Text("\(count)").font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9).background(Color.white.opacity(0.07))
            Divider().overlay(Theme.Border.subtle)
        }
    }

    func row(_ i: ExtensionItem) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppIconView(image: icon(for: i), fallback: i.kind.symbol, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(i.name).foregroundStyle(Theme.Text.primary).lineLimit(1)
                    Text(subtitle(i)).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                }
                Spacer()
                if i.size > 0 { Text(ByteFormat.string(i.size)).monospacedDigit().foregroundStyle(Theme.Text.secondary).frame(width: 78, alignment: .trailing) }
                trailing(i)
            }
            .font(Theme.Font.body).padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(Theme.Border.subtle)
        }
    }

    @ViewBuilder func trailing(_ i: ExtensionItem) -> some View {
        HStack(spacing: 8) {
            Button { NSWorkspace.shared.activateFileViewerSelecting([i.hostURL ?? i.url]) } label: {
                Image(systemName: "folder").font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(Theme.Text.tertiary).pointerCursor().help(tr("Hiện trong Finder"))
            if i.kind.isAppExtension, let bid = i.bundleID {
                SwitchRow(isOn: Binding(get: { i.enabled }, set: { on in Task { await setEnabled(on, i, bid) } }), label: i.name)
                    .disabled(toggling.contains(i.id)).opacity(toggling.contains(i.id) ? 0.5 : 1)
            } else if i.removable {
                Button(tr("Gỡ")) { removing = i }.buttonStyle(DangerButtonStyle()).controlSize(.small)
            } else {
                Pill(text: tr("Cần quyền admin"))
            }
        }
    }

    func icon(for i: ExtensionItem) -> NSImage? {
        i.kind.isAppExtension ? (i.hostURL.map { NSWorkspace.shared.icon(forFile: $0.path) }) : NSWorkspace.shared.icon(forFile: i.url.path)
    }

    func subtitle(_ i: ExtensionItem) -> String {
        if i.kind.isAppExtension { return [i.hostName, i.enabled ? nil : tr("Đã tắt")].compactMap { $0 }.joined(separator: " · ") }
        return i.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: Hành động

    func reload() async { loading = true; items = await ExtensionScanner.scan(); loading = false }

    func setEnabled(_ on: Bool, _ i: ExtensionItem, _ bid: String) async {
        toggling.insert(i.id)
        let ok = await ExtensionScanner.setEnabled(on, bundleID: bid)
        if ok, let idx = items.firstIndex(where: { $0.id == i.id }) { items[idx].enabled = on }
        else if !ok { state.notify(trf("Không đổi được trạng thái của %@", i.name), .warning) }
        toggling.remove(i.id)
    }

    func remove(_ i: ExtensionItem) async {
        let item = ScanItem(url: i.url, title: i.name, allocatedSize: i.size, category: i.kind.title, ruleID: "extension-remove", safety: .review, selected: true)
        await state.cleanLocal([item], mode: .quarantine)
        await reload()
    }
}
