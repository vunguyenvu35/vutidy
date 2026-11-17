import Testing
import Foundation
@testable import CoreKit

@Suite struct AutoCleanTests {
    private func item(_ safety: SafetyLevel, command: [String]? = nil) -> ScanItem {
        ScanItem(url: URL(fileURLWithPath: "/tmp/x"), title: "x", allocatedSize: 1, category: "c", ruleID: "r", safety: safety, command: command)
    }

    @Test func onlySafeFilesAreAutoCleanable() {
        #expect(item(.safe).isAutoCleanable)
        #expect(!item(.review).isAutoCleanable)
        #expect(!item(.dangerous).isAutoCleanable)
    }

    @Test func commandItemsAreNeverAutoCleaned() {
        // docker prune, go clean, brew cleanup cannot be restored from the Quarantine.
        #expect(!item(.safe, command: ["docker", "image", "prune", "-f"]).isAutoCleanable)
    }
}
