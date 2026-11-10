import SwiftUI
import CoreKit

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let tint: Color
    let shortcut: [String]
    let group: String
    let run: () -> Void
}

/// Mở nhanh (⌘K): kính mờ phủ gradient của trang hiện tại, hàng chọn tô theo màu mục.
struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: ShortcutStore
    @FocusState private var focused: Bool

    var body: some View {
        let page = state.section
        let items = state.paletteItems
        ZStack(alignment: .top) {
            Color.black.opacity(0.42).ignoresSafeArea().onTapGesture { state.paletteOpen = false }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.Text.secondary)
                    TextField(tr("Tìm tính năng…"), text: $state.paletteQuery).textFieldStyle(.plain).font(.vt(size: 19))
                        .foregroundStyle(.white).focused($focused).onChange(of: state.paletteQuery) { _ in state.paletteIndex = 0 }
                    KeyCaps(symbols: ["esc"])
                }.padding(.horizontal, 20).frame(height: 62)
                Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            if items.isEmpty {
                                Text(tr("Không có kết quả")).font(Theme.Font.body).foregroundStyle(Theme.Text.secondary)
                                    .frame(maxWidth: .infinity).padding(36)
                            }
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                                if i == 0 || items[i - 1].group != it.group {
                                    Text(it.group.uppercased()).font(.vt(size: 10.5, weight: .semibold)).tracking(0.7)
                                        .foregroundStyle(Theme.Text.tertiary).padding(.horizontal, 12).padding(.top, i == 0 ? 4 : 12).padding(.bottom, 4)
                                }
                                row(it, selected: i == state.paletteIndex).id(i)
                                    .onTapGesture { state.paletteIndex = i; state.runPaletteSelection() }
                                    .pointerCursor()
                            }
                        }.padding(10)
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: state.paletteIndex) { i in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(i, anchor: .center) } }
                }
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1)
                HStack(spacing: 16) {
                    hint(["↑", "↓"], tr("Di chuyển")); hint(["↩"], tr("Mở")); hint(["esc"], tr("Đóng"))
                    Spacer()
                    Text("\(items.count)").font(Theme.Font.caption).monospacedDigit().foregroundStyle(Theme.Text.tertiary)
                }.padding(.horizontal, 18).frame(height: 38).background(Color.black.opacity(0.14))
            }
            .frame(width: 620)
            .background(ZStack { PageBackground(page: page); Color.black.opacity(0.34) }.overlay(.ultraThinMaterial.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: page.palette.glow.opacity(0.35), radius: 50, y: 18)
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
            .padding(.top, 84)
        }
        .onAppear { focused = true }
        .transition(.opacity)
    }

    func row(_ it: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 14) {
            SolidIcon(symbol: it.symbol, tint: it.tint, size: 30)
            Text(it.title).font(.vt(size: 14.5, weight: selected ? .semibold : .medium)).foregroundStyle(.white)
            Spacer()
            if !it.shortcut.isEmpty { KeyCaps(symbols: it.shortcut) }
        }
        .padding(.horizontal, 10).frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? LinearGradient(colors: [it.tint.opacity(0.42), it.tint.opacity(0.14)], startPoint: .leading, endPoint: .trailing)
                               : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Color.white.opacity(0.28) : .clear))
        .contentShape(Rectangle())
    }

    func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 6) { KeyCaps(symbols: keys); Text(label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary) }
    }
}
