import SwiftUI
import CoreKit
import Modules

/// "Giảm nhiệt (Turbo Boost)": chỉ hiện trên Mac Intel. Bật = hạ turbo để máy mát hơn, đổi lại chậm hơn khi tải nặng.
struct TurboBoostCard: View {
    @EnvironmentObject var state: AppState
    @ViewState private var status: TurboBoost.Status?
    @ViewState private var busy = false

    var body: some View {
        Group {
            if let s = status, s.isIntel { card(s) }
        }
        .task { status = await TurboBoost.status() }
    }

    func card(_ s: TurboBoost.Status) -> some View {
        SectionCard(title: tr("Giảm nhiệt (Turbo Boost)"),
                    subtitle: s.turboLimited ? tr("Turbo đang bị hạ: máy mát hơn nhưng chậm hơn khi tải nặng.")
                                             : tr("Turbo Boost đang bật. Hạ turbo giúp Mac Intel bớt nóng và quạt êm hơn."),
                    symbol: "thermometer.medium", tint: Theme.orange,
                    trailing: { if busy { VSpinner(size: 16, lineWidth: 2) } }) {
            if let path = s.kextPath {
                row(title: tr("Tắt Turbo Boost (kext)"),
                    detail: tr("Tắt turbo thật bằng DisableTurboBoost.kext đã cài trên máy. Cần Reduced Security."),
                    isOn: Binding(get: { s.kextLoaded }, set: { v in run { await TurboBoost.setKextLoaded(v, path: path) } }),
                    last: s.lowPowerMode == nil)
            } else {
                Text(tr("Muốn tắt turbo thật: cài Turbo Boost Switcher (kext bên thứ ba, cần Reduced Security) rồi mở lại màn hình này."))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).padding(.horizontal, 16).padding(.vertical, 12)
                Divider().overlay(Theme.Border.subtle)
            }
            if let lpm = s.lowPowerMode {
                row(title: tr("Chế độ Tiết kiệm điện"),
                    detail: tr("Dùng pmset lowpowermode: macOS tự giảm xung nhịp và turbo. Không cần hạ SIP."),
                    isOn: Binding(get: { lpm }, set: { v in run { await TurboBoost.setLowPowerMode(v) } }), last: true)
            } else {
                Text(tr("Máy này không hỗ trợ Chế độ Tiết kiệm điện."))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary).padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .disabled(busy)
    }

    func row(title: String, detail: String, isOn: Binding<Bool>, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.Font.body).foregroundStyle(Theme.Text.primary)
                    Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
                Spacer()
                SwitchRow(isOn: isOn, label: title)
            }.padding(.horizontal, 16).padding(.vertical, 12)
            if !last { Divider().overlay(Theme.Border.subtle) }
        }
    }

    func run(_ op: @escaping () async -> ProcessResult) {
        busy = true
        Task {
            let r = await op()
            if r.status != 0 { state.toast = tr("Không thể đổi cài đặt Turbo Boost.") }
            status = await TurboBoost.status()
            busy = false
        }
    }
}
