import SwiftUI
import AppKit

/// Tùy chọn phông chữ và cỡ chữ của người dùng. Mặc định: phông hệ thống, cỡ 100%.
/// macOS không có cỡ chữ toàn hệ thống như iOS nên "mặc định" ở đây là 100% của cỡ gốc trong thiết kế.
enum FontPrefs {
    /// Các mức cỡ chữ. Dùng mức rời rạc (không thanh kéo) vì đổi cỡ dựng lại toàn bộ giao diện.
    static let scales: [Double] = [0.9, 1.0, 1.12, 1.25]

    /// Họ phông đã cài trên máy (loại bỏ phông hệ thống ẩn bắt đầu bằng dấu chấm).
    static var families: [String] {
        NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// nil = phông hệ thống. Nếu phông đã chọn không còn được cài thì tự quay về hệ thống.
    static var family: String? = {
        let s = UserDefaults.standard.string(forKey: "fontFamily") ?? ""
        return !s.isEmpty && NSFontManager.shared.availableFontFamilies.contains(s) ? s : nil
    }()

    static var scale: CGFloat = {
        let v = UserDefaults.standard.double(forKey: "fontScale")
        return v > 0 ? CGFloat(v) : 1
    }()
}

extension Font {
    /// Thay cho `Font.system(size:weight:design:)`: áp dụng phông và cỡ chữ người dùng chọn.
    /// Phông đơn cách (mono) luôn giữ phông hệ thống để cột số/đường dẫn thẳng hàng.
    static func vt(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let s = size * FontPrefs.scale
        if let fam = FontPrefs.family, design != .monospaced { return .custom(fam, size: s).weight(weight) }
        return .system(size: s, weight: weight, design: design)
    }
}
