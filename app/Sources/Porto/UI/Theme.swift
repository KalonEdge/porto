import AppKit
import CoreText
import SwiftUI

enum Theme {
    static let text1 = adaptive(light: 0x111114, dark: 0xF5F5F7)
    // Quiet labels still clear 4.5:1 on the pure surfaces: text3 is 4.9:1 on
    // white and 5.0:1 on black, text2 7.4:1 and 8.5:1.
    static let text2 = adaptive(light: 0x111114, dark: 0xEBEBF5, lightAlpha: 0.74, darkAlpha: 0.7)
    static let text3 = adaptive(light: 0x111114, dark: 0xEBEBF5, lightAlpha: 0.6, darkAlpha: 0.53)
    /// Hairlines carry the structure, since no surface is ever grey.
    static let separator = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.1, darkAlpha: 0.14)
    /// The outline of bordered controls and cards: a step stronger than a divider.
    static let outline = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.22)
    static let fill = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.1)
    static let hover = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.09)
    static let pressed = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.16)
    static let memoryTrack = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.1)
    /// Other apps on the memory bar: clearly there, clearly not a server.
    static let memoryOther = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.24)
    /// Text on solid primary buttons and ticked checkboxes.
    static let onPrimary = adaptive(light: 0xFFFFFF, dark: 0x000000)
    /// Every surface is pure white in light mode and pure black in dark mode: the
    /// popover, the windows and their cards. The popover paints its own so the
    /// menu bar panel's grey never shows through.
    static let windowBackground = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let popoverBackground = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let snapshotBackground = adaptive(light: 0xE5E7EB, dark: 0x0B0D12)

    static let amber = adaptive(Palette.amber)
    static let red = adaptive(Palette.red)
    static let softRed = adaptive(Palette.softRed)
    /// Confirmed-ok only: a finished check, never decoration.
    static let green = adaptive(Palette.green)

    private static let portColors = Palette.ports.map(adaptive)

    static func portColor(at index: Int) -> Color { portColors[index % portColors.count] }

    private static func adaptive(_ pair: Palette.Pair) -> Color { adaptive(light: pair.light, dark: pair.dark) }

    /// Resolved at drawing time, so open windows follow appearance changes.
    static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    static let popoverWidth: CGFloat = 400
    static let inset: CGFloat = 16

    /// The 4pt grid everything sits on.
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let s: CGFloat = 12
        static let m: CGFloat = 16
        static let l: CGFloat = 20
        static let xl: CGFloat = 24
    }

    /// Concentric radii: the popover is 16, a control inside its 12pt gutter is 8,
    /// a mark inside a control is 4.
    enum Radius {
        static let window: CGFloat = 16
        static let card: CGFloat = 12
        static let control: CGFloat = 8
        static let row: CGFloat = 8
        static let mark: CGFloat = 4
    }

    /// Brief and interruptible; nil under Reduce Motion so states cut instead of moving.
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.12)
        static let state = Animation.snappy(duration: 0.22)
        static func state(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : state }
    }

    static let controlHeight: CGFloat = 32
    static let iconButton: CGFloat = 28

    // The ramp: 34 hero numbers, 28 display, 17 readouts, 13 body, 11 captions
    // and 10 eyebrow labels, in Regular and Medium. Geist Mono carries every number.
    static let hero = Font.custom("GeistMono-Medium", fixedSize: 34)
    static let display = Font.custom("GeistMono-Medium", fixedSize: 28)
    /// Display size for names rather than numbers.
    static let displaySans = Font.custom("Geist-Medium", fixedSize: 28)
    static let readout = Font.custom("GeistMono-Medium", fixedSize: 17)
    static let title = Font.custom("Geist-Medium", fixedSize: 15)
    static let body = Font.custom("Geist-Regular", fixedSize: 13)
    static let bodyMedium = Font.custom("Geist-Medium", fixedSize: 13)
    static let caption = Font.custom("Geist-Regular", fixedSize: 11)
    static let captionMedium = Font.custom("Geist-Medium", fixedSize: 11)
    static let eyebrow = Font.custom("Geist-Medium", fixedSize: 10)
    static let mono = Font.custom("GeistMono-Regular", fixedSize: 13)
    static let monoMedium = Font.custom("GeistMono-Medium", fixedSize: 13)
    static let monoCaption = Font.custom("GeistMono-Regular", fixedSize: 11)
    static let monoCaptionMedium = Font.custom("GeistMono-Medium", fixedSize: 11)
}

/// Raw colours shared by the app and the terminal UI.
enum Palette {
    typealias Pair = (light: UInt32, dark: UInt32)

    static let amber: Pair = (0x966000, 0xFFB224)
    static let red: Pair = (0xC52D24, 0xFF453A)
    static let softRed: Pair = (0xBA3028, 0xFF6961)
    static let green: Pair = (0x1F7A3D, 0x5FD38A)

    /// Port identity colours, clear of the red, amber and green status families.
    static let ports: [Pair] = [
        (0x126B8D, 0x6EC7ED), // sky
        (0x704CB0, 0xB599F0), // lavender
        (0xA23682, 0xEB9CD4), // pink
        (0x405CBC, 0x7D9CF2), // periwinkle
        (0x096D75, 0x7DDBE0), // cyan
        (0x87449E, 0xD9A3F2), // lilac
        (0x4C627D, 0xABC2E0), // slate
    ]
}

enum FontLoader {
    private static var registered = false

    /// Registers the bundled Geist fonts for this process: from Contents/Resources/Fonts
    /// in the app, or the package's Resources folder under `swift run`.
    static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // UI
            .deletingLastPathComponent() // Porto
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // package
            .appendingPathComponent("Resources/Fonts")
        for directory in [bundled, source].compactMap({ $0 }) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            let fonts = files.filter { $0.pathExtension == "ttf" }
            guard !fonts.isEmpty else { continue }
            fonts.forEach { CTFontManagerRegisterFontsForURL($0 as CFURL, .process, nil) }
            return
        }
    }

    static func nsFont(_ name: String, size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }
}

/// Rebuilds the views when the interface language changes; the monitor keeps
/// its scans and history. Also applies Hebrew's right-to-left layout.
struct LocalizedView<Content: View>: View {
    @AppStorage(Preferences.language) private var language = InterfaceLanguage.system.rawValue
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .id(language)
            .environment(\.locale, L10n.locale)
            .environment(\.layoutDirection, L10n.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
