import Foundation

/// Stable language codes shared by onboarding, Settings, the website and `porto language`.
enum InterfaceLanguage: String, CaseIterable {
    case system, english = "en", german = "de", french = "fr", spanish = "es", simplifiedChinese = "zh-Hans", hebrew = "he", japanese = "ja", ukrainian = "uk"

    var label: String {
        switch self {
        case .system: return L10n.text("System default")
        case .english: return "English"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .simplifiedChinese: return "简体中文"
        case .hebrew: return "עברית"
        case .japanese: return "日本語"
        case .ukrainian: return "Українська"
        }
    }

    /// For System default, the first of the Mac's preferred languages Porto speaks, else English.
    func resolved(preferredLanguages: [String]) -> InterfaceLanguage {
        guard self == .system else { return self }
        for preferred in preferredLanguages {
            let tag = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
            // Never substitute Simplified for Traditional Chinese.
            if tag == "zh" || tag.hasPrefix("zh-hans") || tag == "zh-cn" || tag == "zh-sg" { return .simplifiedChinese }
            let base = tag.split(separator: "-").first.map(String.init) ?? tag
            if let match = Self.allCases.first(where: { $0 != .system && $0.rawValue == base }) { return match }
            if base == "iw" { return .hebrew }
        }
        return .english
    }

    var isRightToLeft: Bool { self == .hebrew }

    static let codes = allCases.map(\.rawValue).joined(separator: ", ")
}

/// Lookups in the bundled .lproj tables. English is both the key and the
/// fallback; names, commands, paths and machine-readable output never pass here.
enum L10n {
    static var language: InterfaceLanguage {
        if TerminalCommand.isRequested { return .english }
        let arguments = CommandLine.arguments
        let override = arguments.firstIndex(of: "--ui-language").flatMap { index in
            index + 1 < arguments.count ? InterfaceLanguage(rawValue: arguments[index + 1]) : nil
        }
        let saved = UserDefaults.standard.string(forKey: Preferences.language).flatMap(InterfaceLanguage.init(rawValue:))
        return (override ?? saved ?? .system).resolved(preferredLanguages: Locale.preferredLanguages)
    }

    static var locale: Locale { Locale(identifier: language.rawValue) }

    // SwiftPM's generated accessor looks beside Bundle.main.bundleURL; the
    // packaged app keeps its resources in Contents/Resources instead.
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Porto_Porto", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    private static let tables: [InterfaceLanguage: Bundle] = {
        var result: [InterfaceLanguage: Bundle] = [:]
        for language in InterfaceLanguage.allCases where language != .system {
            // Match the bundle's own spelling (some SwiftPM versions lower-case
            // zh-Hans.lproj), and let Bundle find the folder: flat bundles keep
            // it at the top, newer builds under Contents/Resources.
            if let name = resourceBundle.localizations.first(where: { $0.caseInsensitiveCompare(language.rawValue) == .orderedSame }),
               let url = resourceBundle.url(forResource: name, withExtension: "lproj"), let bundle = Bundle(url: url) {
                result[language] = bundle
            }
        }
        return result
    }()

    static func text(_ english: String, language: InterfaceLanguage = language) -> String {
        guard language != .english else { return english }
        return tables[language]?.localizedString(forKey: english, value: english, table: nil) ?? english
    }

    /// Ukrainian has one/few/many noun forms (1 and 21; 2–4 and 22–24; the rest).
    static func counted(_ singular: String, _ plural: String, count: Int, language: InterfaceLanguage = language) -> String {
        if language == .ukrainian {
            let last = count % 10, lastTwo = count % 100
            if last == 1 && lastTwo != 11 { return text(singular, language: language) }
            if (2...4).contains(last) && !(12...14).contains(lastTwo) { return text(plural + " (few)", language: language) }
        }
        return text(count == 1 || (language == .french && count == 0) ? singular : plural, language: language)
    }

    static func format(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: text(english), locale: locale, arguments: arguments)
    }

    /// Localized durations for the app. The terminal keeps Format.duration's English.
    static func duration(_ interval: TimeInterval, short: Bool = false) -> String {
        guard language != .english else { return short ? Format.shortDuration(interval) : Format.duration(interval) }
        let minutes = Int(interval / 60)
        if minutes < 1 { return short ? format("%dm", 1) : text("<1m") }
        if minutes < 60 { return format("%dm", minutes) }
        let hours = minutes / 60
        if hours >= 24 { return format("%dd", hours / 24) }
        let rest = minutes % 60
        return short || rest == 0 ? format("%dh", hours) : format("%dh %dm", hours, rest)
    }

    static func time(_ date: Date) -> String {
        guard language != .english else { return Format.time(date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }
}
