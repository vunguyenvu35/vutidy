import SwiftUI
import CoreKit
import Modules

extension AppState {
    /// Gọi mỗi lần đo hệ thống. Chỉ khi pin xả và sắp hết mới đi liệt kê tiến trình (tối đa mỗi 60 giây).
    func checkBatteryDrain(_ s: SystemSnapshot, now: Date = Date()) {
        guard BatteryDrain.isLow(s.battery) else {
            if !batteryDrainApps.isEmpty { batteryDrainApps = [] }
            UserDefaults.standard.removeObject(forKey: "batteryDrainNotifiedAt")
            return
        }
        guard !batteryDrainChecking, now.timeIntervalSince(batteryDrainCheckedAt ?? .distantPast) >= 60 else { return }
        batteryDrainChecking = true; batteryDrainCheckedAt = now
        let battery = s.battery
        Task { @MainActor [weak self] in
            let top = await BatteryDrain.topConsumers()
            guard let self else { return }
            self.batteryDrainChecking = false
            let alert = BatteryDrain.shouldAlert(battery, consumers: top)
            self.batteryDrainApps = alert ? top.filter { $0.cpu >= BatteryDrain.minCPU / 2 } : []
            if alert { self.notifyBatteryDrainIfNeeded(minutes: battery?.minutesRemaining ?? 0, apps: self.batteryDrainApps) }
        }
    }

    /// Báo (toast + thông báo hệ thống) tối đa một lần mỗi 2 giờ cho mỗi lần rút sạc.
    func notifyBatteryDrainIfNeeded(minutes: Int, apps: [BatteryDrain.Consumer], now: Date = Date()) {
        guard notifyBatteryDrain, !apps.isEmpty else { return }
        let d = UserDefaults.standard
        if let at = d.object(forKey: "batteryDrainNotifiedAt") as? Date, now.timeIntervalSince(at) < 2 * 3600 { return }
        d.set(now, forKey: "batteryDrainNotifiedAt")
        let names = apps.prefix(2).map(\.name).joined(separator: ", ")
        let text = trf("Máy sẽ hết pin trong khoảng %@ phút vì %@. Cắm sạc hoặc đóng bớt app đó.", "\(minutes)", names)
        notify(text, .warning)
        SystemNotifier.shared.post(title: tr("Pin đang tụt nhanh"), body: text, page: Page.optimization.rawValue)
    }
}
