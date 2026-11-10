import SwiftUI
import CoreKit

struct RootView: View {
    @EnvironmentObject var state: AppState

    /// Các trang tự quản lý cuộn để ghim thanh hành động ở đáy cửa sổ.
    var ownsScroll: Bool { [.systemJunk, .devJunk, .trash, .privacy, .spaceLens].contains(state.section) }

    var body: some View {
        ZStack(alignment: .top) {
        WindowBackground(current: state.section)
        HStack(spacing: 0) {
            Sidebar().frame(width: Theme.Layout.sidebarWidth + 16)
            VStack(spacing: 0) {
                if ownsScroll {
                    pageContent
                } else {
                    GeometryReader { geo in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                FDABannerIfNeeded()
                                pageContent
                            }
                            // Nội dung luôn cao ít nhất bằng cửa sổ để hero có thể giãn, không để trống phía dưới.
                            .frame(maxWidth: .infinity, minHeight: max(0, geo.size.height - 52), alignment: .topLeading)
                            .padding(.horizontal, 28).padding(.bottom, 20).padding(.top, 32)
                        }
                    }
                }
            }
        }
        }
        .background(Color.black)
        .environment(\.currentPage, state.section)
        .background(WindowConfigurator(onTitleBarCenter: { state.titleBarCenter = $0 }, onFullScreen: { state.isFullScreen = $0 }))
        .overlay(alignment: .topLeading) {
            // Dải tiêu đề phía trên vùng nội dung: kéo cửa sổ, double-click để phóng to/thu nhỏ.
            TitleBarArea().frame(height: 28).padding(.leading, Theme.Layout.sidebarWidth + 16)
        }
        .overlay(alignment: .bottomTrailing) { ToastStack() }
        .overlay { if state.settingsOpen { SettingsOverlay() } }
        .overlay { if state.paletteOpen { CommandPalette() } }
        .overlay { if let req = state.confirmRequest { ConfirmDialogView(request: req) } }
        .animation(.easeOut(duration: 0.18), value: state.confirmRequest != nil)
        .animation(.easeOut(duration: 0.2), value: state.settingsOpen)
        .animation(.easeOut(duration: 0.16), value: state.paletteOpen)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: state.toasts.map(\.id))
        .animation(.easeInOut(duration: 0.24), value: state.section)
        .transaction { t in if state.reduceMotion { t.animation = nil } }
        .id("\(state.language)|\(state.typographyKey)")
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Mỗi trang có `id` riêng để SwiftUI cross-fade giữa hai trang (và chạy lại `.task` khi đổi mục).
    var pageContent: some View { detail.id(state.section).transition(.opacity) }

    @ViewBuilder var detail: some View {
        switch state.section {
        case .smartScan: SmartScanView()
        case .systemJunk, .devJunk, .trash, .privacy: CleanupView(section: state.section)
        case .protection: ProtectionView()
        case .malware: MalwareView()
        case .optimization: OptimizationView()
        case .maintenance: MaintenanceView()
        case .uninstaller: UninstallerView()
        case .updater: UpdaterView()
        case .spaceLens: SpaceLensView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .cloud: CloudView()
        case .quarantine: QuarantineView()
        }
    }
}

