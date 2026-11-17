import SwiftUI
import AppKit
import CoreKit

/// Nút thu nhỏ/đóng của Settings khi nó phóng to sát mép trên cửa sổ.
/// Vùng thanh tiêu đề (toolbar unified) nhận click trước nội dung SwiftUI nên nút đặt trong đó không bấm được;
/// đưa chúng vào chính thanh tiêu đề dưới dạng accessory (NSView thật) thì vừa đúng chỗ vừa nhận click.
/// NSHostingView tự đặt con trỏ bàn tay: trong thanh tiêu đề, `pointerStyle` của SwiftUI không có tác dụng.
final class HandCursorHostingView: NSHostingView<AnyView> {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func layout() { super.layout(); window?.invalidateCursorRects(for: self) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
}

struct TitlebarControls: NSViewRepresentable {
    var active: Bool
    var maximized: Bool
    var toggle: () -> Void
    var close: () -> Void

    final class Coordinator {
        var accessory: NSTitlebarAccessoryViewController?
        weak var window: NSWindow?
        func remove() {
            guard let a = accessory else { return }
            if let w = window, let i = w.titlebarAccessoryViewControllers.firstIndex(of: a) { w.removeTitlebarAccessoryViewController(at: i) }
            accessory = nil
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    private var content: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                Image(systemName: maximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }.help(maximized ? tr("Thu nhỏ") : tr("Phóng to"))
            Button(action: close) { Image(systemName: "xmark") }.help(tr("Đóng") + " (Esc)")
        }
        .buttonStyle(PlainPointerStyle()).foregroundStyle(Theme.Text.secondary)
        .padding(.horizontal, 16).frame(maxHeight: .infinity)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let c = context.coordinator
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            c.window = window
            guard active else { c.remove(); return }
            if let a = c.accessory, let host = a.view as? HandCursorHostingView {
                host.rootView = AnyView(content)
                return
            }
            let host = HandCursorHostingView(rootView: AnyView(content))
            host.frame.size = NSSize(width: 84, height: 28)
            let a = NSTitlebarAccessoryViewController()
            a.view = host
            a.layoutAttribute = .trailing
            window.addTitlebarAccessoryViewController(a)
            c.accessory = a
        }
    }
}
