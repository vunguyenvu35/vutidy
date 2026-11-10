import SwiftUI
import AppKit
import CoreKit

/// Tổ hợp phím lưu theo keyCode (không phụ thuộc bố cục bàn phím) + bitmask modifier.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var mods: UInt8

    static let cmd: UInt8 = 1, shift: UInt8 = 2, option: UInt8 = 4, control: UInt8 = 8

    static let labels: [UInt16: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
        45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
        36: "↩", 76: "↩", 48: "⇥", 49: "Space", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    static let fKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    init(_ keyCode: UInt16, _ mods: UInt8 = KeyCombo.cmd) { self.keyCode = keyCode; self.mods = mods }

    init?(event: NSEvent) {
        var m: UInt8 = 0
        let f = event.modifierFlags
        if f.contains(.command) { m |= Self.cmd }
        if f.contains(.shift) { m |= Self.shift }
        if f.contains(.option) { m |= Self.option }
        if f.contains(.control) { m |= Self.control }
        guard Self.labels[event.keyCode] != nil else { return nil }
        self.init(event.keyCode, m)
    }

    var symbols: [String] {
        var s: [String] = []
        if mods & Self.control != 0 { s.append("⌃") }
        if mods & Self.option != 0 { s.append("⌥") }
        if mods & Self.shift != 0 { s.append("⇧") }
        if mods & Self.cmd != 0 { s.append("⌘") }
        s.append(Self.labels[keyCode] ?? "?")
        return s
    }
    var display: String { symbols.joined(separator: " ") }

    /// Phím thường không có ⌘/⌥/⌃ bị từ chối (trừ phím F).
    var isAcceptable: Bool { mods & (Self.cmd | Self.option | Self.control) != 0 || Self.fKeys.contains(keyCode) }

    /// Những tổ hợp macOS giữ cho hệ thống.
    var isReserved: Bool {
        let reserved: [KeyCombo] = [KeyCombo(12), KeyCombo(13), KeyCombo(4), KeyCombo(46), KeyCombo(48), KeyCombo(49),
                                    KeyCombo(4, KeyCombo.cmd | KeyCombo.option), KeyCombo(12, KeyCombo.cmd | KeyCombo.shift)]
        return reserved.contains(self)
    }
}

struct ShortcutAction: Identifiable, Hashable {
    enum Group: String { case navigation = "Điều hướng", actions = "Thao tác"; var title: String { tr(rawValue) } }
    let id: String
    let group: Group
    let page: Page?
    let titleKey: String
    let defaultCombo: KeyCombo
    let symbol: String

    var title: String { page.map { trf("Mở %@", $0.title) } ?? tr(titleKey) }

    static let pageCombos: [(Page, KeyCombo)] = [
        (.smartScan, KeyCombo(18)), (.systemJunk, KeyCombo(19)), (.devJunk, KeyCombo(20)), (.trash, KeyCombo(21)),
        (.privacy, KeyCombo(23)), (.protection, KeyCombo(22)), (.optimization, KeyCombo(26)), (.maintenance, KeyCombo(28)),
        (.uninstaller, KeyCombo(25)), (.malware, KeyCombo(46, KeyCombo.cmd | KeyCombo.shift)),
        (.updater, KeyCombo(32, KeyCombo.cmd | KeyCombo.shift)), (.spaceLens, KeyCombo(37, KeyCombo.cmd | KeyCombo.shift)),
        (.largeFiles, KeyCombo(3, KeyCombo.cmd | KeyCombo.shift)), (.duplicates, KeyCombo(2, KeyCombo.cmd | KeyCombo.shift)),
        (.cloud, KeyCombo(8, KeyCombo.cmd | KeyCombo.shift)), (.quarantine, KeyCombo(16, KeyCombo.cmd | KeyCombo.shift)),
    ]

    static var all: [ShortcutAction] {
        let pages = pageCombos.map { ShortcutAction(id: "go.\($0.0.rawValue)", group: .navigation, page: $0.0, titleKey: "", defaultCombo: $0.1, symbol: $0.0.icon) }
        let actions = [
            ShortcutAction(id: "quickOpen", group: .actions, page: nil, titleKey: "Mở nhanh (tìm tính năng)", defaultCombo: KeyCombo(40), symbol: "magnifyingglass"),
            ShortcutAction(id: "scanCurrent", group: .actions, page: nil, titleKey: "Quét lại trang hiện tại", defaultCombo: KeyCombo(15), symbol: "arrow.clockwise"),
            ShortcutAction(id: "toggleRealtime", group: .actions, page: nil, titleKey: "Bật/tắt Real-time Monitor", defaultCombo: KeyCombo(15, KeyCombo.cmd | KeyCombo.shift), symbol: "dot.radiowaves.left.and.right"),
            ShortcutAction(id: "openSettings", group: .actions, page: nil, titleKey: "Mở Cài đặt", defaultCombo: KeyCombo(43), symbol: "gearshape"),
        ]
        return pages + actions
    }
}

/// Lưu và tra cứu phím tắt. Chỉ lưu phần người dùng đã đổi; phần còn lại dùng mặc định.
@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var overrides: [String: KeyCombo]
    @Published var recordingID: String?
    @Published var message: String?
    let actions = ShortcutAction.all
    private let defaults: UserDefaults
    private let key = "vutidy.shortcuts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let d = defaults.data(forKey: key), let o = try? JSONDecoder().decode([String: KeyCombo].self, from: d) { overrides = o } else { overrides = [:] }
    }

    func combo(_ a: ShortcutAction) -> KeyCombo { overrides[a.id] ?? a.defaultCombo }
    func combo(forPage p: Page) -> KeyCombo? { actions.first { $0.page == p }.map(combo) }
    func isCustom(_ a: ShortcutAction) -> Bool { overrides[a.id] != nil && overrides[a.id] != a.defaultCombo }
    func action(for c: KeyCombo) -> ShortcutAction? { actions.first { combo($0) == c } }

    private func persist() { defaults.set(try? JSONEncoder().encode(overrides), forKey: key) }

    /// Gán phím mới. Trả về false và đặt `message` nếu bị từ chối.
    @discardableResult
    func assign(_ c: KeyCombo, to a: ShortcutAction) -> Bool {
        guard c.isAcceptable else { message = tr("Cần thêm ⌘, ⌥ hoặc ⌃ (phím F được phép)."); return false }
        guard !c.isReserved else { message = tr("Tổ hợp này do macOS giữ."); return false }
        if let owner = action(for: c), owner.id != a.id { message = trf("Đã được dùng cho “%@”.", owner.title); return false }
        overrides[a.id] = c == a.defaultCombo ? nil : c
        persist(); message = nil
        return true
    }

    func record(_ c: KeyCombo) {
        guard let id = recordingID, let a = actions.first(where: { $0.id == id }) else { return }
        if assign(c, to: a) { recordingID = nil }
    }

    func reset(_ a: ShortcutAction) { overrides[a.id] = nil; persist(); message = nil }
    func resetAll() { overrides = [:]; persist(); message = nil; recordingID = nil }
}

// MARK: - Giao diện key cap

struct KeyCaps: View {
    let symbols: [String]
    var highlighted = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, s in
                Text(s).font(.vt(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(highlighted ? Theme.Info.text : Theme.Text.primary)
                    .frame(minWidth: 24, minHeight: 24).padding(.horizontal, s.count > 1 ? 6 : 0)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(LinearGradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(highlighted ? Theme.Info.base : Color.white.opacity(0.28)))
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(symbols.joined(separator: " "))
    }
}