/// Banner thiếu Full Disk Access: chỉ hiện ở trang cần quyền này và có thể ẩn.
struct FDABannerIfNeeded: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if !state.hasFDA && !state.fdaDismissed && [.smartScan, .systemJunk, .privacy, .cloud, .spaceLens].contains(state.section) {
            FDABanner(message: AppDelegate.canRelaunch
                          ? tr("Thiếu Full Disk Access — một số mục (Mail, Photos, Safari) sẽ không quét được.")
                          : AppDelegate.unbundledFDAMessage,
                      onDismiss: { state.fdaDismissed = true })
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo nằm cùng hàng với 3 nút đèn giao thông → không tốn thêm chiều cao.
            HStack(spacing: 8) {
                Spacer().frame(width: state.isFullScreen ? 0 : 82)   // full screen không có 3 nút đèn giao thông
                LogoMark(size: 22)
                Text("Vutidy").font(.vt(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.Text.primary)
                Spacer(minLength: 0)
            }
            .frame(height: state.titleBarCenter * 2)                 // tâm hàng = tâm 3 nút đèn giao thông
            .background(TitleBarArea())

            Button { state.paletteOpen = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12))
                    Text(tr("Tìm tính năng…")).font(.vt(size: 12.5)).lineLimit(1)
                    Spacer(minLength: 0)
                    KeyCaps(symbols: ["⌘", "K"])
                }
                .foregroundStyle(Theme.Text.secondary).padding(.horizontal, 10).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.10)))
            }.buttonStyle(PlainPointerStyle()).padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
            .help(tr("Mở nhanh (tìm tính năng)"))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Page.groups, id: \.0) { name, items in
                        VStack(alignment: .leading, spacing: 1) {
                            if !name.isEmpty {
                                Text(name.uppercased()).font(.vt(size: 10.5, weight: .semibold)).tracking(0.6)
                                    .foregroundStyle(Theme.Text.tertiary).padding(.horizontal, 12).padding(.bottom, 2)
                            }
                            ForEach(items) { s in NavRow(section: s) }
                        }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }

            UpdateBadgeCard()
            QuarantineCard().padding(.horizontal, 12).padding(.top, 6)
            footer.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.30))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
    }

    /// Ngôn ngữ · Real-time · Cài đặt (trước đây nằm ở thanh trên cùng).
    var footer: some View {
        HStack(spacing: 12) {
            LanguageMenu()
            Spacer(minLength: 0)
            Button { state.setRealtime(!state.realtimeOn) } label: {
                HStack(spacing: 5) {
                    Circle().fill(state.realtimeOn ? Theme.Signal.base : Theme.Text.tertiary).frame(width: 7, height: 7)
                    Text("Real-time").font(Theme.Font.label)
                }.foregroundStyle(Theme.Text.secondary)
            }.buttonStyle(PlainPointerStyle())
            .help(state.realtimeOn ? tr("Real-time bật") : tr("Real-time tắt"))
            Button { state.openSettings(.general) } label: {
                Image(systemName: "gearshape").font(.system(size: 14))
                    .overlay(alignment: .topTrailing) { if state.hasUpdate { Circle().fill(Theme.Signal.base).frame(width: 7, height: 7).offset(x: 3, y: -3) } }
            }
                .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary).help(tr("Mở Cài đặt") + " (⌘,)")
        }
    }
}

struct NavRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: ShortcutStore
    let section: Page
    @ViewState private var hover = false

    var body: some View {
        let active = state.section == section
        Button { state.section = section } label: {
            HStack(spacing: 11) {
                SolidIcon(symbol: section.icon, tint: section.tint, size: 24)
                Text(section.title).font(.vt(size: 13.5, weight: active ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
                if let cid = section.cleanupID, state.cleaning.contains(cid) || state.scanning.contains(cid) {
                    VSpinner(size: 13, lineWidth: 2)
                } else if hover, let c = store.combo(forPage: section) {
                    Text(c.display.replacingOccurrences(of: " ", with: "")).font(.vt(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.Text.tertiary)
                }
            }
            .foregroundStyle(active ? Theme.Text.primary : Theme.Text.primary.opacity(0.86))
            .padding(.horizontal, 10).frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Color.white.opacity(0.18) : (hover ? Color.white.opacity(0.08) : .clear)))
            .animation(.easeOut(duration: 0.14), value: active)
            .animation(.easeOut(duration: 0.12), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPointerStyle()).onHover { hover = $0 }
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct QuarantineCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Button { state.section = .quarantine } label: {
            HStack(spacing: 12) {
                SolidIcon(symbol: "archivebox.fill", tint: Theme.Signal.base, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Quarantine").font(.vt(size: 13, weight: .semibold))
                    Text(ByteFormat.string(state.quarantineBytes) + " · " + trf("%@ mục", "\(state.quarantineEntries.count)"))
                        .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.Text.tertiary)
            }
            .foregroundStyle(Theme.Text.primary).padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Border.subtle))
        }.buttonStyle(PlainPointerStyle())
    }
}

