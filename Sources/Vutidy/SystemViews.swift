import SwiftUI
import CoreKit
import Modules

struct UninstallerView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var apps: [AppInfo] = []
    @ViewState private var loading = false
    @ViewState private var selected: AppInfo?
    @ViewState private var plan: [ScanItem] = []
    @ViewState private var query = ""
    @ViewState private var confirm = false
    @ViewState private var busy = false
    @ViewState private var grouped = true
    @ViewState private var collapsed: Set<String> = []

    var filtered: [AppInfo] { query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(caption: tr("Gỡ app cùng leftovers theo bundle ID"), title: tr("Gỡ ứng dụng"),
                       trailing: AnyView(HStack(spacing: 10) {
                           ChipPicker(options: [(true, tr("Theo nhà sản xuất")), (false, tr("Danh sách"))], selection: $grouped)
                           VTextField(placeholder: tr("Tìm ứng dụng"), text: $query, width: 220)
                       }))
            if loading { LoadingCard(title: tr("Đang liệt kê ứng dụng…")) }
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 0) { listBody }.cardFlat().frame(maxWidth: .infinity)

                if let s = selected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(s.name).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                        Text(s.bundleID).font(Theme.Font.mono).foregroundStyle(Theme.Text.secondary)
                        if s.source == .homebrew {
                            Text(tr("Cài qua Homebrew — nên gỡ bằng: brew uninstall --cask")).font(Theme.Font.caption).foregroundStyle(Theme.Review.text)
                        }
                        ForEach($plan) { $p in
                            HStack {
                                VCheckbox(isOn: $p.selected)
                                VStack(alignment: .leading) {
                                    Text(p.title).lineLimit(1).foregroundStyle(Theme.Text.primary)
                                    Text(p.detail ?? p.category).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                                }
                                Spacer(); SafetyBadge(level: p.safety)
                                Text(ByteFormat.string(p.allocatedSize)).monospacedDigit().foregroundStyle(Theme.Text.secondary)
                            }.font(Theme.Font.body)
                        }
                        Button { confirm = true } label: {
                                if busy { HStack(spacing: 8) { VSpinner(size: 16, lineWidth: 2); Text(tr("Đang gỡ…")) } }
                else { IconLabel(title: trf("Gỡ %@", "\(ByteFormat.string(plan.filter(\.selected).reduce(0) { $0 + $1.allocatedSize }))"), symbol: "v.trash") }
                            }
                            .buttonStyle(DangerButtonStyle()).controlSize(.regular).disabled(plan.filter(\.selected).isEmpty)
                    }.frame(width: 420, alignment: .leading).card(hero: true)
                }
            }
        }
        .smooth(selected?.id, 0.2).smooth(loading).smooth(apps.count).smooth(grouped).smooth(collapsed)
        .task { if apps.isEmpty { loading = true; apps = await Uninstaller.installedApps(); loading = false } }
        .confirmDialog(isPresented: $confirm, title: trf("Gỡ %@?", "\(selected?.name ?? "")"),
                       message: trf("Ứng dụng và %@ mục liên quan (%@) sẽ bị xóa vĩnh viễn. Không thể hoàn tác.",
                                    "\(max(0, plan.filter(\.selected).count - 1))", ByteFormat.string(plan.filter(\.selected).reduce(0) { $0 + $1.allocatedSize })),
                       confirmTitle: tr("Gỡ cài đặt"), destructive: true, symbol: "v.trash") {
            Task { await uninstall() }
        }
    }

    // MARK: Danh sách theo nhà sản xuất

    struct VendorGroup: Identifiable {
        let id: String
        let name: String
        let apps: [AppInfo]
        var total: Int64 { apps.reduce(0) { $0 + $1.size } }
        var isOther: Bool { id == "__other__" }
    }

    /// Nhà sản xuất có từ 2 ứng dụng trở lên thành một nhóm riêng (lớn nhất trước); phần còn lại gom vào "Khác".
    var vendorGroups: [VendorGroup] {
        let byKey = Dictionary(grouping: filtered, by: \.vendorKey)
        var multi: [VendorGroup] = []
        var singles: [AppInfo] = []
        for (key, list) in byKey {
            if key.isEmpty || list.count < 2 { singles += list }
            else { multi.append(VendorGroup(id: key, name: list.first!.vendor, apps: list.sorted { $0.size > $1.size })) }
        }
        multi.sort { $0.total > $1.total }
        if !singles.isEmpty { multi.append(VendorGroup(id: "__other__", name: tr("Khác"), apps: singles.sorted { $0.size > $1.size })) }
        return multi
    }

    @ViewBuilder var listBody: some View {
        if grouped {
            ForEach(vendorGroups) { g in
                vendorHeader(g)
                if !collapsed.contains(g.id) {
                    ForEach(g.apps) { a in appRow(a, showVendor: g.isOther) }
                }
            }
        } else {
            ForEach(filtered) { a in appRow(a, showVendor: true) }
        }
    }

    func monogramTint(_ key: String) -> Color {
        let palette: [Color] = [Theme.Info.base, Theme.apps, Theme.teal, Theme.pink, Theme.orange, Theme.Review.base, Theme.Signal.base]
        return palette[Int(key.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 1000 }) % palette.count]
    }

    func vendorHeader(_ g: VendorGroup) -> some View {
        let open = !collapsed.contains(g.id)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(String(g.name.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(monogramTint(g.id).opacity(g.isOther ? 0.4 : 0.85)))
                Text(g.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                Text(trf("%@ ứng dụng", "\(g.apps.count)")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Spacer()
                Text(ByteFormat.string(g.total)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Text.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.white.opacity(0.07))
            .contentShape(Rectangle())
            .onTapGesture { if open { collapsed.insert(g.id) } else { collapsed.remove(g.id) } }
            .pointerCursor()
            Divider().overlay(Theme.Border.subtle)
        }
    }

    func appRow(_ a: AppInfo, showVendor: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name).foregroundStyle(Theme.Text.primary)
                    Text((showVendor && !a.vendor.isEmpty ? a.vendor + " · " : "")
                         + (a.lastUsed.map { trf("dùng %@", "\($0.formatted(.relative(presentation: .named)))") } ?? tr("chưa rõ lần dùng")))
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
                Spacer()
                if a.source != .other { Pill(text: a.source.title) }
                Text(ByteFormat.string(a.size)).monospacedDigit().foregroundStyle(Theme.Text.secondary).frame(width: 78, alignment: .trailing)
            }
            .font(Theme.Font.body).padding(.leading, grouped ? 28 : 14).padding(.trailing, 14).padding(.vertical, 8)
            .background(selected?.id == a.id ? Color.white.opacity(0.10) : .clear)
            .contentShape(Rectangle()).onTapGesture { choose(a) }.pointerCursor()
            Divider().overlay(Theme.Border.subtle)
        }
    }

    func choose(_ a: AppInfo) { selected = a; plan = Uninstaller.plan(for: a) }

    func uninstall() async {
        guard let app = selected else { return }
        let sel = plan.filter(\.selected)
        busy = true
        let report = await Uninstaller.uninstall(sel, app: app, executor: state.executor)
        state.lastReport = report
        let failed = report.failures.count + report.skipped.count
        state.toast = trf("Đã gỡ %@ · giải phóng %@", app.name, ByteFormat.string(report.reclaimedBytes))
                      + (failed > 0 ? " · " + trf("%@ lỗi · %@ bỏ qua", "\(report.failures.count)", "\(report.skipped.count)") : "")
        apps = await Uninstaller.installedApps()
        selected = nil; plan = []; busy = false
    }
}

