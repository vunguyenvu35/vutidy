import SwiftUI
import CoreKit
import Modules

/// Gỡ ứng dụng: danh sách thoáng, mỗi dòng có thanh dung lượng tỉ lệ (thấy ngay app nào chiếm nhiều chỗ), lọc nhanh "Lớn" / "Lâu không dùng",
/// sắp xếp theo dung lượng / lần dùng / nhà sản xuất. Chọn một app thì panel chi tiết trượt vào, nút Gỡ nằm cố định ở cuối panel.
struct UninstallerView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var apps: [AppInfo] = []
    @ViewState private var loading = false
    @ViewState private var selected: AppInfo?
    @ViewState private var plan: [ScanItem] = []
    @ViewState private var query = ""
    @ViewState private var confirm = false
    @ViewState private var busy = false
    @ViewState private var sort: Sort = .size
    @ViewState private var filter: Filter = .all
    @ViewState private var collapsed: Set<String> = []

    enum Sort: Hashable { case size, recent, vendor }
    enum Filter: Hashable { case all, large, unused }

    static let largeBytes: Int64 = 1_000_000_000
    static let unusedDays = 180

    func isUnused(_ a: AppInfo) -> Bool {
        guard let d = a.lastUsed else { return true }
        return d < Calendar.current.date(byAdding: .day, value: -Self.unusedDays, to: Date())!
    }
    func matches(_ a: AppInfo, _ f: Filter) -> Bool {
        switch f { case .all: return true; case .large: return a.size >= Self.largeBytes; case .unused: return isUnused(a) }
    }

    var filtered: [AppInfo] {
        var list = apps.filter { matches($0, filter) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
        switch sort {
        case .size, .vendor: list.sort { $0.size > $1.size }
        case .recent: list.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
        return list
    }
    var maxSize: Int64 { max(1, apps.map(\.size).max() ?? 1) }
    var accent: Color { state.section.tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(caption: tr("Gỡ app cùng leftovers theo bundle ID"), title: tr("Gỡ ứng dụng"),
                       trailing: AnyView(VTextField(placeholder: tr("Tìm ứng dụng"), text: $query, width: 240)))
            toolbar
            if loading { LoadingCard(title: tr("Đang liệt kê ứng dụng…")) }
            // Trang tự quản lý cuộn: danh sách cuộn riêng, còn tiêu đề và panel chi tiết (nút Gỡ) luôn nằm yên trong tầm nhìn.
            HStack(alignment: .top, spacing: 16) {
                ScrollView { listBody.padding(8).vtScroller() }
                    .cardFlat().frame(maxWidth: .infinity, maxHeight: .infinity)
                if let s = selected {
                    detailPanel(s).transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 20)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selected?.id)
        .smooth(loading).smooth(apps.count).smooth(sort).smooth(filter).smooth(collapsed)
        .task { if apps.isEmpty { loading = true; apps = await Uninstaller.installedApps(); loading = false } }
        .confirmDialog(isPresented: $confirm, title: trf("Gỡ %@?", "\(selected?.name ?? "")"),
                       message: trf("Ứng dụng và %@ mục liên quan (%@) sẽ bị xóa vĩnh viễn. Không thể hoàn tác.",
                                    "\(max(0, plan.filter(\.selected).count - 1))", ByteFormat.string(plan.filter(\.selected).reduce(0) { $0 + $1.allocatedSize })),
                       confirmTitle: tr("Gỡ cài đặt"), destructive: true, symbol: "v.trash") {
            Task { await uninstall() }
        }
    }

    // MARK: Thanh công cụ: lọc nhanh · tóm tắt · sắp xếp

    var toolbar: some View {
        HStack(spacing: 14) {
            ChipPicker(options: [(Filter.all, "\(tr("Tất cả"))  \(apps.count)"),
                                 (.large, "\(tr("Lớn"))  \(apps.filter { matches($0, .large) }.count)"),
                                 (.unused, "\(tr("Lâu không dùng"))  \(apps.filter { matches($0, .unused) }.count)")], selection: $filter)
            Spacer(minLength: 8)
            let list = filtered
            Text(trf("%@ ứng dụng", "\(list.count)") + " · " + ByteFormat.string(list.reduce(0) { $0 + $1.size }))
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).monospacedDigit()
            ChipPicker(options: [(Sort.size, tr("Dung lượng")), (.recent, tr("Lần dùng")), (.vendor, tr("Nhà sản xuất"))], selection: $sort)
        }
    }

    // MARK: Danh sách

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
        let list = filtered
        if list.isEmpty && !loading {
            Text(tr("Không có ứng dụng nào khớp")).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
                .frame(maxWidth: .infinity).padding(40)
        } else {
            LazyVStack(spacing: 2) {
                if sort == .vendor {
                    ForEach(vendorGroups) { g in
                        vendorHeader(g)
                        if !collapsed.contains(g.id) { ForEach(g.apps) { a in row(a, showVendor: g.isOther) } }
                    }
                } else {
                    ForEach(list) { a in row(a, showVendor: true) }
                }
            }
        }
    }

    /// Tiêu đề nhóm nhẹ: chữ nhỏ viết hoa như nhãn mục ở thanh bên, không dải nền; bấm để thu gọn.
    func vendorHeader(_ g: VendorGroup) -> some View {
        let open = !collapsed.contains(g.id)
        return HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0)).frame(width: 12)
            Text(g.name.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6)
            Text("\(g.apps.count)").font(.system(size: 11, weight: .medium)).opacity(0.7)
            Spacer()
            Text(ByteFormat.string(g.total)).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(Theme.Text.secondary)
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 6)
        .contentShape(Rectangle())
        .onTapGesture { if open { collapsed.insert(g.id) } else { collapsed.remove(g.id) } }
        .pointerCursor()
    }

    func row(_ a: AppInfo, showVendor: Bool) -> some View {
        AppRow(app: a, showVendor: showVendor, ratio: Double(a.size) / Double(maxSize), accent: accent, unused: isUnused(a), selected: selected?.id == a.id)
            .onTapGesture { choose(a) }
    }

    func choose(_ a: AppInfo) {
        if selected?.id == a.id { selected = nil; plan = []; return }
        selected = a; plan = Uninstaller.plan(for: a)
    }

    // MARK: Panel chi tiết

    func detailPanel(_ s: AppInfo) -> some View {
        let chosen = plan.filter(\.selected)
        let bytes = chosen.reduce(0) { $0 + $1.allocatedSize }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: s.url.path)).resizable().frame(width: 56, height: 56)
                    .shadow(color: accent.opacity(0.45), radius: 14, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.name).font(.vt(size: 17, weight: .bold)).foregroundStyle(Theme.Text.primary).lineLimit(2)
                    Text(s.bundleID).font(Theme.Font.mono).foregroundStyle(Theme.Text.secondary).lineLimit(1).truncationMode(.middle)
                    Text(ByteFormat.string(s.size)).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.Text.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
                Button { selected = nil; plan = [] } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Theme.Text.tertiary)
                }.buttonStyle(PlainPointerStyle()).help(tr("Đóng"))
            }
            if s.source == .homebrew {
                Label(tr("Cài qua Homebrew — nên gỡ bằng: brew uninstall --cask"), systemImage: "shippingbox.fill")
                    .font(Theme.Font.caption).foregroundStyle(Theme.Review.text)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Review.tint))
            }
            Text(trf("Gỡ cùng %@ mục liên quan", "\(max(0, plan.count - 1))")).font(.system(size: 11, weight: .bold)).tracking(0.5)
                .foregroundStyle(Theme.Text.tertiary).textCase(.uppercase)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach($plan) { $p in
                        HStack(spacing: 10) {
                            VCheckbox(isOn: $p.selected)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.title).lineLimit(1).foregroundStyle(Theme.Text.primary)
                                Text(p.detail ?? p.category).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            SafetyBadge(level: p.safety)
                            Text(ByteFormat.string(p.allocatedSize)).font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.Text.secondary)
                                .frame(width: 62, alignment: .trailing)
                        }
                        .font(Theme.Font.body).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(p.selected ? 0.05 : 0)))
                    }
                }.vtScroller()
            }
            // Panel co theo nội dung (danh sách dài thì cuộn trong 300 pt), nút Gỡ nằm liền ngay dưới danh sách chứ không dạt xuống đáy.
            .frame(maxHeight: 300).fixedSize(horizontal: false, vertical: plan.count < 6)
            Button { confirm = true } label: {
                if busy { HStack(spacing: 8) { VSpinner(size: 16, lineWidth: 2); Text(tr("Đang gỡ…")) } }
                else { IconLabel(title: trf("Gỡ %@", ByteFormat.string(bytes)), symbol: "v.trash") }
            }
            .buttonStyle(DangerButtonStyle(fullWidth: true)).controlSize(.regular).disabled(chosen.isEmpty || busy)
        }
        .frame(width: 400, alignment: .leading).card(hero: true)
    }

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

