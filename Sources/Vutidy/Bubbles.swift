import SwiftUI
import CoreKit
import ScanEngine

// MARK: - Bố cục bong bóng (circle packing bằng thư giãn lực đẩy)

struct Bubble: Identifiable {
    let node: DirNode
    var center: CGPoint
    var radius: CGFloat
    var id: String { node.id }
}

enum BubbleLayout {
    /// Diện tích bong bóng tỉ lệ với dung lượng. Các bong bóng giao nhau được đẩy tách ra; nếu không đủ chỗ thì thu nhỏ đều rồi thử lại.
    static func pack(_ nodes: [DirNode], in size: CGSize, maxBubbles: Int = 36) -> [Bubble] {
        guard size.width > 80, size.height > 80 else { return [] }
        var items = nodes.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        if items.count > maxBubbles {
            let rest = items[maxBubbles...]
            let parent = rest.first?.url.deletingLastPathComponent() ?? URL(fileURLWithPath: "/")
            let agg = DirNode(url: parent.appendingPathComponent("…"), name: trf("…%@ mục khác", "\(rest.count)"),
                              size: rest.reduce(0) { $0 + $1.size }, isDir: false, isAggregate: true)
            items = Array(items[..<maxBubbles]) + [agg]
        }
        guard !items.isEmpty else { return [] }

        let total = Double(items.reduce(0) { $0 + $1.size })
        let area = Double(size.width * size.height) * 0.50
        var radii: [CGFloat] = items.map { max(12, CGFloat((area * Double($0.size) / total / Double.pi).squareRoot())) }
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let gap: CGFloat = 5

        // Vị trí ban đầu: xoắn ốc hoa hướng dương, bong bóng lớn ở giữa.
        var pos: [CGPoint] = items.indices.map { i in
            let a = Double(i) * 2.399963
            let r = 38 * Double(i).squareRoot()
            return CGPoint(x: c.x + CGFloat(cos(a) * r), y: c.y + CGFloat(sin(a) * r) * 0.8)
        }

        func overlaps() -> Bool {
            for i in 0..<items.count { for j in (i + 1)..<items.count where hypot(pos[j].x - pos[i].x, pos[j].y - pos[i].y) < radii[i] + radii[j] + gap - 0.5 { return true } }
            return false
        }

        for _ in 0..<7 {
            for iter in 0..<420 {
                var moved = false
                for i in 0..<items.count {
                    for j in (i + 1)..<items.count {
                        let dx = pos[j].x - pos[i].x, dy = pos[j].y - pos[i].y
                        var d = hypot(dx, dy)
                        let minD = radii[i] + radii[j] + gap
                        if d < minD {
                            if d < 0.001 { d = 0.001 }
                            let push = (minD - d)
                            let ux = dx / d, uy = dy / d
                            let wi = radii[j] / (radii[i] + radii[j]), wj = radii[i] / (radii[i] + radii[j])   // bong bóng nhỏ bị đẩy nhiều hơn
                            pos[i].x -= ux * push * wi; pos[i].y -= uy * push * wi
                            pos[j].x += ux * push * wj; pos[j].y += uy * push * wj
                            moved = true
                        }
                    }
                }
                for i in 0..<items.count {   // trọng lực nhẹ về tâm + giữ trong khung
                    pos[i].x += (c.x - pos[i].x) * 0.012
                    pos[i].y += (c.y - pos[i].y) * 0.016
                    pos[i].x = min(max(pos[i].x, radii[i] + 3), size.width - radii[i] - 3)
                    pos[i].y = min(max(pos[i].y, radii[i] + 3), size.height - radii[i] - 3)
                }
                if !moved && iter > 40 { break }
            }
            if !overlaps() { break }
            radii = radii.map { max(9, $0 * 0.93) }
        }
        // Phóng đều cả cụm cho vừa khung (giữ nguyên tỉ lệ nên không bong bóng nào bị chồng lên nhau).
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for i in items.indices {
            minX = min(minX, pos[i].x - radii[i]); maxX = max(maxX, pos[i].x + radii[i])
            minY = min(minY, pos[i].y - radii[i]); maxY = max(maxY, pos[i].y + radii[i])
        }
        let margin: CGFloat = 14
        let scale = min(2.4, min((size.width - 2 * margin) / max(1, maxX - minX), (size.height - 2 * margin) / max(1, maxY - minY)))
        let mid = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        return items.indices.map { i in
            Bubble(node: items[i],
                   center: CGPoint(x: c.x + (pos[i].x - mid.x) * scale, y: c.y + (pos[i].y - mid.y) * scale),
                   radius: radii[i] * scale)
        }
    }
}

