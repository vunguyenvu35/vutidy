import SwiftUI
import CoreKit

/// Màn dọn dẹp dùng chung cho Rác hệ thống / Dev Junk / Thùng rác / Quyền riêng tư.
/// Bố cục: hero khi chưa quét → thẻ danh mục có icon lớn → thanh hành động ghim ở đáy.
struct CleanupView: View {
    @EnvironmentObject var state: AppState
    let section: Page
    @ViewState private var filter: SafetyFilter = .all
    @ViewState private var expanded: Set<String> = []
    @ViewState private var confirm = false
    @ViewState private var showCommands = false

    enum SafetyFilter: String, CaseIterable {
        case all = "Tất cả", safe = "An toàn", review = "Cần xem lại"
        var title: String { tr(rawValue) }
    }

    var id: String { section.cleanupID! }
    var items: [ScanItem] { state.results[id] ?? [] }
    var scanning: Bool { state.scanning.contains(id) }
    var busy: Bool { state.cleaning.contains(id) }
    /// Pha hiển thị của trang: 0 chưa quét · 1 không có gì · 2 có danh sách (+10 đang quét lại). Đổi pha → hoạt ảnh, không bật đột ngột.
    var phase: Int { (state.results[id] == nil ? 0 : (items.isEmpty ? 1 : 2)) + (scanning ? 10 : 0) + (state.cleanSummary[id] != nil ? 100 : 0) }
    var selected: [ScanItem] { items.filter(\.selected) }
    /// Thùng rác: các mục đã nằm trong Trash nên dọn = xóa vĩnh viễn.
    var effectiveMode: CleanMode { section == .trash ? (state.mode == .dryRun ? .dryRun : .permanent) : state.mode }

    func matches(_ i: ScanItem, _ f: SafetyFilter) -> Bool {
        f == .all || (f == .safe ? i.safety == .safe : i.safety != .safe)
    }
    var visible: [ScanItem] { items.filter { matches($0, filter) } }
    func count(_ f: SafetyFilter) -> Int { items.filter { matches($0, f) }.count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FDABannerIfNeeded()
                    if busy, let p = state.cleanProgress[id] { CleaningBanner(progress: p).transition(.opacity.combined(with: .move(edge: .top))) }
                    content
                        .opacity(busy ? 0.45 : 1).allowsHitTesting(!busy)
                        .animation(.easeInOut(duration: 0.2), value: busy)
                }
                .padding(.horizontal, 32).padding(.top, 32).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.results[id] != nil, !items.isEmpty, !scanning { actionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .smooth(phase).smooth(busy).smooth(filter)
        .task {
            guard !scanning else { return }
            // Lần đầu → quét. Vào lại trang mà kết quả trước đó rỗng ("gọn gàng") → quét lại để không hiện kết quả cũ.
            // Có danh sách (hoặc vừa dọn xong) thì giữ nguyên để không mất lựa chọn/tóm tắt.
            if state.results[id] == nil || (items.isEmpty && state.cleanSummary[id] == nil && !state.trashBlocked) {
                await state.scan(id)
            }
        }
        .confirmDialog(isPresented: $confirm, title: confirmTitle, message: confirmMessage,
                       confirmTitle: effectiveMode == .permanent ? tr("Xóa vĩnh viễn") : (effectiveMode == .dryRun ? tr("Xem trước") : tr("Dọn")),
                       destructive: effectiveMode == .permanent, symbol: effectiveMode == .permanent ? "v.trash" : "v.smartScan") {
            Task { await state.clean(id, mode: effectiveMode) }
        }
    }

