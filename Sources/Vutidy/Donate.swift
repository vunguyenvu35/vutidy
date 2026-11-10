import SwiftUI
import AppKit
import CoreKit

/// Thông tin ủng hộ — lấy từ Vutty (frontend/src/lib/donate.ts).
/// Giống Vutty, địa chỉ crypto đang ẩn: đặt `showCrypto = true` để hiện lại trong Settings → Support Vutidy.
enum Donate {
    static let showCrypto = false
    static let kofi = URL(string: "https://ko-fi.com/vunguyenvu")!

    struct Network: Identifiable {
        let id: String, name: String, chain: String, address: String, qr: String
    }
    static let networks = [
        Network(id: "tron", name: "USDT · Tron", chain: "TRC20", address: "TMXXHRNG7qauoFWJKYbqEbd4FGgt3DgjBK", qr: "usdt-tron"),
        Network(id: "bsc", name: "USDT · BSC", chain: "BEP20", address: "0x4bdfd1d6456c28d06e3f8456ddac59e6168e5153", qr: "usdt-bsc"),
    ]

    static func qrImage(_ name: String) -> NSImage? {
        Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources/donate").flatMap { NSImage(contentsOf: $0) }
    }
}

struct DonateCard: View {
    @ViewState private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                SolidIcon(symbol: "heart.fill", tint: Theme.pink, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("Ủng hộ Vutidy")).font(.vt(size: 18, weight: .bold)).foregroundStyle(Theme.Text.primary)
                    Text(tr("Vutidy miễn phí, không quảng cáo, không telemetry. Nếu app giúp bạn lấy lại dung lượng, bạn có thể ủng hộ để dự án tiếp tục phát triển."))
                        .font(Theme.Font.body).foregroundStyle(Theme.Text.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { NSWorkspace.shared.open(Donate.kofi) } label: {
                Label(tr("Ủng hộ trên Ko-fi"), systemImage: "cup.and.saucer.fill")
            }.buttonStyle(PrimaryButtonStyle())

            if Donate.showCrypto {
                Divider().overlay(Theme.Border.subtle)
                ForEach(Donate.networks) { n in
                    HStack(alignment: .top, spacing: 14) {
                        if let img = Donate.qrImage(n.qr) {
                            Image(nsImage: img).interpolation(.none).resizable().frame(width: 92, height: 92)
                                .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("QR \(n.name)")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) { Text(n.name).font(Theme.Font.heading).foregroundStyle(Theme.Text.primary); Pill(text: n.chain) }
                            Text(n.address).font(Theme.Font.mono).foregroundStyle(Theme.Text.secondary).textSelection(.enabled).lineLimit(2)
                            Button(copied == n.id ? tr("Đã sao chép") : tr("Sao chép địa chỉ")) {
                                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.address, forType: .string)
                                copied = n.id
                            }.buttonStyle(TextActionStyle())
                        }
                    }
                }
            }
        }.card(hero: true)
    }
}
