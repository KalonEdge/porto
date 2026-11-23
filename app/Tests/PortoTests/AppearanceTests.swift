import AppKit
import Testing
@testable import Porto

@MainActor
struct AppearanceTests {
    @Test func followsTheMacUnlessChosen() {
        #expect(Preferences.Appearance.system.nsAppearance == nil)
        #expect(Preferences.Appearance.light.nsAppearance?.name == .aqua)
        #expect(Preferences.Appearance.dark.nsAppearance?.name == .darkAqua)
        Preferences.register()
        #expect(UserDefaults.standard.string(forKey: Preferences.appearance) == Preferences.Appearance.system.rawValue)
    }

    @Test func appliesToTheWholeApp() {
        _ = NSApplication.shared
        defer {
            UserDefaults.standard.removeObject(forKey: Preferences.appearance)
            NSApp.appearance = nil
        }
        for (choice, expected) in [(Preferences.Appearance.dark, NSAppearance.Name.darkAqua), (.light, .aqua)] {
            UserDefaults.standard.set(choice.rawValue, forKey: Preferences.appearance)
            Preferences.applyAppearance()
            #expect(NSApp.appearance?.name == expected)
        }
        UserDefaults.standard.set(Preferences.Appearance.system.rawValue, forKey: Preferences.appearance)
        Preferences.applyAppearance()
        #expect(NSApp.appearance == nil)
        // An unknown saved value falls back to the Mac's.
        UserDefaults.standard.set("sepia", forKey: Preferences.appearance)
        Preferences.applyAppearance()
        #expect(NSApp.appearance == nil)
    }
}
