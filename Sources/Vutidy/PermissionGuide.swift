import SwiftUI
import AppKit
import CoreKit

/// Luồng cấp lại Full Disk Access có hướng dẫn (như CleanMyMac): mở System Settings, hiện một bảng nổi ngay cạnh đó với
/// biểu tượng Vutidy để kéo vào danh sách, tự phát hiện khi quyền đã được cấp, và có nút đặt lại quyền khi nó bị kẹt.
@MainActor
final class PermissionGuide {
    static let shared = PermissionGuide()
    private var panel: NSPanel?
    private var poll: Task<Void, Never>?

    static let fdaURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    func show(state: AppState, openSettings: Bool = true) {
        guard AppDelegate.canRelaunch else { state.notify(AppDelegate.unbundledFDAMessage, .warning); return }
        if openSettings { NSWorkspace.shared.open(Self.fdaURL) }
        if panel == nil {
            let host = NSHostingView(rootView: PermissionGuideView(close: { [weak self] in self?.close() })
                .environmentObject(state).preferredColorScheme(.dark))
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: 500, height: 250)),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.contentView = host
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .floating; p.isFloatingPanel = true; p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        if let p = panel, let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - p.frame.width / 2, y: f.minY + 60))
            p.orderFrontRegardless()
        }
        poll?.cancel()
        poll = Task { @MainActor [weak self] in
            // macOS cập nhật quyền ngay khi bạn bật công tắc; hỏi lại mỗi giây cho đến khi thấy.
            while !Task.isCancelled {
                state.checkFDA()
                if state.hasFDA { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self?.panel == nil { return }
            }
        }
    }

    func close() {
        poll?.cancel(); poll = nil
        panel?.orderOut(nil); panel = nil
    }

    /// Xóa quyền đã lưu của Vutidy (`tccutil reset`) — dùng khi quyền bị kẹt hoặc danh sách có nhiều dòng Vutidy lẫn lộn.
    static func resetFullDiskAccess() async -> ProcessResult {
        let id = Bundle.main.bundleIdentifier ?? "com.vutidy.app"
        return await ProcessRunner.run(["tccutil", "reset", "SystemPolicyAllFiles", id], timeout: 15)
    }
}

struct PermissionGuideView: View {
    @EnvironmentObject var state: AppState
    let close: () -> Void
    @ViewState private var resetting = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: state.hasFDA ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 18)).foregroundStyle(state.hasFDA ? Theme.Signal.base : Theme.Review.base)
                Text(state.hasFDA ? tr("Đã cấp quyền!") : tr("Cho phép Full Disk Access"))
                    .font(.vt(size: 16, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary)
            }

            if state.hasFDA {
                Text(tr("Khởi động lại Vutidy để macOS áp dụng hoàn toàn quyền mới."))
                    .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    Button(tr("Khởi động lại Vutidy")) { AppDelegate.relaunch() }.buttonStyle(PrimaryButtonStyle()).controlSize(.small)
                    Button(tr("Xong")) { close() }.buttonStyle(SecondaryButtonStyle()).controlSize(.small)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        step("1", tr("Trong danh sách của System Settings, bật công tắc Vutidy."))
                        step("2", tr("Chưa thấy Vutidy? Kéo biểu tượng bên cạnh vào danh sách."))
                        step("3", tr("Nhập mật khẩu hoặc dùng Touch ID nếu macOS hỏi."))
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 5) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path))
                            .resizable().frame(width: 56, height: 56)
                            .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                            .help(tr("Kéo biểu tượng này vào danh sách"))
                        Text("Vutidy").font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                    }
                }
                HStack(spacing: 8) {
                    VSpinner(size: 13, lineWidth: 2)
                    Text(tr("Đang chờ bạn cấp quyền…")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).lineLimit(1).fixedSize()
                    Spacer()
                    Button(tr("Đặt lại quyền")) { reset() }.buttonStyle(TextActionStyle(color: Theme.Text.secondary)).disabled(resetting)
                        .help(tr("Dùng khi Vutidy đã bật nhưng vẫn báo thiếu quyền, hoặc có nhiều dòng Vutidy trong danh sách."))
                    Button(tr("Khởi động lại Vutidy")) { AppDelegate.relaunch() }.buttonStyle(TextActionStyle(color: Theme.Text.secondary))
                }
            }
        }
        .padding(18).frame(width: 500)
        .background(Color(white: 0.11).opacity(0.97))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.vt(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.white.opacity(0.16)))
            Text(text).font(Theme.Font.body).foregroundStyle(Theme.Text.primary).fixedSize(horizontal: false, vertical: true)
        }
    }

    func reset() {
        resetting = true
        Task {
            let r = await PermissionGuide.resetFullDiskAccess()
            resetting = false
            if r.ok {
                state.checkFDA()
                state.notify(tr("Đã đặt lại quyền. Hãy bật lại Vutidy trong System Settings."))
                NSWorkspace.shared.open(PermissionGuide.fdaURL)
            } else {
                state.notify(trf("Không đặt lại được quyền: %@", r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)), .warning)
            }
        }
    }
}

extension AppState {
    func grantFullDiskAccess() { PermissionGuide.shared.show(state: self) }

    /// Đặt lại quyền Full Disk Access (sau khi hỏi xác nhận), rồi mở hướng dẫn cấp lại.
    func resetFullDiskAccess() async {
        let r = await PermissionGuide.resetFullDiskAccess()
        checkFDA()
        if r.ok {
            notify(tr("Đã đặt lại quyền. Hãy bật lại Vutidy trong System Settings."))
            grantFullDiskAccess()
        } else {
            notify(trf("Không đặt lại được quyền: %@", r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)), .warning)
        }
    }
}
