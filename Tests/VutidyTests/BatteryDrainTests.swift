import Testing
import Foundation
@testable import Modules

@Suite struct BatteryDrainTests {
    func battery(minutes: Int?, plugged: Bool = false, charging: Bool = false) -> BatteryInfo {
        BatteryInfo(percent: 30, charging: charging, cycleCount: nil, health: nil, pluggedIn: plugged, tempC: nil, minutesRemaining: minutes)
    }

    @Test func alertsOnlyWhenOnBatteryAndLow() {
        let hot = [BatteryDrain.Consumer(name: "Xcode", cpu: 80)]
        #expect(BatteryDrain.shouldAlert(battery(minutes: 21), consumers: hot))
        #expect(!BatteryDrain.shouldAlert(battery(minutes: 200), consumers: hot))
        #expect(!BatteryDrain.shouldAlert(battery(minutes: 21, plugged: true), consumers: hot))
        #expect(!BatteryDrain.shouldAlert(battery(minutes: 21, charging: true), consumers: hot))
        #expect(!BatteryDrain.shouldAlert(battery(minutes: nil), consumers: hot))
        #expect(!BatteryDrain.shouldAlert(nil, consumers: hot))
        #expect(!BatteryDrain.shouldAlert(battery(minutes: 21), consumers: [.init(name: "x", cpu: 3)]))
        #expect(!BatteryDrain.shouldAlert(battery(minutes: 21), consumers: []))
    }

    @Test func parseGroupsHelpersByApp() {
        let out = """
         40.0 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
         35.5 /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
         50.0 /usr/local/bin/node
         99.0 /kernel_task
          0.0 /bin/zsh
        """
        let r = BatteryDrain.parse(out)
        #expect(r.map(\.name) == ["Google Chrome", "node"])
        #expect(r[0].cpu == 75.5)
    }
}
