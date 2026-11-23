import Foundation
import Testing
@testable import Porto

struct LocalizationTests {
    @Test func picksTheFirstSupportedPreferredLanguage() {
        let cases: [([String], InterfaceLanguage)] = [
            (["de-DE"], .german), (["fr-CA"], .french), (["es-419"], .spanish), (["ja-JP"], .japanese), (["uk-UA"], .ukrainian),
            (["zh-Hans-CN"], .simplifiedChinese), (["zh_CN"], .simplifiedChinese), (["zh-Hant-TW", "fr-FR"], .french), (["zh-Hant"], .english),
            (["he-IL"], .hebrew), (["iw-IL"], .hebrew),
            (["ko-KR", "de-AT", "en-US"], .german), (["en-GB", "de-DE"], .english), ([], .english), (["xx"], .english),
        ]
        for (preferred, expected) in cases {
            #expect(InterfaceLanguage.system.resolved(preferredLanguages: preferred) == expected, "\(preferred)")
        }
        for language in InterfaceLanguage.allCases where language != .system {
            #expect(language.resolved(preferredLanguages: ["de-DE"]) == language)
        }
        #expect(InterfaceLanguage.hebrew.isRightToLeft)
        #expect(!InterfaceLanguage.japanese.isRightToLeft)
    }

    @Test func translatesAndLeavesUserContentAlone() {
        let settings: [InterfaceLanguage: String] = [.english: "Settings", .german: "Einstellungen", .french: "Réglages", .spanish: "Ajustes",
                                                    .simplifiedChinese: "设置", .hebrew: "הגדרות", .japanese: "設定", .ukrainian: "Налаштування"]
        for (language, expected) in settings {
            #expect(L10n.text("Settings", language: language) == expected)
            // Project names, folders and commands pass through untouched.
            let content = "~/código/项目 · bun run dev · fix/Größe"
            #expect(L10n.text(content, language: language) == content)
        }
    }

    /// Every table has exactly the English keys, no empty values, and the same
    /// format arguments (numbered arguments may move, types may not).
    @Test func tablesMatchEnglish() throws {
        let english = try table(.english)
        #expect(english.count > 250)
        for language in InterfaceLanguage.allCases where language != .system {
            let translated = try table(language)
            #expect(Set(translated.keys) == Set(english.keys), "Keys: \(language.rawValue)")
            for (key, value) in english {
                #expect(value == key, "English values repeat their keys: \(key)")
                guard let translation = translated[key] else { continue }
                #expect(!translation.isEmpty, "Empty: \(language.rawValue) \(key)")
                #expect(try arguments(translation) == arguments(key), "Arguments: \(language.rawValue) \(key)")
            }
        }
    }

    /// Every string the sources pass to L10n has an entry, so nothing silently
    /// shows English in another language.
    @Test func everyStringInTheSourcesIsTranslated() throws {
        let english = try table(.english)
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Porto")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)

        let literal = #""((?:[^"\\]|\\.)*)""#
        let patterns = [
            try NSRegularExpression(pattern: #"L10n\.(?:text|format)\("# + literal),
            try NSRegularExpression(pattern: #"L10n\.counted\("# + literal + #",\s*"# + literal),
        ]
        var used = Set<String>()
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for pattern in patterns {
                for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                    for group in 1..<match.numberOfRanges {
                        guard let range = Range(match.range(at: group), in: source) else { continue }
                        used.insert(source[range].replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\\"#, with: "\\"))
                    }
                }
            }
        }
        // Keys built at runtime.
        used.formUnion(SettingsPane.allCases.map(\.rawValue))
        used.formUnion(Preferences.IconStyle.allCases.map(\.label))
        used.formUnion(Preferences.CleanUpMode.allCases.map(\.label))
        used.formUnion(Preferences.AutopilotMode.allCases.map(\.label))
        used.formUnion(Preferences.Appearance.allCases.map(\.label))
        used.formUnion(["Checking…", "Waiting…", "Allowed", "Not allowed", "Allow…", "Settings…", "Unavailable",
                        "Added", "Adding…", "Not added", "Add", "Needs approval", "Not found", "Open", "Merged", "Closed"])

        #expect(used.count > 200)
        let interpolated = used.filter { $0.contains("\\(") }
        #expect(interpolated.isEmpty, "Interpolated keys never match a table: \(interpolated.sorted())")
        let missing = used.subtracting(english.keys).subtracting(interpolated)
        #expect(missing.isEmpty, "Missing from Localizable.strings: \(missing.sorted())")
    }

    @Test func ukrainianCountsUseAllThreeForms() {
        for count in [1, 21, 31, 101] { #expect(L10n.counted("server", "servers", count: count, language: .ukrainian) == "сервер") }
        for count in [2, 3, 4, 22, 34] { #expect(L10n.counted("server", "servers", count: count, language: .ukrainian) == "сервери") }
        for count in [0, 5, 11, 12, 14, 15, 111, 112] { #expect(L10n.counted("server", "servers", count: count, language: .ukrainian) == "серверів") }
        #expect(L10n.counted("server", "servers", count: 1, language: .german) == "Server")
        #expect(L10n.counted("server", "servers", count: 2, language: .english) == "servers")
    }

    @Test func formatsReorderArgumentsWhereTheLanguageNeedsIt() {
        #expect(String(format: L10n.text("Stop %d processes", language: .simplifiedChinese), 3) == "停止 3 个进程")
        #expect(String(format: L10n.text("+%@ in %@", language: .simplifiedChinese), "500 MB", "10 分钟") == "10 分钟内增加 500 MB")
    }

    @Test func hebrewIsolatesTechnicalTokens() {
        #expect(L10n.text("Open localhost:%@", language: .hebrew).contains("\u{2066}localhost:%@\u{2069}"))
        // Isolation marks take no columns in the terminal.
        #expect(TextWidth.of("\u{2066}:5173\u{2069}") == 5)
    }

    private func table(_ language: InterfaceLanguage) throws -> [String: String] {
        let folder = try #require(L10n.resourceBundle.localizations.first { $0.caseInsensitiveCompare(language.rawValue) == .orderedSame })
        let url = try #require(L10n.resourceBundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: folder))
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }

    /// "position:type" for each argument, sorted.
    private func arguments(_ value: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: "%(?:([0-9]+)\\$)?([@df])")
        return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).enumerated().map { index, match in
            let position = Range(match.range(at: 1), in: value).map { String(value[$0]) } ?? String(index + 1)
            return "\(position):\(value[Range(match.range(at: 2), in: value)!])"
        }.sorted()
    }
}
