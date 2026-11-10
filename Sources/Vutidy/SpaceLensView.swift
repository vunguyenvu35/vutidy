import SwiftUI
import AppKit
import CoreKit
import ScanEngine

// MARK: - Đường dẫn hiển thị (gốc là ổ đĩa)

/// Trên macOS hiện đại dữ liệu người dùng nằm ở volume Data (`/System/Volumes/Data`), được "firmlink" vào `/`.
/// Người dùng chỉ nên thấy đường dẫn logic (`/Users/...`) và tên ổ đĩa thật, không thấy tiền tố nội bộ.
enum SpacePaths {
    static let dataRoot = "/System/Volumes/Data"

    static func logical(_ p: String) -> String {
        if p == dataRoot { return "/" }
        return p.hasPrefix(dataRoot + "/") ? String(p.dropFirst(dataRoot.count)) : p
    }
    static func logicalURL(_ u: URL) -> URL { URL(fileURLWithPath: logical(u.path)) }
    /// Dạng hiển thị: bỏ tiền tố Data, thư mục Home rút gọn thành `~`.
    static func shown(_ p: String) -> String { logical(p).replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    /// Tên ổ đĩa khởi động (ví dụ "Macintosh HD").
    static var volumeName: String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "Macintosh HD"
    }
    static func name(of n: DirNode) -> String { n.url.path == dataRoot ? volumeName : n.name }
}

// MARK: - Phạm vi quét

struct SpaceScope: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let url: URL
}

enum SpaceScopes {
    static func all() -> [SpaceScope] {
        let home = NSHomeDirectory()
        func short(_ p: String) -> String { p.replacingOccurrences(of: home, with: "~") }
        var list = [
            // Trên macOS hiện đại dữ liệu người dùng nằm ở volume Data; "/" chỉ là volume hệ thống chỉ đọc.
            SpaceScope(id: "disk", title: SpacePaths.volumeName, subtitle: "/  ·  " + tr("Toàn bộ dữ liệu trên ổ khởi động. Quét lâu hơn."), symbol: "v.drive", url: URL(fileURLWithPath: "/System/Volumes/Data")),
            SpaceScope(id: "home", title: tr("Thư mục Home"), subtitle: short(home), symbol: "v.folder", url: URL(fileURLWithPath: home)),
        ]
        for (name, sym) in [("Downloads", "v.folder"), ("Documents", "v.doc"), ("Desktop", "v.folder")] {
            let p = home + "/" + name
            if FileManager.default.fileExists(atPath: p) { list.append(SpaceScope(id: name, title: name, subtitle: short(p), symbol: sym, url: URL(fileURLWithPath: p))) }
        }
        list.append(SpaceScope(id: "apps", title: tr("Ứng dụng"), subtitle: "/Applications", symbol: "v.uninstaller", url: URL(fileURLWithPath: "/Applications")))
        list.append(SpaceScope(id: "lib", title: tr("Thư viện"), subtitle: short(home + "/Library"), symbol: "v.box", url: URL(fileURLWithPath: home + "/Library")))
        for v in (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
            let u = URL(fileURLWithPath: "/Volumes/" + v)
            if u.resolvingSymlinksInPath().path == "/" { continue }
            list.append(SpaceScope(id: "vol-" + v, title: v, subtitle: u.path, symbol: "v.drive", url: u))
        }
        return list
    }
}

struct SpaceLensView: View {
    @EnvironmentObject var state: AppState
    @ViewState private var scanRoot: URL?
    @ViewState private var path: [URL] = []
    @ViewState private var cache: [String: DirNode] = [:]
    @ViewState private var current: DirNode?
    @ViewState private var scanning = false
    @ViewState private var scanTitle = ""
    @ViewState private var live = ScanSnapshot()
    @ViewState private var scanTask: Task<Void, Never>?
    @ViewState private var selection: DirNode?
    @ViewState private var checked: Set<String> = []
    @ViewState private var anchor: String?
    @ViewState private var style = 0
    @ViewState private var confirm = false
    @ViewState private var confirmDelete = false
    @ViewState private var picking = false

