import Testing
import Foundation
@testable import Modules

@Suite struct XProtectTests {
    // Dòng thật lấy từ `log show` trên một máy sạch.
    let clean = """
    Timestamp               Ty Process[PID:TID]
    2026-11-17 22:07:15.103 Df XProtectRemediatorFloppyFlipper[76674:67b089] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"execution_duration":7.593631744384766e-05,"status_code":20,"status_message":"NoThreatDetected","caused_by":[]}
    2026-11-17 22:07:15.785 E  XProtectRemediatorSnowBeagle[76675:67b090] [com.apple.XProtectFramework.PluginAPI:XPLaunchServices] Got path from LaunchServices that was not a bundle
    2026-11-17 22:08:08.904 Df XProtectRemediatorConductor[77089:67b732] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_message":"Success","caused_by":[],"execution_duration":0.0001,"status_code":0}
    2026-11-17 22:10:39.867 Df XProtectRemediatorTrovi[78002:67c446] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_message":"NoThreatDetected","execution_duration":1.6e-05,"status_code":20,"caused_by":[]}
    """

    @Test func parsesStatusOutput() {
        let st = XProtectCheck.parseStatus("XProtect launch scans: enabled\nXProtect background scans: enabled\nVersion: 5372 Installed: 2026-11-11 19:02:29 +0000\n")
        #expect(st.launch == true && st.background == true && st.version == "5372")
        #expect(st.installed == ISO8601DateFormatter().date(from: "2026-11-11T19:02:29Z"))
        let off = XProtectCheck.parseStatus("XProtect launch scans: disabled\nXProtect background scans: enabled\n")
        #expect(off.launch == false && off.background == true && off.version == nil && off.installed == nil)
    }

    @Test func parsesRealEventLinesAndIgnoresNoise() {
        let ev = XProtectCheck.parseEvents(clean)
        #expect(ev.map(\.plugin) == ["FloppyFlipper", "Conductor", "Trovi"], "bỏ dòng tiêu đề và dòng không phải XPEvent.structured")
        #expect(ev[0].status == "NoThreatDetected" && ev[0].code == 20 && ev[0].causedBy.isEmpty)
        #expect(ev.allSatisfy { !$0.isThreat }, "NoThreatDetected và Success là bình thường")
    }

    @Test func cleanMachineHasNoDetections() {
        let sum = XProtectCheck.summarize(XProtectCheck.parseEvents(clean))
        #expect(sum.modules == 3 && sum.detections.isEmpty && sum.last != nil)
    }

    @Test func anyOtherStatusOrAnyEvidenceIsSurfaced() {
        let log = """
        2026-11-17 22:07:15.103 Df XProtectRemediatorAdload[1:2] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_code":1,"status_message":"ThreatRemediated","caused_by":["/Users/x/Library/LaunchAgents/evil.plist"]}
        2026-11-17 22:08:00.000 Df XProtectRemediatorTrovi[3:4] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_code":20,"status_message":"NoThreatDetected","caused_by":["something"]}
        2026-11-17 22:09:00.000 Df XProtectRemediatorBundlore[5:6] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_code":9,"status_message":"Timeout","caused_by":[]}
        """
        let sum = XProtectCheck.summarize(XProtectCheck.parseEvents(log))
        #expect(sum.detections.map(\.plugin) == ["Adload", "Bundlore", "Trovi"], "trạng thái lạ và mọi căn cứ đều hiện ra, sắp theo tên")
        let info = XProtectInfo(detections: sum.detections)
        let f = XProtectCheck.findings(info)
        #expect(f.count == 3 && f.allSatisfy { $0.severity == .high && $0.code == "xprotect.detection" && $0.source == .system })
        #expect(f.first?.detail.contains("evil.plist") == true)
        #expect(Set(f.map(\.key)).count == 3, "mỗi phát hiện có khóa riêng để bỏ qua/nhận biết mục mới")
    }

    @Test func onlyLatestRunPerModuleCounts() {
        let log = """
        2026-11-10 10:00:00.000 Df XProtectRemediatorAdload[1:2] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_code":1,"status_message":"ThreatDetected","caused_by":["/x"]}
        2026-11-12 10:00:00.000 Df XProtectRemediatorAdload[3:4] [com.apple.XProtectFramework.PluginAPI:XPEvent.structured] {"status_code":20,"status_message":"NoThreatDetected","caused_by":[]}
        """
        let sum = XProtectCheck.summarize(XProtectCheck.parseEvents(log))
        #expect(sum.modules == 1 && sum.detections.isEmpty, "lần quét sau đã sạch thì không còn cảnh báo")
    }

    @Test func staleDatabaseIsFlaggedOnlyWhenOld() {
        let now = ISO8601DateFormatter().date(from: "2026-11-18T00:00:00Z")!
        var info = XProtectInfo(installed: ISO8601DateFormatter().date(from: "2026-11-11T00:00:00Z"))
        #expect(info.updateAgeDays(now: now) == 7 && XProtectCheck.findings(info, now: now).isEmpty)
        info.installed = ISO8601DateFormatter().date(from: "2026-08-01T00:00:00Z")
        let f = XProtectCheck.findings(info, now: now)
        #expect(f.count == 1 && f[0].code == "xprotect.stale" && f[0].severity == .low)
    }
}
