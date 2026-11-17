import Testing
import Foundation
@testable import Modules

@Suite struct DockerItemsTests {
    let dir = URL(fileURLWithPath: "/tmp/docker")

    /// Hồi quy: `docker system df` báo Reclaimable gồm cả image có tag không dùng, nhưng `prune -f` chỉ xóa dangling.
    /// Mục "an toàn" phải khớp phần lệnh thật sự giải phóng, không hứa 8 GB rồi giải phóng 0.
    @Test func noDanglingMeansNoSafeImageItem() {
        let items = DockerDetector.imageItems(reclaimable: 8_022_000_000, dangling: 0, dir: dir)
        #expect(items.count == 1)
        #expect(items[0].safety == .review && items[0].command == ["docker", "image", "prune", "-a", "-f"] && items[0].allocatedSize == 8_022_000_000)
        #expect(items[0].ruleID == "docker-images-tagged")
    }

    @Test func splitsDanglingFromTaggedUnused() {
        let items = DockerDetector.imageItems(reclaimable: 8_000_000_000, dangling: 1_500_000_000, dir: dir)
        let safe = items.first { $0.safety == .safe }, review = items.first { $0.safety == .review }
        #expect(safe?.allocatedSize == 1_500_000_000 && safe?.command == ["docker", "image", "prune", "-f"] && safe?.ruleID == "docker-images")
        #expect(review?.allocatedSize == 6_500_000_000)
        #expect(items.reduce(Int64(0)) { $0 + $1.allocatedSize } == 8_000_000_000, "tổng không đổi so với df")
    }

    @Test func danglingNeverExceedsReclaimable() {
        let items = DockerDetector.imageItems(reclaimable: 1_000_000_000, dangling: 5_000_000_000, dir: dir)
        #expect(items.count == 1 && items[0].safety == .safe && items[0].allocatedSize == 1_000_000_000)
        #expect(DockerDetector.imageItems(reclaimable: 0, dangling: 0, dir: dir).isEmpty)
    }
}