/// Một dòng ứng dụng: biểu tượng (phóng nhẹ khi rê chuột), tên + nguồn/lần dùng, thanh dung lượng tỉ lệ (mọc ra khi hiện) và con số.
private struct AppRow: View {
    let app: AppInfo
    let showVendor: Bool
    let ratio: Double
    let accent: Color
    let unused: Bool
    let selected: Bool
    @ViewState private var hover = false
    @ViewState private var grown = false

    var subtitle: String {
        (showVendor && !app.vendor.isEmpty ? app.vendor + " · " : "")
        + (app.lastUsed.map { trf("dùng %@", "\($0.formatted(.relative(presentation: .named)))") } ?? tr("chưa rõ lần dùng"))
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 36, height: 36)
                .scaleEffect(hover || selected ? 1.07 : 1).animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(app.name).font(.vt(size: 13.5, weight: .medium)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                    if app.source != .other { Pill(text: app.source.title) }
                }
                Text(subtitle).font(Theme.Font.caption).foregroundStyle(unused ? Theme.Review.text : Theme.Text.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            // Thanh tỉ lệ so với app lớn nhất.
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.95)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, 96 * (grown ? ratio : 0)))
            }.frame(width: 96, height: 5)
            Text(ByteFormat.string(app.size)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.Text.primary).frame(width: 76, alignment: .trailing)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.Text.tertiary)
                .opacity(hover || selected ? 1 : 0).offset(x: hover || selected ? 0 : -4)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? accent.opacity(0.20) : Color.white.opacity(hover ? 0.07 : 0))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(accent.opacity(selected ? 0.6 : 0), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(.easeOut(duration: 0.2), value: selected)
        .pointerCursor()
        .onAppear { withAnimation(.easeOut(duration: 0.7).delay(0.05)) { grown = true } }
    }
}
