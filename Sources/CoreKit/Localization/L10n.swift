import Foundation

public enum Language: String, CaseIterable, Sendable, Identifiable {
    case system, en, vi, ja, zh
    public var id: String { rawValue }
    /// Tên hiển thị bằng chính ngôn ngữ đó (không dịch).
    public var nativeName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .vi: return "Tiếng Việt"
        case .ja: return "日本語"
        case .zh: return "中文（简体）"
        }
    }
    public var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .en: return Locale(identifier: "en")
        case .vi: return Locale(identifier: "vi")
        case .ja: return Locale(identifier: "ja")
        case .zh: return Locale(identifier: "zh-Hans")
        }
    }
}

/// Đa ngôn ngữ nhẹ: khóa là câu tiếng Việt gốc; `vi` trả về chính khóa,
/// các ngôn ngữ khác tra bảng, thiếu thì rơi về English rồi về khóa.
public enum L10n {
    static let defaultsKey = "vutidy.language"
    private static let lock = NSLock()
    private static var _override: Language?

    /// Lựa chọn của người dùng (có thể là `.system`).
    public static var preference: Language {
        get {
            lock.lock(); defer { lock.unlock() }
            if let o = _override { return o }
            // Dùng cho test/chụp màn hình: VUTIDY_LANG=ja|zh|en|vi
            if let e = ProcessInfo.processInfo.environment["VUTIDY_LANG"], let l = Language(rawValue: e) { return l }
            return Language(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
        }
        set {
            lock.lock(); _override = newValue; lock.unlock()
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    /// Ngôn ngữ thực tế đang dùng (đã resolve `.system`).
    public static var current: Language {
        let p = preference
        return p == .system ? systemLanguage() : p
    }

    public static var locale: Locale { current.locale }

    /// Chọn ngôn ngữ hỗ trợ đầu tiên trong danh sách ưu tiên của hệ thống, mặc định English.
    public static func systemLanguage(preferred: [String] = Locale.preferredLanguages) -> Language {
        for tag in preferred {
            let code = tag.lowercased()
            if code.hasPrefix("vi") { return .vi }
            if code.hasPrefix("ja") { return .ja }
            if code.hasPrefix("zh") { return .zh }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }

    static let tables: [Language: [String: String]] = [.en: Translations.en, .ja: Translations.ja, .zh: Translations.zh]

    public static func translate(_ key: String, to lang: Language) -> String {
        if lang == .vi || lang == .system { return key }
        return tables[lang]?[key] ?? tables[.en]?[key] ?? key
    }

    /// Tất cả khóa đã có bản dịch (dùng cho test độ phủ).
    public static var allKeys: Set<String> { Set(Translations.en.keys) }
    public static func table(_ lang: Language) -> [String: String] { tables[lang] ?? [:] }
}

public func tr(_ key: String) -> String { L10n.translate(key, to: L10n.current) }

public func trf(_ key: String, _ args: String...) -> String {
    let fmt = tr(key)
    return String(format: fmt, arguments: args.map { $0 as CVarArg })
}