enum ToastKind {
    case success, warning, error
    var icon: String {
        switch self {
        case .success: return "checkmark"
        case .warning: return "exclamationmark"
        case .error: return "xmark"
        }
    }
    var color: Color {
        switch self {
        case .success: return Theme.Signal.base
        case .warning: return Theme.Review.base
        case .error: return Theme.danger
        }
    }
    /// Lỗi tồn tại lâu hơn để kịp đọc.
    var duration: Double { self == .error ? 10 : 5 }
}

/// Chồng thông báo ở góc phải-dưới: thông báo mới bay lên từ phía dưới, các thông báo cũ được đẩy dần lên trên.
/// Mỗi thông báo tự đếm ngược riêng (dừng khi rê chuột vào) và trượt sang phải khi biến mất.
struct ToastStack: View {
    @EnvironmentObject var state: AppState

    /// Trang dọn dẹp có thanh hành động ghim ở đáy (nút Dọn nằm bên phải) → đẩy chồng thông báo lên trên thanh đó.
    private var bottomInset: CGFloat {
        if state.pinnedBarVisible { return 88 }
        guard let id = state.section.cleanupID else { return 16 }
        let hasBar = !(state.results[id] ?? []).isEmpty && !state.scanning.contains(id)
        return hasBar ? 88 : 16
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            ForEach(state.toasts) { t in
                ToastCard(toast: t)
                    .transition(.asymmetric(
                        insertion: .modifier(active: ToastRise(y: 80, opacity: 0), identity: ToastRise(y: 0, opacity: 1)),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .padding(.trailing, 20).padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!state.toasts.isEmpty)
    }
}

private struct ToastRise: ViewModifier {
    let y: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.offset(y: y).opacity(opacity) }
}

/// Một thông báo: huy hiệu theo loại, tiêu đề + chi tiết (tách ở " · "), nút Hoàn tác khi áp dụng, thanh đếm ngược.
private struct ToastCard: View {
    @EnvironmentObject var state: AppState
    let toast: AppToast
    @ViewState private var hovering = false
    @ViewState private var progress: CGFloat = 1

    var body: some View {
        let kind = toast.kind
        let parts = toast.text.components(separatedBy: " · ")
        let title = parts.first ?? toast.text
        let detail = parts.dropFirst().joined(separator: " · ")
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(kind.color.opacity(0.18))
                Image(systemName: kind.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(kind.color)
            }.frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.vt(size: 13.5, weight: .semibold)).foregroundStyle(Theme.Text.primary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !detail.isEmpty {
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)

            if toast.action == .openUpdate {
                Button(tr("Cập nhật ngay")) { state.openSettings(.general); state.dismissToast(toast.id) }
                    .buttonStyle(TextActionStyle(color: kind.color))
            }
            if toast.undo {
                Button(tr("Hoàn tác")) { state.section = .quarantine; state.dismissToast(toast.id) }
                    .buttonStyle(TextActionStyle(color: kind.color))
            }
            Button { state.dismissToast(toast.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.tertiary)
            .help(tr("Đóng"))
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 12)
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.25)))
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Capsule().fill(kind.color.opacity(0.55)).frame(width: geo.size.width * progress, height: 2)
            }.frame(height: 2).padding(.horizontal, 14).padding(.bottom, 1)
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Border.default))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .onHover { hovering = $0 }
        .task(id: toast.id) { await countdown(duration: kind.duration) }
        .accessibilityElement(children: .combine)
    }

    /// Đếm ngược 100ms/bước; tạm dừng khi chuột đang ở trên thông báo này.
    private func countdown(duration: Double) async {
        progress = 1
        var left = duration
        while left > 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if Task.isCancelled { return }
            if !hovering { left -= 0.1; progress = max(0, CGFloat(left / duration)) }
        }
        state.dismissToast(toast.id)
    }
}