final class BubbleCache {
    private var key = ""
    private var value: [Bubble] = []
    func get(_ nodes: [DirNode], _ size: CGSize) -> [Bubble] {
        let k = "\(nodes.map(\.id).joined(separator: "|").hashValue)-\(Int(size.width))x\(Int(size.height))"
        if k != key { value = BubbleLayout.pack(nodes, in: size); key = k }
        return value
    }
}

// MARK: - Màu theo dung lượng · vòng viền theo trạng thái

enum BubbleColor {
    /// 0 (nhỏ) → 1 (lớn nhất): xanh ngọc → xanh dương → tím → hồng → cam.
    static func heat(_ t: Double) -> Color {
        let stops: [(Double, Color)] = [(0, Theme.teal), (0.30, Color(hex: 0x5AA9FF)), (0.55, Color(hex: 0x9B7BFF)), (0.78, Color(hex: 0xFF6FA5)), (1, Color(hex: 0xFF9F5A))]
        let x = min(max(t, 0), 1)
        for i in 1..<stops.count where x <= stops[i].0 {
            let (a, ca) = stops[i - 1], (b, cb) = stops[i]
            return ca.mixed(with: cb, (x - a) / (b - a))
        }
        return stops.last!.1
    }
}

enum BubbleStatus {
    case cleanable, review, normal
    var color: Color {
        switch self { case .cleanable: return Color(hex: 0x4DEBA4); case .review: return Theme.Review.base; case .normal: return .clear }
    }
    var label: String { self == .cleanable ? tr("Có thể dọn") : (self == .review ? tr("Cần xem lại") : "") }

    static func of(_ n: DirNode) -> BubbleStatus {
        let p = n.url.path.lowercased()
        let clean = ["/caches", "/.cache", "/node_modules", "/deriveddata", "/.npm", "/__pycache__", "/.gradle/caches", "/cocoapods", "/.trash", "/logs"]
        if clean.contains(where: { p.contains($0) }) { return .cleanable }
        let review = ["/downloads", "/docker", ".ollama", "/movies", "/virtualbox", "/coresimulator", "/backups", "/xcode/archives", "/.huggingface"]
        if review.contains(where: { p.contains($0) }) { return .review }
        return .normal
    }
}

// MARK: - Biểu đồ bong bóng

struct BubbleChart: View {
    let nodes: [DirNode]
    @Binding var selection: DirNode?
    var onOpen: (DirNode) -> Void
    @ViewState private var hovered: String?
    @ViewState private var cache = BubbleCache()

    var body: some View {
        GeometryReader { g in
            let bubbles = cache.get(nodes, g.size)
            let maxSize = Double(bubbles.map { $0.node.size }.max() ?? 1)
            ZStack {
                ForEach(bubbles) { b in bubbleView(b, maxSize: maxSize) }
            }
            .frame(width: g.size.width, height: g.size.height)
            .animation(.easeInOut(duration: 0.35), value: bubbles.map(\.id))
        }
    }

