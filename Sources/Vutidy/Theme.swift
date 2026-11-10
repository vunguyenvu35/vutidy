// Graphite Glass v2 — design tokens cho SwiftUI
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Theme {
    enum Bg {
        static let content = Color(hex: 0x0F1217)
        static let card    = Color(hex: 0x151920)
        static let heroTop = Color(hex: 0x171C25)
        static let heroBottom = Color(hex: 0x131720)
        static let code    = Color(hex: 0x0A0C10)
        static let hero = LinearGradient(colors: [heroTop, heroBottom], startPoint: .top, endPoint: .bottom)
    }
    enum Border {
        static let subtle  = Color.white.opacity(0.10)
        static let `default` = Color.white.opacity(0.16)
    }
    enum Text {
        static let primary   = Color.white.opacity(0.97)
        static let secondary = Color.white.opacity(0.72)
        static let tertiary  = Color.white.opacity(0.52)
    }
    enum Signal {
        static let base = Color(hex: 0x3DDC97)
        static let text = Color(hex: 0x8EF0C2)
        static let on   = Color(hex: 0x062014)
        static let tint = Color(hex: 0x3DDC97, opacity: 0.12)
    }
    enum Review {
        static let base = Color(hex: 0xF2B13A)
        static let text = Color(hex: 0xF6C766)
        static let tint = Color(hex: 0xF2B13A, opacity: 0.12)
    }
    enum Info {
        static let base = Color(hex: 0x5AA9FF)
        static let text = Color(hex: 0x8EC5FF)
    }
    static let apps   = Color(hex: 0xA78BFA)
    static let danger = Color(hex: 0xFF8A7A)

    enum Category {
        static let system    = Info.base
        static let apps      = Theme.apps
        static let developer = Signal.base
        static let documents = Review.base
        static let purgeable = Color(hex: 0x7D8796)
        static let free      = Color.white.opacity(0.25)
    }

    enum Font {
        // Computed (không phải `let`) để đổi phông/cỡ chữ trong Cài đặt có hiệu lực ngay.
        static var display: SwiftUI.Font { .vt(size: 36, weight: .bold, design: .rounded).monospacedDigit() }
        static var title: SwiftUI.Font   { .vt(size: 32, weight: .bold) }
        static var heading: SwiftUI.Font { .vt(size: 15, weight: .semibold) }
        static var body: SwiftUI.Font    { .vt(size: 14) }
        static var caption: SwiftUI.Font { .vt(size: 12) }
        static var label: SwiftUI.Font   { .vt(size: 11, weight: .semibold) }
        static var mono: SwiftUI.Font    { .vt(size: 12, design: .monospaced) }
    }

    enum Radius {
        static let nav: CGFloat = 8
        static let button: CGFloat = 12
        static let card: CGFloat = 16
        static let hero: CGFloat = 18
    }

    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16
        static let xl: CGFloat = 24, xxl: CGFloat = 32
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 248
        static let toolbarHeight: CGFloat = 54
        static let popoverWidth: CGFloat = 400
    }
}

struct CardStyle: ViewModifier {
    var hero = false
    func body(content: Content) -> some View {
        content
            .padding(hero ? 24 : 18)
            .glassSurface(radius: hero ? Theme.Radius.hero : Theme.Radius.card, strong: hero)
    }
}

extension View {
    func card(hero: Bool = false) -> some View { modifier(CardStyle(hero: hero)) }
}