    @ViewBuilder var content: some View {
        if state.results[id] == nil {
            ScanHero(page: section, title: section.title, subtitle: subtitle + "\n" + tr("Chưa có gì bị xóa cho tới khi bạn xác nhận."),
                     actionTitle: tr("Quét"), busy: scanning, status: state.status[id]) { Task { await state.scan(id) } }
            if section == .devJunk && state.projectRoots.isEmpty && !scanning {
                Text(tr("Mẹo: thêm thư mục project (Cài đặt) để tìm node_modules/vendor/venv của project lâu không dùng."))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity)
            }
        } else if items.isEmpty && section == .trash && state.trashBlocked {
            // Không đọc được Thùng rác ≠ Thùng rác trống.
            FDABanner(message: AppDelegate.canRelaunch
                          ? tr("Không đọc được Thùng rác — hãy cấp Full Disk Access cho Vutidy rồi khởi động lại app.")
                          : AppDelegate.unbundledFDAMessage)
            ScanHero(page: section, title: tr("Chưa thể quét Thùng rác"), subtitle: tr("macOS chặn Vutidy đọc ~/.Trash cho tới khi bạn cấp Full Disk Access."),
                     actionTitle: tr("Quét lại")) { state.checkFDA(); Task { await state.scan(id) } }
        } else if items.isEmpty, let sum = state.cleanSummary[id] {
            CleanDoneHero(page: section, summary: sum,
                          onUndo: sum.mode == .quarantine ? { state.section = .quarantine } : nil,
                          onRescan: { Task { await state.scan(id) } })
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if items.isEmpty {
            ScanHero(page: section, title: tr("Mac của bạn đang gọn gàng"),
                     subtitle: state.lastChecked[id].map { trf("Đã kiểm tra lúc %@ — không có gì để dọn", $0.formatted(date: .omitted, time: .shortened)) } ?? tr("Mục này đang gọn gàng."),
                     actionTitle: tr("Quét lại"), busy: scanning, status: tr("Đang quét…")) { Task { await state.scan(id) } }
        } else {
            if let sum = state.cleanSummary[id] {
                CleanSummaryBanner(summary: sum, onUndo: sum.mode == .quarantine ? { state.section = .quarantine } : nil,
                                   onDismiss: { withAnimation(.easeOut(duration: 0.2)) { state.cleanSummary[id] = nil } })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            PageHeader(caption: subtitle, title: ByteFormat.string(items.reduce(0) { $0 + $1.allocatedSize }) + " · " + section.title,
                       trailing: AnyView(Button { Task { await state.scan(id) } } label: {
                           HStack(spacing: 6) {
                               if scanning { VSpinner(size: 14, lineWidth: 2) } else { Image(systemName: "arrow.clockwise") }
                               Text(scanning ? tr("Đang quét…") : tr("Quét lại"))
                           }
                       }.buttonStyle(SecondaryButtonStyle()).disabled(scanning)))
            HStack {
                ChipPicker(options: SafetyFilter.allCases.map { ($0, "\($0.title)  \(count($0))") }, selection: $filter)
                Spacer()
                let all = selected.count == items.count
                Button {
                    let on = selected.count != items.count
                    for g in groups { state.setGroup(id, category: g.0, selected: on) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: all ? "circle" : "checkmark.circle").font(.system(size: 12, weight: .semibold))
                        Text(all ? tr("Bỏ chọn tất cả") : tr("Chọn tất cả"))
                    }
                }.buttonStyle(PillActionStyle())
            }
            if visible.isEmpty {
                Text(tr("Không có gì để dọn")).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity).padding(40)
            }
            VStack(spacing: 12) {
                ForEach(groups, id: \.0) { cat, gi in groupCard(cat, gi).transition(.opacity.combined(with: .scale(scale: 0.98))) }
            }
            .animation(.easeInOut(duration: 0.35), value: items.map(\.id))
        }
    }

    var subtitle: String {
        switch section {
        case .systemJunk: return tr("Cache, log, preferences hỏng, file đính kèm Mail")
        case .devJunk: return tr("Docker, JetBrains, Node, Go, Xcode, Homebrew, model LLM")
        case .trash: return tr("Thùng rác của bạn và ổ ngoài")
        default: return tr("Cache trình duyệt và dấu vết sử dụng")
        }
    }

    var groups: [(String, [ScanItem])] {
        Dictionary(grouping: visible, by: \.category).map { ($0.key, $0.value) }
            .sorted { $0.1.reduce(0) { $0 + $1.allocatedSize } > $1.1.reduce(0) { $0 + $1.allocatedSize } }
    }

    // MARK: Thẻ danh mục

    func groupCard(_ cat: String, _ gi: [ScanItem]) -> some View {
        let all = gi.allSatisfy(\.selected), some = gi.contains(where: \.selected)
        let size = gi.reduce(0) { $0 + $1.allocatedSize }
        let open = expanded.contains(cat)
        let style = CategoryStyle.style(for: gi)
        let total = max(1, items.reduce(0) { $0 + $1.allocatedSize })
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                VCheckbox(state: all ? .on : (some ? .mixed : .off)) { state.setGroup(id, category: cat, selected: !all) }
                    .accessibilityLabel(cat)
                SolidIcon(symbol: style.symbol, tint: style.tint, size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(cat).font(.vt(size: 14.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                    HStack(spacing: 8) {
                        MeterBar(value: Double(size) / Double(total), color: style.tint, height: 4).frame(width: 90)
                        Text(gi.count == 1 || !some ? trf("%@ mục", "\(gi.count)") : trf("%@ mục · đã chọn %@", "\(gi.count)", "\(gi.filter(\.selected).count)"))
                            .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    }
                }
                Spacer()
                Text(ByteFormat.string(size)).font(.vt(size: 16, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Text.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
            }
            .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
            .onTapGesture { if open { expanded.remove(cat) } else { expanded.insert(cat) } }
            .pointerCursor()
            if open {
                Divider().overlay(Theme.Border.subtle)
                let sorted = gi.sorted { $0.allocatedSize > $1.allocatedSize }
                ForEach(sorted) { i in itemRow(i, parentSize: size, isLast: i.id == sorted.last?.id) }
            }
        }.cardFlat().smooth(open, 0.25)
    }

    func itemRow(_ i: ScanItem, parentSize: Int64, isLast: Bool = false) -> some View {
        let share = Double(i.allocatedSize) / Double(max(1, parentSize))
        return HStack(spacing: 0) {
            Color.clear.frame(width: 22 + 14)                              // thẳng cột với checkbox của hàng cha
            // Checkbox nằm ngay dưới icon của hàng cha → thể hiện cấp bậc mà không cần đường nối.
            ZStack {
                VCheckbox(state: i.selected ? .on : .off) { state.toggle(id, itemID: i.id) }
                    .accessibilityLabel(i.title)
            }.frame(width: 40)
            Color.clear.frame(width: 14)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(i.title).font(.vt(size: 13, weight: .medium)).foregroundStyle(Theme.Text.primary).lineLimit(1)
                        if i.isCLI { Pill(text: "CLI") }
                        if i.safety != .safe { SafetyBadge(level: i.safety) }     // cạnh tên → cột dung lượng luôn thẳng hàng
                    }
                    Text(i.isCLI ? "$ " + i.command!.joined(separator: " ") : i.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.vt(size: 11.5, design: .monospaced)).foregroundStyle(Theme.Text.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                    if let d = i.detail {
                        Label(d, systemImage: "info.circle").font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                // Tỉ trọng của mục trong nhóm + dung lượng; chừa chỗ chevron để thẳng cột với hàng cha.
                MeterBar(value: share, color: CategoryStyle.style(for: [i]).tint.opacity(0.8), height: 3).frame(width: 48)
                Text(ByteFormat.string(i.allocatedSize)).font(.vt(size: 13.5, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.Text.primary).frame(width: 74, alignment: .trailing)
                Color.clear.frame(width: 11)
            }
            .padding(.vertical, 11)
        }
        .padding(.horizontal, 18)
        .background(Color.black.opacity(0.10))
        .contentShape(Rectangle())
        .onTapGesture { state.toggle(id, itemID: i.id) }
        .contextMenu { if !i.isCLI { Button(tr("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([i.url]) } } }
    }

    // MARK: Thanh hành động (ghim đáy)

    var actionBar: some View {
        HStack(spacing: 12) {
            if busy, let p = state.cleanProgress[id] {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        VSpinner(size: 16, lineWidth: 2)
                        Text(tr("Đang dọn…")).font(.vt(size: 15, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                        Text("\(p.done) / \(p.total)").font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.Text.secondary)
                    }
                    MeterBar(value: max(0.04, p.fraction), color: .white, height: 6).frame(width: 260)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Đã chọn")).font(Theme.Font.label).foregroundStyle(Theme.Text.secondary).textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ByteFormat.string(state.selectedBytes(id))).font(.vt(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Text.primary)
                        Text(trf("%@ / %@ mục", "\(selected.count)", "\(items.count)")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    }
                }
            }
            Spacer()
            Button { showCommands.toggle() } label: { Label(tr("Chi tiết lệnh"), systemImage: "terminal") }
                .buttonStyle(TextActionStyle(color: Theme.Text.secondary))
                .popover(isPresented: $showCommands, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("Lệnh sẽ chạy")).font(Theme.Font.heading)
                        CodeBlock(lines: commandPreview).frame(width: 440)
                    }.padding(16)
                }
            if section != .trash { modeMenu.disabled(busy).opacity(busy ? 0.5 : 1) }
            Button {
                if state.confirmBeforeClean { confirm = true } else { Task { await state.clean(id, mode: effectiveMode) } }
            } label: {
                if busy {
                    HStack(spacing: 8) { VSpinner(size: 16, lineWidth: 2); Text(tr("Đang dọn…")) }
                } else {
                    IconLabel(title: effectiveMode == .dryRun ? tr("Xem trước") : trf("Dọn %@", ByteFormat.string(state.selectedBytes(id))),
                              symbol: effectiveMode == .dryRun ? "v.search" : (effectiveMode == .permanent ? "v.trash" : "v.smartScan"))
                }
            }
            .modifier(CleanButtonStyle(danger: effectiveMode == .permanent)).controlSize(.regular).disabled(selected.isEmpty || busy || scanning)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 32).padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.Border.default).frame(height: 1) }
    }

    var modeMenu: some View {
        VSelect(selection: $state.mode,
                options: [CleanMode.quarantine, .moveToTrash, .dryRun].map { ($0, modeTitle($0)) },
                width: 170, symbol: { modeSymbol($0) }, height: 36)
            .help(modeHelp(state.mode))
    }

    func modeTitle(_ m: CleanMode) -> String {
        switch m { case .quarantine: return tr("Quarantine"); case .moveToTrash: return tr("Thùng rác"); case .dryRun: return tr("Chỉ xem trước"); case .permanent: return tr("Xóa vĩnh viễn") }
    }
    func modeSymbol(_ m: CleanMode) -> String {
        switch m { case .quarantine: return "archivebox"; case .moveToTrash: return "trash"; case .dryRun: return "eye"; case .permanent: return "flame" }
    }
    func modeHelp(_ m: CleanMode) -> String {
        switch m {
        case .quarantine: return trf("Khôi phục trong %@ ngày", "\(state.retentionDays)")
        case .moveToTrash: return tr("Dọn bằng Finder")
        case .dryRun: return tr("Không thay đổi gì")
        case .permanent: return tr("Hành động này không thể hoàn tác.")
        }
    }

    var confirmTitle: String { "\(effectiveMode == .dryRun ? tr("Xem trước") : tr("Dọn")) \(ByteFormat.string(state.selectedBytes(id)))?" }
    var confirmMessage: String {
        switch effectiveMode {
        case .quarantine: return trf("Các mục sẽ được chuyển vào Quarantine và khôi phục được trong %@ ngày.", "\(state.retentionDays)")
        case .moveToTrash: return tr("Các mục sẽ được chuyển vào Thùng rác.")
        case .permanent: return tr("Hành động này không thể hoàn tác.")
        case .dryRun: return tr("Chỉ liệt kê, không thay đổi gì.")
        }
    }

    var commandPreview: [String] {
        var lines: [String] = effectiveMode == .dryRun ? [tr("# dry-run: không thay đổi gì")] : []
        let sel = selected
        for i in sel.prefix(6) {
            if let c = i.command { lines.append("$ " + c.joined(separator: " ")) }
            else {
                let p = i.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                switch effectiveMode {
                case .permanent: lines.append("$ rm -rf \(p)")
                case .moveToTrash: lines.append("$ trash \(p)")
                default: lines.append("$ mv \(p) → Quarantine")
                }
            }
        }
        if sel.count > 6 { lines.append(trf("# … và %@ mục khác", "\(sel.count - 6)")) }
        return lines.isEmpty ? [tr("# chưa chọn mục nào")] : lines
    }
}

/// Icon + màu cho từng danh mục, suy ra từ ruleID của mục đầu tiên.
enum CategoryStyle {
    static func style(for items: [ScanItem]) -> (symbol: String, tint: Color) {
        let rid = items.first?.ruleID ?? ""
        let table: [(String, String, Color)] = [
            ("docker", "shippingbox.fill", Theme.Info.base), ("jetbrains", "curlybraces", Theme.apps),
            ("npm", "shippingbox", Theme.Signal.base), ("yarn", "shippingbox", Theme.Signal.base), ("pnpm", "shippingbox", Theme.Signal.base),
            ("stale-project", "folder.badge.minus", Theme.Review.base),
            ("go-", "chevron.left.forwardslash.chevron.right", Theme.teal), ("composer", "shippingbox", Theme.pink),
            ("pip", "chevron.left.forwardslash.chevron.right", Theme.Review.base),
            ("xcode", "hammer.fill", Theme.Info.base), ("homebrew", "cup.and.saucer.fill", Theme.orange),
            ("gradle", "cube.fill", Theme.teal), ("cargo", "gearshape.2.fill", Theme.orange), ("cocoapods", "cube.fill", Theme.pink),
            ("ollama", "brain", Theme.apps), ("huggingface", "brain", Theme.apps),
            ("user-caches", "internaldrive.fill", Theme.Info.base), ("user-logs", "doc.text.fill", Theme.Review.base),
            ("crash", "exclamationmark.triangle.fill", Theme.orange), ("mail", "envelope.fill", Theme.Info.base),
            ("photos", "photo.fill", Theme.pink), ("broken-prefs", "wrench.fill", Theme.Review.base),
            ("chrome", "globe", Theme.Info.base), ("firefox", "flame.fill", Theme.orange), ("arc", "globe", Theme.apps),
            ("safari", "safari.fill", Theme.Info.base), ("recent", "clock.fill", Theme.Review.base),
            ("trash", "trash.fill", Theme.pink),
        ]
        if let hit = table.first(where: { rid.hasPrefix($0.0) || rid.contains($0.0) }) { return (hit.1, hit.2) }
        return ("folder.fill", Theme.Info.base)
    }
}


/// Dọn vĩnh viễn → nút đỏ; còn lại → nút theo màu trang.
struct CleanButtonStyle: ViewModifier {
    let danger: Bool
    func body(content: Content) -> some View {
        if danger { content.buttonStyle(DangerButtonStyle()) } else { content.buttonStyle(PrimaryButtonStyle()) }
    }
}
