import SwiftUI
import AppKit
import CoreKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, cleaning, protection, shortcuts, storage, support
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return tr("Chung"); case .cleaning: return tr("Dọn dẹp"); case .protection: return tr("Bảo vệ")
        case .shortcuts: return tr("Phím tắt"); case .storage: return tr("Lưu trữ"); case .support: return tr("Ủng hộ Vutidy")
        }
    }
    var subtitle: String {
        switch self {
        case .general: return tr("Giao diện và hành vi của ứng dụng.")
        case .cleaning: return tr("Quarantine và thư mục project.")
        case .protection: return tr("Quyền hệ thống và giám sát thời gian thực.")
        case .shortcuts: return tr("Đổi phím tắt để mở nhanh các tính năng.")
        case .storage: return tr("Dữ liệu Vutidy lưu trên máy bạn.")
        case .support: return tr("Vutidy miễn phí, không quảng cáo, không telemetry.")
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"; case .cleaning: return "sparkles"; case .protection: return "shield"
        case .shortcuts: return "command"; case .storage: return "externaldrive"; case .support: return "heart"
        }
    }
    static var groups: [(String, [SettingsPage])] {
        [(tr("Tùy chọn"), [.general, .cleaning, .protection]), (tr("Nâng cao"), [.shortcuts, .storage]), (tr("Trợ giúp"), [.support])]
    }
}

// MARK: - Khối dựng trang cài đặt (theo Vutty: thẻ có tiêu đề in hoa + hàng "tên/mô tả ↔ điều khiển")

struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased()).font(.vt(size: 11, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.Text.tertiary)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                Divider().overlay(Theme.Border.subtle)
            }
            content
        }.cardFlat()
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var desc: String? = nil
    var showDivider = true
    @ViewBuilder var control: Control
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                    if let desc { Text(desc).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 16)
                control
            }.padding(.horizontal, 18).padding(.vertical, 14)
            if showDivider { Divider().overlay(Theme.Border.subtle) }
        }
    }
}

// MARK: - Cửa sổ Settings nổi

struct SettingsOverlay: View {
    @EnvironmentObject var state: AppState
    @ViewState private var maximized = false
    @ViewState private var confirmEmpty = false
    @ViewState private var confirmResetFDA = false

    var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev" }