    var rootName: String {
        guard let r = scanRoot else { return "" }
        return r.path == SpacePaths.dataRoot ? SpacePaths.volumeName : (r.path == NSHomeDirectory() ? "~" : r.lastPathComponent)
    }

    /// Mục sẽ bị tác động: các mục được tick (chế độ Danh sách) hoặc, nếu chưa tick gì, mục đang chọn.
    var targets: [DirNode] {
        let ticked = (current?.children ?? []).filter { checked.contains($0.id) && !$0.isAggregate }
        if !ticked.isEmpty { return ticked }
        if let s = selection, !s.isAggregate { return [s] }
        return []
    }
    var canAct: Bool { !scanning && !picking && current != nil && !targets.isEmpty }
    var targetsLabel: String { targets.count == 1 ? targets[0].name : trf("%@ mục", "\(targets.count)") }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FDABannerIfNeeded()
                    if scanning { scanningView }
                    else if scanRoot == nil || picking || current == nil { picker }
                    else { results }
                }
                .padding(.horizontal, 28).padding(.top, 32).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            // Thanh hành động ghim đáy: danh sách dài kéo xuống vẫn thấy nút Quarantine / Xóa.
            if canAct { actionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .onChange(of: canAct) { state.pinnedBarVisible = $0 }
        .onDisappear { state.pinnedBarVisible = false }
        .smooth(canAct).smooth(scanning).smooth(scanRoot == nil).smooth(picking).smooth(current?.id).smooth(style).smooth(selection?.id, 0.2).smooth(checked.count)
        .task {
            // Kiểm thử/chụp màn hình: VUTIDY_SPACE=<thư mục> quét ngay thay vì hiện màn chọn phạm vi.
            if scanRoot == nil, let p = ProcessInfo.processInfo.environment["VUTIDY_SPACE"] { start(URL(fileURLWithPath: p)) }
        }
        .confirmDialog(isPresented: $confirm, title: trf("Chuyển %@ vào Quarantine?", targetsLabel),
                       message: trf("Khôi phục được trong %@ ngày.", "\(state.retentionDays)"),
                       confirmTitle: tr("Chuyển vào Quarantine"), symbol: "v.quarantine") {
            Task { await moveSelection(.quarantine) }
        }
        .confirmDialog(isPresented: $confirmDelete, title: trf("Xóa %@ vĩnh viễn?", targetsLabel),
                       message: tr("Hành động này không thể hoàn tác."),
                       confirmTitle: tr("Xóa vĩnh viễn"), destructive: true, symbol: "v.trash") {
            Task { await moveSelection(.permanent) }
        }
    }

    // MARK: Chọn phạm vi

    var picker: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(caption: tr("Chọn ổ đĩa hoặc thư mục. Quét toàn bộ ổ đĩa sẽ mất nhiều thời gian hơn."), title: tr("Quét dung lượng ở đâu?"),
                       trailing: AnyView(picking && current != nil ? AnyView(Button(tr("Hủy")) { picking = false }.buttonStyle(SecondaryButtonStyle())) : AnyView(EmptyView())))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(SpaceScopes.all()) { s in
                    Button { start(s.url) } label: {
                        HStack(spacing: 14) {
                            SolidIcon(symbol: s.symbol, tint: Page.spaceLens.palette.glow, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.title).font(.vt(size: 14.5, weight: .semibold)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                                Text(s.subtitle).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                        }
                        .padding(14).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                        .glassSurface(radius: 16, strong: false).contentShape(Rectangle())
                    }.buttonStyle(PlainPointerStyle())
                }
                Button { pick() } label: {
                    HStack(spacing: 14) {
                        SolidIcon(symbol: "v.search", tint: Theme.Review.base, size: 44)
                        Text(tr("Chọn thư mục…")).font(.vt(size: 14.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(14).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                    .glassSurface(radius: 16, strong: false).contentShape(Rectangle())
                }.buttonStyle(PlainPointerStyle())
            }
        }
    }

    // MARK: Đang quét

    var scanningView: some View {
        SpaceScanProgress(title: scanTitle, symbol: scanRoot?.path == SpacePaths.dataRoot ? "v.drive" : "v.folder",
                          snapshot: live) { cancelScan() }
    }

    // MARK: Kết quả

    var results: some View {
        let node = current!
        return VStack(alignment: .leading, spacing: 16) {
            PageHeader(caption: SpacePaths.shown(node.url.path), title: "\(SpacePaths.name(of: node)): \(ByteFormat.string(node.size))",
                       trailing: AnyView(HStack(spacing: 10) {
                           ChipPicker(options: [(0, tr("Bong bóng")), (1, "Treemap"), (2, tr("Danh sách"))], selection: $style)
                           Button { picking = true } label: { IconLabel(title: tr("Đổi vị trí"), symbol: "v.folder") }.buttonStyle(SecondaryButtonStyle())
                           Button { if let r = scanRoot { start(r) } } label: { Label(tr("Quét lại"), systemImage: "arrow.clockwise") }.buttonStyle(SecondaryButtonStyle())
                       }))
            breadcrumb
            if node.children.isEmpty {
                EmptyStateView(icon: "folder", title: tr("Thư mục trống"), subtitle: "")
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 10) {
                        if style == 0 {
                            BubbleChart(nodes: node.children, selection: $selection, onOpen: open).frame(height: 500)
                        } else {
                            Group {
                                if style == 1 { Treemap(nodes: node.children, selection: $selection, onOpen: open).frame(height: 500) }
                                else { listView(node) }
                            }.cardFlat()
                        }
                        if style == 0 { BubbleLegend().padding(.horizontal, 4) }
                    }
                    detail.frame(width: 300)
                }
            }
        }
    }

    var breadcrumb: some View {
        HStack(spacing: 6) {
            Button(rootName) { goTo(index: -1) }.buttonStyle(SecondaryButtonStyle())
            ForEach(Array(path.enumerated()), id: \.offset) { i, u in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.Text.tertiary)
                Button(u.lastPathComponent) { goTo(index: i) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    func listView(_ root: DirNode) -> some View {
        let rows = Array(root.children.prefix(60))
        let selectable = rows.filter { !$0.isAggregate }
        let allOn = !selectable.isEmpty && selectable.allSatisfy { checked.contains($0.id) }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { if allOn { checked = [] } else { checked = Set(selectable.map(\.id)) } } label: {
                    Image(systemName: allOn ? "checkmark.square.fill" : (checked.isEmpty ? "square" : "minus.square.fill"))
                        .font(.system(size: 15)).foregroundStyle(checked.isEmpty ? Theme.Text.tertiary : Theme.Signal.base)
                }.buttonStyle(PlainPointerStyle()).help(allOn ? tr("Bỏ chọn") : tr("Chọn tất cả")).padding(.leading, 2)
                Text(checked.isEmpty ? tr("Chọn tất cả") : trf("%@ mục", "\(checked.count)")).font(Theme.Font.label).foregroundStyle(Theme.Text.secondary)
                Spacer()
                Text(tr("Ngày tạo")).font(Theme.Font.label).foregroundStyle(Theme.Text.tertiary).frame(width: 150, alignment: .trailing)
                Text(tr("Dung lượng")).font(Theme.Font.label).foregroundStyle(Theme.Text.tertiary).frame(width: 80, alignment: .trailing)
            }.padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(Theme.Border.subtle)
            ForEach(rows) { n in
                let on = checked.contains(n.id)
                // Ô tick là một vùng riêng (anh em, không lồng trong vùng bấm của dòng) để cú bấm không bị cử chỉ chọn/mở của dòng nuốt mất.
                HStack(spacing: 0) {
                    Group {
                        if n.isAggregate { Color.clear }
                        else {
                            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 16))
                                .foregroundStyle(on ? Theme.Signal.base : Theme.Text.tertiary)
                        }
                    }
                    .frame(width: 44).frame(maxHeight: .infinity).contentShape(Rectangle())
                    .onTapGesture { if !n.isAggregate { if on { checked.remove(n.id) } else { checked.insert(n.id) } } }
                    .pointerCursor()

                    HStack(spacing: 10) {
                        Image(systemName: n.isDir ? "folder" : "doc").foregroundStyle(Theme.Info.base)
                        Text(n.name).foregroundStyle(Theme.Text.primary).lineLimit(1)
                        Spacer()
                        if let d = n.created {
                            Text(d.formatted(date: .abbreviated, time: .shortened)).font(Theme.Font.caption).foregroundStyle(Theme.Text.tertiary).lineLimit(1)
                                .frame(width: 150, alignment: .trailing)
                        }
                        Text(ByteFormat.string(n.size)).monospacedDigit().foregroundStyle(Theme.Text.secondary).frame(width: 80, alignment: .trailing)
                    }
                    .padding(.trailing, 14).frame(maxHeight: .infinity)
                    .contentShape(Rectangle()).onTapGesture(count: 2) { open(n) }.onTapGesture { rowClick(n, in: rows) }.pointerCursor()
                }
                .frame(height: 40).font(Theme.Font.body)
                .background(on ? Theme.Signal.base.opacity(0.10) : (selection?.id == n.id ? Color.white.opacity(0.12) : .clear))
                Divider().overlay(Theme.Border.subtle)
            }
        }
    }

    /// Bấm dòng: thường = chọn riêng dòng đó; ⌘/⌃ + bấm = thêm/bớt vào nhóm đang chọn; ⇧ + bấm = chọn cả dải từ dòng neo.
    func rowClick(_ n: DirNode, in rows: [DirNode]) {
        let f = NSEvent.modifierFlags
        guard !n.isAggregate else { selection = n; return }
        if f.contains(.command) || f.contains(.control) {
            if checked.isEmpty, let s = selection, !s.isAggregate { checked.insert(s.id) }   // mục đang chọn trở thành phần tử đầu của nhóm
            if checked.contains(n.id) { checked.remove(n.id) } else { checked.insert(n.id) }
            anchor = n.id; selection = n
        } else if f.contains(.shift), let a = anchor ?? selection?.id,
                  let i = rows.firstIndex(where: { $0.id == a }), let j = rows.firstIndex(where: { $0.id == n.id }) {
            checked = Set(rows[min(i, j)...max(i, j)].filter { !$0.isAggregate }.map(\.id))
            selection = n
        } else {
            checked = []; anchor = n.id; selection = n
        }
    }

    var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = selection {
                let status = BubbleStatus.of(s)
                Text(s.name).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary)
                Text(SpacePaths.shown(s.isAggregate ? s.url.deletingLastPathComponent().path : s.url.path)).font(Theme.Font.mono).foregroundStyle(Theme.Text.secondary)
                Text(ByteFormat.string(s.size)).font(Theme.Font.display).foregroundStyle(Theme.Text.primary)
                if let d = s.created {
                    Text(trf("Tạo lúc %@", d.formatted(date: .long, time: .shortened))).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
                if s.isAggregate {
                    Text(tr("Gồm nhiều mục nhỏ hơn nên không hiện riêng lẻ. Mở thư mục chứa để xem và xử lý từng mục.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                } else if status != .normal { Pill(text: status.label, color: status.color) }
                if s.name == "Docker.raw" || s.url.path.contains("com.docker.docker") {
                    Text(tr("Docker.raw không nên xóa trực tiếp. Hãy dọn bằng Dev Junk (docker prune).")).font(Theme.Font.caption).foregroundStyle(Theme.Review.text)
                    Button(tr("Mở Dev Junk")) { state.section = .devJunk }.buttonStyle(SecondaryButtonStyle())
                }
                HStack {
                    if s.isDir && !s.isAggregate { Button(tr("Mở")) { open(s) }.buttonStyle(SecondaryButtonStyle()) }
                    if s.isAggregate {
                        Button(tr("Mở thư mục chứa trong Finder")) { NSWorkspace.shared.open(SpacePaths.logicalURL(s.url.deletingLastPathComponent())) }.buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button(tr("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([SpacePaths.logicalURL(s.url)]) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            } else { Text(tr("Chọn một ô để xem chi tiết. Bấm đúp để mở thư mục.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).card(hero: true)
    }

    var actionBar: some View {
        let total = targets.reduce(Int64(0)) { $0 + $1.size }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("Đã chọn")).font(Theme.Font.label).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ByteFormat.string(total)).font(.vt(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                    Text(targetsLabel).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            // Bỏ chọn cả mục đang chọn lẫn các mục đã tick → thanh đáy ẩn đi. Phím Esc cũng làm được.
            Button { selection = nil; checked = []; anchor = nil } label: { Label(tr("Bỏ chọn"), systemImage: "xmark") }
                .buttonStyle(TextActionStyle(color: Theme.Text.secondary)).keyboardShortcut(.cancelAction)
            Button { confirm = true } label: { IconLabel(title: tr("Chuyển vào Quarantine"), symbol: "v.quarantine") }.buttonStyle(PrimaryButtonStyle())
            Button { confirmDelete = true } label: { IconLabel(title: tr("Xóa vĩnh viễn"), symbol: "v.trash") }.buttonStyle(DangerButtonStyle())
        }
        .padding(.horizontal, 32).padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Border.default).frame(height: 1) }
    }

    // MARK: Quét & điều hướng

    func index(_ n: DirNode) {
        guard !n.isAggregate else { return }
        cache[n.url.path] = n
        n.children.forEach(index)
    }

    func runScan(_ url: URL, push: Bool, title: String) {
        scanTask?.cancel()
        let p = ScanProgress()
        scanTitle = title; live = ScanSnapshot(); scanning = true; selection = nil; checked = []; anchor = nil
        Task { while scanning { live = p.snapshot; try? await Task.sleep(nanoseconds: 250_000_000) } }
        scanTask = Task {
            let tree = await DirectoryTree.build(root: url, maxDepth: 3, progress: p)
            if Task.isCancelled { scanning = false; return }
            index(tree)
            current = tree
            if push { path.append(url) }
            scanning = false
        }
    }

    func start(_ url: URL) {
        scanRoot = url; path = []; cache = [:]; current = nil; picking = false
        runScan(url, push: false, title: url.path == SpacePaths.dataRoot ? SpacePaths.volumeName : url.lastPathComponent)
    }

    func cancelScan() {
        scanTask?.cancel(); scanning = false
        if current == nil { scanRoot = nil }
    }

    func open(_ n: DirNode) {
        guard n.isDir, !n.isAggregate else { return }
        selection = nil; checked = []; anchor = nil
        // Nút đã có con trong bộ nhớ đệm → mở ngay, không quét lại.
        if let cached = cache[n.url.path], !cached.children.isEmpty || cached.size == 0 {
            current = cached; path.append(n.url)
        } else {
            runScan(n.url, push: true, title: n.name)
        }
    }

    func goTo(index i: Int) {
        selection = nil; checked = []; anchor = nil
        if i < 0 { path = []; current = scanRoot.flatMap { cache[$0.path] } }
        else { path = Array(path.prefix(i + 1)); current = cache[path[i].path] }
    }

    func pick() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        p.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if p.runModal() == .OK, let u = p.url { start(u) }
    }

    func moveSelection(_ mode: CleanMode) async {
        let nodes = targets
        guard !nodes.isEmpty else { return }
        let items = nodes.map { ScanItem(url: SpacePaths.logicalURL($0.url), title: $0.name, allocatedSize: $0.size, category: "Space Lens", ruleID: "space-lens", safety: .review, selected: true) }
        let r = await state.executor.execute(items, mode: mode)
        state.lastReport = r
        if r.doneCount > 0 {
            var msg = mode == .permanent ? trf("Đã xóa %@", ByteFormat.string(r.reclaimedBytes)) : trf("Đã chuyển %@ vào Quarantine", ByteFormat.string(r.reclaimedBytes))
            if !r.failures.isEmpty { msg += trf(" · %@ lỗi", "\(r.failures.count)") }
            state.notify(msg, r.failures.isEmpty ? .success : .warning, undo: mode != .permanent)
        } else { state.notify(trf("Không thực hiện được: %@", r.outcomes.first.map { "\($0.status)" } ?? ""), .error) }
        await state.refreshQuarantine()
        selection = nil; checked = []; anchor = nil
        if let c = current { runScan(c.url, push: false, title: c.name) }
    }
}

/// Treemap chia nhị phân cân bằng theo tổng dung lượng.
struct Treemap: View {
    let nodes: [DirNode]
    @Binding var selection: DirNode?
    var onOpen: (DirNode) -> Void
    @ViewState private var hovered: String?

    var body: some View {
        GeometryReader { g in
            let maxSize = Double(nodes.map(\.size).max() ?? 1)
            let rects = Self.layout(nodes.filter { $0.size > 0 }, in: CGRect(origin: .zero, size: g.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.element.0.id) { _, pair in
                    let (n, r) = pair
                    let sel = selection?.id == n.id
                    let hov = hovered == n.id
                    let color = n.isAggregate ? Color(hex: 0x7D8796) : BubbleColor.heat((Double(n.size) / max(1, maxSize)).squareRoot())
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(hov ? 0.85 : (sel ? 0.7 : 0.5)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(sel ? Color.white : Color.white.opacity(0.18), lineWidth: sel ? 2 : 1))
                        .overlay(alignment: .topLeading) {
                            if r.width > 70 && r.height > 36 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.name).font(.vt(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(ByteFormat.string(n.size)).font(.vt(size: 11)).opacity(0.85)
                                }.foregroundStyle(.white).padding(8)
                            }
                        }
                        .frame(width: max(0, r.width - 3), height: max(0, r.height - 3))
                        .offset(x: r.minX + 1.5, y: r.minY + 1.5)
                        .onHover { hovered = $0 ? n.id : (hovered == n.id ? nil : hovered) }
                        .onTapGesture(count: 2) { onOpen(n) }
                        .onTapGesture { selection = n }
                        .pointerCursor()
                        .accessibilityLabel("\(n.name), \(ByteFormat.string(n.size))")
                }
            }
        }.padding(8)
    }

    static func layout(_ nodes: [DirNode], in rect: CGRect) -> [(DirNode, CGRect)] {
        guard !nodes.isEmpty else { return [] }
        if nodes.count == 1 { return [(nodes[0], rect)] }
        let total = nodes.reduce(0.0) { $0 + Double($1.size) }
        var acc = 0.0, split = 1
        for (i, n) in nodes.enumerated() { acc += Double(n.size); if acc >= total / 2 { split = max(1, min(nodes.count - 1, i + 1)); break } }
        let a = Array(nodes[..<split]), b = Array(nodes[split...])
        let fa = a.reduce(0.0) { $0 + Double($1.size) } / total
        if rect.width >= rect.height {
            let w = rect.width * fa
            return layout(a, in: CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height))
                 + layout(b, in: CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height))
        } else {
            let h = rect.height * fa
            return layout(a, in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h))
                 + layout(b, in: CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h))
        }
    }
}
