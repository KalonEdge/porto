import AppKit

/// The right-click (or Control-click) menu on the menu bar icon. MenuBarExtra
/// has no API for one, so watch for secondary clicks on its status bar button.
@MainActor
enum StatusItemMenu {
    private static var eventMonitor: Any?

    static func install(monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
            let secondary = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            guard secondary, let button = StatusItemOpener.findButton(in: event.window?.contentView) else { return event }
            show(from: button, monitor: monitor, openSettings: openSettings)
            return nil
        }
    }

    private static func show(from button: NSStatusBarButton, monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionItem(L10n.text("Open Porto")) { StatusItemOpener.open() })

        let browser = NSMenuItem(title: L10n.text("Open in Browser"), action: nil, keyEquivalent: "")
        let servers = NSMenu()
        for server in monitor.servers {
            servers.addItem(ActionItem("localhost:\(String(server.port))  \(server.project.branch ?? server.project.name)") {
                Usage.record(.openBrowser)
                NSWorkspace.shared.open(server.url)
            })
        }
        browser.submenu = servers
        browser.isEnabled = !monitor.servers.isEmpty
        menu.addItem(browser)

        menu.addItem(.separator())
        let settings = ActionItem(L10n.text("Settings…"), action: openSettings)
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let updates = ActionItem(L10n.text("Check for Updates…")) { Updater.shared.checkForUpdates() }
        updates.isEnabled = Updater.shared.canCheckForUpdates
        menu.addItem(updates)

        let feedback = NSMenuItem(title: L10n.text("Send Feedback"), action: nil, keyEquivalent: "")
        feedback.submenu = NSMenu()
        feedback.submenu?.addItem(ActionItem(L10n.text("Report a Bug…")) { NSWorkspace.shared.open(FeedbackLink.issue(.bug)) })
        feedback.submenu?.addItem(ActionItem(L10n.text("Suggest a Feature…")) { NSWorkspace.shared.open(FeedbackLink.issue(.feature)) })
        menu.addItem(feedback)

        menu.addItem(.separator())
        let quit = ActionItem(L10n.text("Quit Porto")) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        button.highlight(false)
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// MenuBarExtra has no API to open its window, so find the status item's button
/// and click it. Every window is searched rather than a private window class:
/// macOS 27 draws the menu bar as one window instead of one per icon.
@MainActor
enum StatusItemOpener {
    /// Returns false when there's no icon to click.
    @discardableResult
    static func open() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard let button else { return false }
        // On recent macOS the menu bar draws SwiftUI's status item itself, and the
        // local button has no target or action, so clicking it in code does
        // nothing. Its scene item presents the popover when asked instead.
        if button.action == nil, let item = sceneItem(of: button) {
            item.perform(NSSelectorFromString("_requestExpandedInterfaceSession"))
            return true
        }
        button.performClick(nil)
        return true
    }

    /// The status item behind the button, when it can present the popover itself.
    private static func sceneItem(of button: NSStatusBarButton) -> NSObject? {
        let getter = NSSelectorFromString("_statusItem")
        guard button.responds(to: getter), let item = button.perform(getter)?.takeUnretainedValue() as? NSObject,
              item.responds(to: NSSelectorFromString("_requestExpandedInterfaceSession")) else { return nil }
        return item
    }

    /// Whether the icon is on screen. The menu bar hides it in its overflow on
    /// macOS 27, behind the notch, or when it's turned off in System Settings.
    static var isShowing: Bool {
        guard let window = button?.window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    private static var button: NSStatusBarButton? {
        NSApp.windows.lazy.compactMap { findButton(in: $0.contentView) }.first
    }

    static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}
