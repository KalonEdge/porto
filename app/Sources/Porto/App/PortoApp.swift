import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        // Run as `porto` (a symlink to this binary) or with --tui for the terminal UI.
        if TerminalCommand.isRequested { TerminalCommand.run() }
        PortoApp.main()
    }
}

struct PortoApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var monitor: ServerMonitor

    init() {
        FontLoader.registerBundledFonts()
        Preferences.register()
        // Initialize AppKit for snapshot mode without overriding its appearance.
        _ = NSApplication.shared
        let monitor = ServerMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        if let directory = Self.argument(after: "--snapshot-onboarding") {
            SnapshotRenderer.runOnboarding(monitor: monitor, directory: directory)
        }
        if let directory = Self.argument(after: "--snapshot") {
            SnapshotRenderer.run(monitor: monitor, directory: directory)
        }
        if let directory = Self.argument(after: "--render-icon") {
            SnapshotRenderer.renderIcon(directory: directory)
        }
        if let directory = Self.argument(after: "--render-dmg-background") {
            SnapshotRenderer.renderDMGBackground(directory: directory)
        }
        Preferences.applyAppearance()
        _ = Updater.shared
        AlertCenter.shared.start(monitor: monitor)
        AutopilotController.shared.start(monitor: monitor)
        HotKey.shared.setEnabled(UserDefaults.standard.bool(forKey: Preferences.hotkey))
        monitor.start()
        Usage.start()
    }

    private static func argument(after flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag) else { return nil }
        return CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
    }

    var body: some Scene {
        MenuBarExtra {
            LocalizedView { PopoverRoot(monitor: monitor) }
        } label: {
            LocalizedView { MenuBarLabel(monitor: monitor) }
        }
        .menuBarExtraStyle(.window)

        Window(L10n.text("Settings"), id: "settings") {
            LocalizedView { SettingsView(monitor: monitor) }
        }
        .windowResizability(.contentSize)

        Window(L10n.text("Welcome to Porto"), id: "onboarding") {
            LocalizedView { OnboardingContainer(monitor: monitor) }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the menu bar icon appears, since only views can open windows.
    @MainActor static var openSettings: (() -> Void)?

    /// Opening the app again (from Finder, Spotlight or Launchpad) opens the
    /// popover, or Settings when the menu bar is hiding the icon, so people who
    /// can't see it still reach the app.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if StatusItemOpener.isShowing {
            StatusItemOpener.open()
        } else {
            Self.openSettings?()
        }
        return false
    }

    /// Nothing Autopilot paused stays paused once Porto is gone.
    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        AutopilotController.shared.resumeAll()
    }
}

struct OnboardingContainer: View {
    @ObservedObject var monitor: ServerMonitor
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Preferences.onboarded) private var onboarded = false

    var body: some View {
        // People who onboarded before usage sharing existed only see that step.
        OnboardingView(monitor: monitor, step: onboarded ? .usage : .welcome, usageOnly: onboarded,
                       close: { dismissWindow(id: "onboarding") })
    }
}

/// The menu bar icon: the porthole, the server count, or amber when something needs attention.
struct MenuBarLabel: View {
    @ObservedObject var monitor: ServerMonitor
    @AppStorage(Preferences.iconStyle) private var iconStyle = Preferences.IconStyle.ringCount.rawValue
    @AppStorage(Preferences.onboarded) private var onboarded = false
    @AppStorage(Preferences.usageAsked) private var usageAsked = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = monitor.servers.count
        let style = Preferences.IconStyle(rawValue: iconStyle) ?? .ringCount
        let (glyph, label): (DotGlyph, Int?) = {
            // With nothing running every style rests on the ring.
            if count == 0 { return (.porthole, nil) }
            if monitor.needsAttention { return (.alert, style == .ring ? nil : count) }
            switch style {
            case .ring: return (.porthole, nil)
            case .ringCount: return (.porthole, count)
            case .count: return DotGlyph.digit(count).map { ($0, nil) } ?? (.porthole, count)
            }
        }()
        Image(nsImage: MenuBarIcon.image(glyph: glyph, count: label))
            .accessibilityLabel(count == 0 ? L10n.text("Porto, no servers") : L10n.format("Porto, %d servers", count))
            .task {
                let openSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                AppDelegate.openSettings = openSettings
                StatusItemMenu.install(monitor: monitor, openSettings: openSettings)
                // First launch shows onboarding; after an update that added it, the usage question.
                guard !onboarded || !usageAsked, Bundle.main.bundleURL.pathExtension == "app" else { return }
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
    }
}