    @ViewBuilder
    func bubbleView(_ b: Bubble, maxSize: Double) -> some View {
        let r = b.radius
        let t = (Double(b.node.size) / max(1, maxSize)).squareRoot()
        let color = b.node.isAggregate ? Color(hex: 0x7D8796) : BubbleColor.heat(t)
        let status = b.node.isAggregate ? BubbleStatus.normal : BubbleStatus.of(b.node)
        let isHover = hovered == b.id
        let dim = hovered != nil && !isHover
        let selected = selection?.id == b.id

        ZStack {
            // Thân bóng: trong mờ ở giữa, đậm dần ra mép như bong bóng thủy tinh.
            Circle().fill(RadialGradient(colors: [color.mixed(with: .white, 0.18).opacity(0.55), color.opacity(0.78), color.mixed(with: .black, 0.30).opacity(0.95)],
                                         center: UnitPoint(x: 0.42, y: 0.38), startRadius: r * 0.05, endRadius: r * 1.05))
            // Ánh sáng phản xạ ở đáy (caustic).
            Circle().fill(RadialGradient(colors: [color.mixed(with: .white, 0.55).opacity(0.55), .clear],
                                         center: UnitPoint(x: 0.68, y: 0.88), startRadius: 0, endRadius: r * 0.75))
                .mask(Circle())
            // Vành sáng mỏng.
            Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.10), Color.white.opacity(0.35)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(1, min(2.2, r * 0.05)))
            // Điểm sáng bóng (specular) góc trên trái.
            Ellipse().fill(LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .frame(width: r * 0.62, height: r * 0.30)
                .rotationEffect(.degrees(-28))
                .offset(x: -r * 0.36, y: -r * 0.55)
                .blur(radius: r * 0.02)
            if r > 18 {
                Circle().fill(Color.white.opacity(0.7)).frame(width: r * 0.10, height: r * 0.10).offset(x: r * 0.52, y: r * 0.46).blur(radius: 0.6)
            }
            if status != .normal {
                Circle().strokeBorder(status.color.opacity(0.95), style: StrokeStyle(lineWidth: 1.8, dash: [1, 5], dashPhase: 0))
                    .padding(-6).shadow(color: status.color.opacity(0.55), radius: 5)
            }
            if selected { Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(-10).shadow(color: .white.opacity(0.5), radius: 6) }
            if r > 34 {
                VStack(spacing: 1) {
                    Text(b.node.name).font(.system(size: min(16, max(10, r * 0.26)), weight: .semibold)).lineLimit(1).minimumScaleFactor(0.55)
                    Text(ByteFormat.string(b.node.size)).font(.system(size: min(13, max(9, r * 0.2)), weight: .medium)).opacity(0.88).lineLimit(1)
                }
                .foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 2, y: 1).padding(r * 0.16)
            }
        }
        .frame(width: r * 2, height: r * 2)
        // QUAN TRỌNG: hover/bấm phải gắn vào hình tròn TRƯỚC `.position` — `.position` làm view giãn bằng cả khung,
        // nếu gắn sau thì vùng hover của mọi bong bóng là toàn bộ biểu đồ.
        .contentShape(Circle())
        .onHover { inside in hovered = inside ? b.id : (hovered == b.id ? nil : hovered) }
        .onTapGesture(count: 2) { onOpen(b.node) }
        .onTapGesture { selection = b.node }
        .pointerCursor()
        .scaleEffect(isHover ? 1.12 : 1)
        .opacity(dim ? 0.30 : 1)
        .shadow(color: color.opacity(isHover ? 0.85 : 0.30), radius: isHover ? 26 : 8, y: isHover ? 8 : 3)
        .overlay(alignment: .top) {
            if isHover {
                VStack(spacing: 2) {
                    Text(b.node.name).font(.vt(size: 12.5, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(ByteFormat.string(b.node.size)).font(.vt(size: 12, weight: .medium)).monospacedDigit()
                        if status != .normal { Text("· " + status.label).font(.vt(size: 11)).foregroundStyle(status.color) }
                    }
                }
                .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                .fixedSize().offset(y: -(r * 0.12) - 44).allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovered)
        .position(b.center)
        .zIndex(isHover ? 20 : (selected ? 10 : 0))
        .accessibilityLabel("\(b.node.name), \(ByteFormat.string(b.node.size))")
    }
}

/// Chú giải: thang màu theo dung lượng + ý nghĩa vòng viền.
struct BubbleLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Text(tr("Nhỏ")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                Capsule().fill(LinearGradient(colors: (0...8).map { BubbleColor.heat(Double($0) / 8) }, startPoint: .leading, endPoint: .trailing))
                    .frame(width: 130, height: 8)
                Text(tr("Lớn")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
            }
            ForEach([BubbleStatus.cleanable, .review], id: \.label) { s in
                HStack(spacing: 6) {
                    Circle().strokeBorder(s.color, lineWidth: 2.5).frame(width: 14, height: 14)
                    Text(s.label).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
            }
            Spacer()
        }
    }
}