    var body: some View {
        GeometryReader { geo in
            let w = maximized ? geo.size.width - 24 : min(960, geo.size.width - 80)
            let h = maximized ? geo.size.height - 24 : min(680, geo.size.height - 110)
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { state.settingsOpen = false }
                VStack(spacing: 0) {
                    titleBar
                    Divider().overlay(Theme.Border.default)
                    HStack(spacing: 0) {
                        menu.frame(width: 236)
                        Divider().overlay(Theme.Border.subtle)
                        content
                    }
                }
                .frame(width: w, height: h)
                .background(ZStack { PageBackground(page: state.section); Color.black.opacity(0.46) }.overlay(.ultraThinMaterial.opacity(0.4)))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Border.default))
                .shadow(color: state.section.palette.glow.opacity(0.30), radius: 50, y: 18).shadow(color: .black.opacity(0.55), radius: 36, y: 14)
            }.frame(width: geo.size.width, height: geo.size.height)
        }
        .transition(.opacity)
        .confirmDialog(isPresented: $confirmEmpty, title: tr("Dọn sạch Quarantine?"),
                       message: tr("Mọi mục trong Quarantine sẽ bị xóa vĩnh viễn và không thể khôi phục."),
                       confirmTitle: tr("Xóa vĩnh viễn"), destructive: true, symbol: "v.trash") {
            Task { await emptyQuarantine() }
        }
        .confirmDialog(isPresented: $confirmResetFDA, title: tr("Đặt lại quyền Full Disk Access?"),
                       message: tr("Vutidy sẽ bị gỡ khỏi danh sách Full Disk Access của macOS. Dùng khi quyền bị kẹt hoặc có nhiều dòng Vutidy. Sau đó bạn bật lại quyền theo hướng dẫn."),
                       confirmTitle: tr("Đặt lại và cấp lại"), symbol: "v.protection") {
            Task { await state.resetFullDiskAccess() }
        }
    }

    var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape").foregroundStyle(Theme.Text.secondary)
            Text(tr("Cài đặt")).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
            Spacer()
            Button { maximized.toggle() } label: { Image(systemName: maximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary).help(maximized ? tr("Thu nhỏ") : tr("Phóng to"))
            Button { state.settingsOpen = false } label: { Image(systemName: "xmark") }
                .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary).help(tr("Đóng") + " (Esc)")
        }.padding(.horizontal, 16).frame(height: 44)
    }

    var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(SettingsPage.groups, id: \.0) { name, pages in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name.uppercased()).font(.vt(size: 10.5, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(Theme.Text.tertiary).padding(.horizontal, 12).padding(.bottom, 3)
                            ForEach(pages) { p in menuRow(p) }
                        }
                    }
                }.padding(12)
            }
            Divider().overlay(Theme.Border.subtle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vutidy").font(.vt(size: 12, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                Text(trf("Phiên bản %@", version)).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            }.padding(14)
        }.background(Color.black.opacity(0.20))
    }

    func menuRow(_ p: SettingsPage) -> some View {
        let active = state.settingsPage == p
        return Button { state.settingsPage = p } label: {
            HStack(spacing: 10) {
                if active { SolidIcon(symbol: p.symbol, tint: Theme.Info.base, size: 24) }
                else { Image(systemName: p.symbol).font(.system(size: 13)).frame(width: 24, height: 24).foregroundStyle(Theme.Text.secondary) }
                Text(p.title).font(.vt(size: 13.5, weight: active ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.Text.primary).padding(.horizontal, 8).frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(active ? Theme.Info.base.opacity(0.16) : .clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).pointerCursor().accessibilityAddTraits(active ? .isSelected : [])
    }

    var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.settingsPage.title).font(.vt(size: 26, weight: .bold)).foregroundStyle(Theme.Text.primary)
                    Text(state.settingsPage.subtitle).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
                }
                Divider().overlay(Theme.Border.subtle)
                pageBody.id(state.settingsPage).transition(.opacity)
            }
            .frame(maxWidth: 660, alignment: .leading).padding(.vertical, 28).padding(.horizontal, 32)
            .smooth(state.settingsPage, 0.2)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder var pageBody: some View {
        switch state.settingsPage {
        case .general: general
        case .cleaning: cleaning
        case .protection: protection
        case .shortcuts: ShortcutsEditor()
        case .storage: storage
        case .support: DonateCard()
        }
    }

    func scaleTitle(_ s: Double) -> String {
        switch s {
        case ..<0.95: return tr("Nhỏ")
        case ..<1.05: return tr("Mặc định")
        case ..<1.2: return tr("Lớn")
        default: return tr("Rất lớn")
        }
    }

    // MARK: Chung

    var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            UpdateSettingsGroup()
            SettingsGroup(title: tr("Giao diện")) {
                SettingRow(title: tr("Ngôn ngữ"), desc: tr("Ngôn ngữ của menu, trang và thông báo. Tự động theo ngôn ngữ hệ thống.")) {
                    VSelect(selection: $state.language, options: Language.allCases.map { ($0, $0.menuTitle) }, width: 200)
                }
                SettingRow(title: tr("Phông chữ"), desc: tr("Phông dùng cho toàn bộ giao diện. Mặc định theo phông của hệ thống.")) {
                    VSelect(selection: $state.fontFamily,
                            options: [("", tr("Hệ thống (mặc định)"))] + FontPrefs.families.map { ($0, $0) }, width: 200)
                }
                SettingRow(title: tr("Cỡ chữ"), desc: tr("Phóng to hoặc thu nhỏ toàn bộ chữ trong app.")) {
                    ChipPicker(options: FontPrefs.scales.map { ($0, scaleTitle($0)) }, selection: $state.fontScale)
                }
                SettingRow(title: tr("Giảm chuyển động"), desc: tr("Tắt hiệu ứng động và chuyển cảnh."), showDivider: false) {
                    SwitchRow(isOn: $state.reduceMotion, label: tr("Giảm chuyển động"))
                }
            }
            SettingsGroup(title: tr("Hành vi")) {
                SettingRow(title: tr("Khởi động cùng macOS"), desc: state.canLaunchAtLogin ? tr("Tự mở Vutidy khi bạn đăng nhập vào máy.") : tr("Chỉ khả dụng khi chạy từ file .app.")) {
                    SwitchRow(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }), label: tr("Khởi động cùng macOS"))
                        .disabled(!state.canLaunchAtLogin)
                }
                SettingRow(title: tr("Xác nhận trước khi dọn"), desc: tr("Hỏi lại một lần trước khi dọn các mục đã chọn.")) {
                    SwitchRow(isOn: $state.confirmBeforeClean, label: tr("Xác nhận trước khi dọn"))
                }
                SettingRow(title: tr("Cách dọn mặc định"), desc: tr("Quarantine cho phép hoàn tác; Thùng rác dọn bằng Finder; Xem trước không thay đổi gì.")) {
                    VSelect(selection: $state.defaultMode,
                            options: [(CleanMode.quarantine, tr("Quarantine")), (CleanMode.moveToTrash, tr("Thùng rác")), (CleanMode.dryRun, tr("Chỉ xem trước"))], width: 200)
                }
                SettingRow(title: tr("Bật Real-time Monitor khi mở app"), desc: tr("Theo dõi file mới ở vị trí nhạy cảm ngay khi Vutidy khởi động."), showDivider: false) {
                    SwitchRow(isOn: $state.realtimeAtLaunch, label: tr("Bật Real-time Monitor khi mở app"))
                }
            }
        }
    }

    // MARK: Dọn dẹp

    var cleaning: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: "Quarantine") {
                SettingRow(title: tr("Thời gian giữ"), desc: tr("Số ngày giữ mục đã dọn trước khi xóa hẳn."), showDivider: false) {
                    VStepper(value: $state.retentionDays, range: 1...60) { trf("%@ ngày", "\($0)") }
                }
            }
            SettingsGroup(title: "Dev Junk") {
                SettingRow(title: tr("Project không đổi"), desc: tr("Chỉ gợi ý dọn node_modules/vendor/venv của project không đổi quá số ngày này.")) {
                    VStepper(value: $state.staleProjectDays, range: 7...365, step: 7) { trf("%@ ngày", "\($0)") }
                }
                SettingRow(title: tr("Thư mục project"), desc: tr("Chỉ quét các thư mục bạn chọn, không quét toàn bộ home."), showDivider: !state.projectRoots.isEmpty) {
                    Button(tr("Thêm thư mục…")) {
                        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                        if p.runModal() == .OK, let u = p.url, !state.projectRoots.contains(u.path) { state.projectRoots.append(u.path) }
                    }.buttonStyle(SecondaryButtonStyle())
                }
                ForEach(Array(state.projectRoots.enumerated()), id: \.element) { idx, r in
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.teal)
                            Text(r.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(Theme.Font.mono).foregroundStyle(Theme.Text.primary).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { state.projectRoots.removeAll { $0 == r } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.tertiary).help(tr("Xóa"))
                        }.padding(.horizontal, 18).padding(.vertical, 10)
                        if idx < state.projectRoots.count - 1 { Divider().overlay(Theme.Border.subtle) }
                    }
                }
            }
        }
    }

    // MARK: Bảo vệ

    var protection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: tr("Quyền")) {
                SettingRow(title: "Full Disk Access", desc: tr("Cần để quét Mail, Photos, Safari và iCloud Drive."), showDivider: true) {
                    Pill(text: state.hasFDA ? tr("Đã cấp") : tr("Chưa cấp"), color: state.hasFDA ? Theme.Signal.text : Theme.Review.text)
                }
                // Các nút nằm ở dòng riêng: một hàng nếu đủ chỗ, nếu không tự chia thành hai hàng.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { fdaButtons(first: true); fdaButtons(first: false) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) { fdaButtons(first: true) }
                        HStack(spacing: 10) { fdaButtons(first: false) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 16)
            }
            SettingsGroup(title: "Real-time Monitor") {
                SettingRow(title: tr("Theo dõi file mới"), desc: tr("Chỉ phát hiện sau khi file đã ghi, không chặn thực thi. Đây không phải phần mềm diệt virus."), showDivider: false) {
                    SwitchRow(isOn: Binding(get: { state.realtimeOn }, set: { state.setRealtime($0) }), label: "Real-time Monitor")
                }
            }
        }
    }

    /// Nút của mục Full Disk Access: cấp quyền có hướng dẫn, kiểm tra lại, đặt lại, khởi động lại.
    @ViewBuilder func fdaButtons(first: Bool) -> some View {
        if first {
            if state.hasFDA {
                Button { state.grantFullDiskAccess() } label: { Label(tr("Cấp quyền…"), systemImage: "lock.open") }.buttonStyle(SecondaryButtonStyle())
            } else {
                Button { state.grantFullDiskAccess() } label: { Label(tr("Cấp quyền…"), systemImage: "lock.open") }.buttonStyle(PrimaryButtonStyle())
            }
            Button(tr("Kiểm tra lại")) { state.checkFDA() }.buttonStyle(SecondaryButtonStyle())
        } else {
            Button(tr("Đặt lại quyền")) { confirmResetFDA = true }.buttonStyle(SecondaryButtonStyle())
                .help(tr("Dùng khi Vutidy đã bật nhưng vẫn báo thiếu quyền, hoặc có nhiều dòng Vutidy trong danh sách."))
            if AppDelegate.canRelaunch { Button(tr("Khởi động lại Vutidy")) { AppDelegate.relaunch() }.buttonStyle(SecondaryButtonStyle()) }
        }
    }

    // MARK: Lưu trữ

    var storage: some View {
        let paths = AppPaths.default
        let auditSize = ((try? FileManager.default.attributesOfItem(atPath: paths.auditLog.path)[.size]) as? Int64) ?? 0
        return VStack(alignment: .leading, spacing: 18) {
            SettingsGroup(title: tr("Dữ liệu")) {
                SettingRow(title: tr("Thư mục dữ liệu"), desc: paths.base.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    Button(tr("Hiện trong Finder")) {
                        try? FileManager.default.createDirectory(at: paths.base, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(paths.base)
                    }.buttonStyle(SecondaryButtonStyle(minWidth: 176))
                }
                SettingRow(title: "Quarantine", desc: ByteFormat.string(state.quarantineBytes) + " · " + trf("%@ mục", "\(state.quarantineEntries.count)")) {
                    Button(tr("Dọn sạch Quarantine")) { confirmEmpty = true }.buttonStyle(SecondaryButtonStyle(minWidth: 176)).disabled(state.quarantineEntries.isEmpty)
                }
                SettingRow(title: "Audit log", desc: ByteFormat.string(auditSize) + " · " + paths.auditLog.lastPathComponent) {
                    Button(tr("Hiện trong Finder")) { NSWorkspace.shared.activateFileViewerSelecting([paths.auditLog]) }.buttonStyle(SecondaryButtonStyle(minWidth: 176))
                        .disabled(auditSize == 0)
                }
                SettingRow(title: tr("Rule tùy chỉnh"), desc: tr("Thả file .json vào thư mục này để thêm hoặc ghi đè rule dọn dẹp."), showDivider: false) {
                    Button(tr("Mở thư mục")) {
                        try? FileManager.default.createDirectory(at: paths.userRules, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(paths.userRules)
                    }.buttonStyle(SecondaryButtonStyle(minWidth: 176))
                }
            }
            Label(tr("Không có telemetry. Mọi dữ liệu nằm trên máy bạn."), systemImage: "lock.fill")
                .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
        }
    }

    func emptyQuarantine() async {
        for e in state.quarantineEntries { await state.executor.quarantine.purge(e.id) }
        await state.refreshQuarantine()
        state.toast = tr("Đã dọn sạch Quarantine.")
    }
}

// MARK: - Trang Phím tắt (theo Vutty: key cap bấm để đổi, Reset, cảnh báo trùng, nhóm "Cố định")

struct ShortcutsEditor: View {
    @EnvironmentObject var store: ShortcutStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text(tr("Bấm vào phím tắt rồi nhấn tổ hợp mới. Nhấn Esc để hủy. Cần ⌘, ⌥ hoặc ⌃ (phím F được phép)."))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button(tr("Đặt lại tất cả")) { store.resetAll() }.buttonStyle(SecondaryButtonStyle())
            }
            if let m = store.message {
                Label(m, systemImage: "exclamationmark.triangle.fill").font(Theme.Font.caption).foregroundStyle(Theme.Review.text)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.Review.tint))
            }
            ForEach([ShortcutAction.Group.navigation, .actions], id: \.rawValue) { g in
                let rows = store.actions.filter { $0.group == g }
                SettingsGroup(title: g.title) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, a in
                        SettingRow(title: a.title, showDivider: idx < rows.count - 1) { control(a) }
                    }
                }
            }
            SettingsGroup(title: tr("Cố định")) {
                SettingRow(title: tr("Dọn các mục đã chọn")) { KeyCaps(symbols: ["⌘", "↩"]) }
                SettingRow(title: tr("Đóng bảng, menu hoặc cửa sổ"), showDivider: false) { KeyCaps(symbols: ["Esc"]) }
            }
        }
    }

    func control(_ a: ShortcutAction) -> some View {
        let recording = store.recordingID == a.id
        return HStack(spacing: 10) {
            Button {
                store.message = nil
                store.recordingID = recording ? nil : a.id
            } label: {
                if recording {
                    Text(tr("Nhấn phím…")).font(.vt(size: 12, weight: .semibold)).foregroundStyle(Theme.Info.text)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.Info.base.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.Info.base))
                } else {
                    KeyCaps(symbols: store.combo(a).symbols, highlighted: store.isCustom(a))
                }
            }.buttonStyle(PlainPointerStyle())
            if store.isCustom(a) { Button(tr("Đặt lại")) { store.reset(a) }.buttonStyle(TextActionStyle()) }
        }
    }
}
