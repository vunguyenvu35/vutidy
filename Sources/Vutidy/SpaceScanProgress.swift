import SwiftUI
import ScanEngine
import CoreKit

/// Màn "đang quét" của Space Lens: radar quét ở giữa, ba chỉ số sống (file · dung lượng · tốc độ) và đường dẫn đang đọc.
struct SpaceScanProgress: View {
    let title: String
    let symbol: String
    let snapshot: ScanSnapshot
    let onCancel: () -> Void

    @ViewState private var rate: Double = 0
    @ViewState private var last: (date: Date, files: Int)?
    private let tint = Page.spaceLens.palette.glow

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 22) {
                ScanRadar(symbol: symbol, tint: tint, blips: snapshot.files)
                VStack(spacing: 6) {
                    Text(trf("Đang quét %@", title)).font(.vt(size: 20, weight: .bold)).foregroundStyle(Theme.Text.primary)
                    Text(tr("Đang lập bản đồ dung lượng, chưa có gì bị thay đổi.")).font(Theme.Font.caption).foregroundStyle(Theme.Text.secondary)
                }
                HStack(spacing: 10) {
                    stat(tr("File"), snapshot.files.formatted(), numeric: snapshot.files)
                    stat(tr("Dung lượng"), ByteFormat.string(snapshot.bytes), numeric: Int(snapshot.bytes / 1_000_000))
                    stat(tr("Tốc độ"), trf("%@ file/giây", Int(rate).formatted()), numeric: Int(rate))
                }
                pathPill
            }
            .padding(.vertical, 30).padding(.horizontal, 26)
            .frame(maxWidth: .infinity)
            .glassSurface(radius: Theme.Radius.hero, strong: false)

            Button(action: onCancel) { Label(tr("Hủy"), systemImage: "xmark") }.buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: 580).frame(maxWidth: .infinity)
        .padding(.top, 12)
        .onChange(of: snapshot.files) { files in
            let now = Date()
            if let l = last, now.timeIntervalSince(l.date) > 0.1 {
                let inst = Double(files - l.files) / now.timeIntervalSince(l.date)
                rate = rate == 0 ? inst : rate * 0.7 + inst * 0.3     // làm mượt để số không nhảy loạn
                last = (now, files)
            } else if last == nil { last = (now, files) }
        }
    }

    func stat(_ label: String, _ value: String, numeric: Int) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.vt(size: 19, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.Text.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText()).animation(.easeOut(duration: 0.25), value: numeric)
            Text(label.uppercased()).font(Theme.Font.label).tracking(0.8).foregroundStyle(Theme.Text.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Border.subtle, lineWidth: 1))
    }

    var pathPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(snapshot.current.isEmpty ? " " : SpacePaths.shown(snapshot.current))
                .font(Theme.Font.mono).foregroundStyle(Theme.Text.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 34).frame(maxWidth: .infinity)
        .background(Capsule().fill(Color.black.opacity(0.22)))
        .overlay(Capsule().strokeBorder(Theme.Border.subtle, lineWidth: 1))
    }
}

/// Radar: vòng đồng tâm, tia quét xoay, sóng lan ra và các chấm nhấp nháy mỗi khi tìm thấy thêm file.
struct ScanRadar: View {
    let symbol: String
    let tint: Color
    var blips: Int = 0
    private let size: CGFloat = 176

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let sweep = (t * 360 / 2.6).truncatingRemainder(dividingBy: 360)
            ZStack {
                ForEach(1..<4) { i in
                    Circle().strokeBorder(tint.opacity(0.10 + 0.04 * Double(4 - i)), lineWidth: 1)
                        .frame(width: size * CGFloat(i) / 3, height: size * CGFloat(i) / 3)
                }
                // Sóng lan: hai pha lệch nhau nửa chu kỳ.
                ForEach(0..<2) { k in
                    let p = (t / 2.4 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                    Circle().strokeBorder(tint.opacity((1 - p) * 0.35), lineWidth: 1.5)
                        .frame(width: 64 + (size - 64) * p, height: 64 + (size - 64) * p)
                }
                // Tia quét: nón sáng mờ dần phía sau.
                Circle()
                    .fill(AngularGradient(stops: [.init(color: tint.opacity(0), location: 0.0), .init(color: tint.opacity(0.0), location: 0.62),
                                                  .init(color: tint.opacity(0.42), location: 1.0)], center: .center))
                    .frame(width: size, height: size).rotationEffect(.degrees(sweep))
                    .mask(Circle().frame(width: size, height: size))
                ForEach(0..<7) { i in blip(i, t: t, sweep: sweep) }
                SolidIcon(symbol: symbol, tint: tint, size: 56)
                    .shadow(color: tint.opacity(0.45), radius: 18)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }

    /// Chấm ở vị trí giả ngẫu nhiên cố định, sáng lên khi tia quét đi qua rồi tắt dần.
    func blip(_ i: Int, t: Double, sweep: Double) -> some View {
        let angle = (Double(i) * 137.5 + Double(blips % 5) * 11).truncatingRemainder(dividingBy: 360)
        let radius = size / 2 * (0.42 + 0.5 * Double((i * 53) % 100) / 100)
        let behind = (sweep - angle + 360).truncatingRemainder(dividingBy: 360)      // độ trễ sau tia quét
        let glow = max(0, 1 - behind / 150)
        let rad = (angle - 90) * .pi / 180
        return Circle().fill(tint).frame(width: 5, height: 5)
            .shadow(color: tint, radius: 4)
            .opacity(glow)
            .offset(x: CGFloat(cos(rad) * radius), y: CGFloat(sin(rad) * radius))
    }
}
