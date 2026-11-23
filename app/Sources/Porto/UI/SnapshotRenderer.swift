import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// `Porto --snapshot <dir>` scans for a few seconds, renders each popover page,
/// every Settings pane and every onboarding step with live data to PNG, and
/// exits. For checking the UI without clicking through the menu bar.
@MainActor
enum SnapshotRenderer {
    static func run(monitor: ServerMonitor, directory: String) {
        configureAppearance()
        let scheme: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        // CPU and history need a few scans.
        for _ in 0..<5 {
            monitor.scanNow()
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        monitor.scanNow()

        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var pages: [(String, PopoverRoute, Bool)] = [("servers", .servers, false), ("cleanup", .servers, true)]
        if let first = monitor.servers.first(where: { $0.agent != nil }) ?? monitor.servers.first {
            pages.insert(("detail", .detail(port: first.port), false), at: 1)
        }
        for (name, route, cleaning) in pages {
            // The page at the popover's width, without the menu-bar window fitter.
            let view = page(monitor: monitor, route: route, cleaning: cleaning)
                .frame(width: Theme.popoverWidth)
                .background(Theme.popoverBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(20)
                .background(Theme.snapshotBackground)
                .environment(\.colorScheme, scheme)
            renderWindow(view, size: NSHostingView(rootView: view).fittingSize, to: output.appendingPathComponent("\(name).png"))
        }

        for pane in SettingsPane.allCases {
            let file = "settings-" + pane.id.lowercased().replacingOccurrences(of: " & ", with: "-").replacingOccurrences(of: " ", with: "-")
            renderWindow(SettingsView(monitor: monitor, initialPane: pane), size: CGSize(width: 740, height: 560), titleBar: true,
                         to: output.appendingPathComponent("\(file).png"))
        }

        for step in OnboardingStep.allCases {
            renderWindow(OnboardingView(monitor: monitor, step: step), size: CGSize(width: 480, height: 620),
                         to: output.appendingPathComponent("onboarding-\(step.rawValue + 1).png"))
        }

        // Autopilot's log is empty unless it has acted, so draw its rows from samples.
        renderWindow(autopilotLogSample.environment(\.colorScheme, scheme), size: CGSize(width: 540, height: 260),
                     to: output.appendingPathComponent("settings-autopilot-log.png"))

        let icon = MenuBarIcon.image(glyph: monitor.needsAttention ? .alert : .porthole, count: monitor.servers.count)
        if let tiff = icon.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("menubar-icon.png"))
        }
        writeIcon(size: 1024, to: output.appendingPathComponent("appicon-1024.png"))

        for server in monitor.servers {
            print(":\(server.port)  \(server.project.name)  branch=\(server.project.branch ?? "-")  command=\(server.command ?? "-")  procs=\(server.processes.count)  mem=\(Format.bytesString(server.memory))  cpu=\(Format.percent(server.cpu))  agent=\(server.agent.map { "\($0.kind.rawValue): \($0.title ?? "?")" } ?? "-")  addresses=\(server.addresses.joined(separator: ","))")
        }
        print("apps: " + monitor.otherApps.prefix(8).map { "\($0.name) \(Format.bytesString($0.memory))" }.joined(separator: ", "))
        exit(0)
    }

    private static var autopilotLogSample: some View {
        let key = ServerKey(port: 5173, rootPid: 1, startedAt: nil)
        let entries = [
            AutopilotLogEntry(time: Date(), verb: .stop, name: "storefront", key: key, reason: L10n.text("Memory pressure"), source: .rules, outcome: .asked),
            AutopilotLogEntry(time: Date().addingTimeInterval(-900), verb: .pause, name: "docs-site", key: key, reason: L10n.text("Memory pressure"), source: .kalon, outcome: .done),
            AutopilotLogEntry(time: Date().addingTimeInterval(-4200), verb: .stop, name: "api", key: key, reason: L10n.text("Memory pressure"), source: .rules, outcome: .failed),
            AutopilotLogEntry(time: Date().addingTimeInterval(-9000), verb: .resume, name: "docs-site", key: key, reason: "", source: .user, outcome: .resumed),
        ]
        return SettingsPage {
            SettingsSection(eyebrow: L10n.text("Recent actions")) {
                ForEach(entries) { entry in
                    AutopilotLogRow(entry: entry) {
                        if entry.outcome == .asked { Button(L10n.text("Approve")) {} } else if entry.verb == .pause { Button(L10n.text("Resume")) {} }
                    }
                }
            }
        }
        .font(Theme.body)
    }

    @ViewBuilder private static func page(monitor: ServerMonitor, route: PopoverRoute, cleaning: Bool) -> some View {
        switch route {
        case .servers:
            ServersView(monitor: monitor, startCleaning: cleaning, openServer: { _ in }, openSettings: {})
        case .detail(let port):
            if let server = monitor.server(port: port) {
                ServerDetailView(server: server, monitor: monitor, back: {})
            }
        }
    }

    /// Deterministic onboarding states. These services never request real
    /// notification permission, change login items or touch preferences.
    static func runOnboarding(monitor: ServerMonitor, directory: String) {
        configureAppearance()
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let samples: [(String, OnboardingStep, UNAuthorizationStatus, SMAppService.Status)] = [
            ("tools-loading", .tools, .authorized, .enabled),
            ("tools-confirmed", .tools, .authorized, .enabled),
            ("tools-missing", .tools, .authorized, .enabled),
            ("setup-actions", .leaks, .notDetermined, .notRegistered),
            ("setup-pending", .leaks, .notDetermined, .notRegistered),
            ("setup-confirmed", .leaks, .authorized, .enabled),
            ("setup-approval", .leaks, .denied, .requiresApproval),
        ]
        renderWindow(OnboardingView(monitor: monitor), size: CGSize(width: 480, height: 620), to: output.appendingPathComponent("welcome.png"))
        for (name, step, authorization, login) in samples {
            let services = OnboardingServices(
                detect: { tool in
                    if name == "tools-loading", tool != .claude { try? await Task.sleep(for: .seconds(5)) }
                    return name != "tools-missing" || tool != .github
                },
                notifications: { authorization },
                requestNotifications: { try await Task.sleep(for: .seconds(5)) },
                login: { login },
                registerLogin: { try await Task.sleep(for: .seconds(5)) }
            )
            let status = OnboardingStatus(services: services)
            if name == "setup-pending" {
                Task {
                    await status.refreshSetup()
                    async let notification: Void = status.allowNotifications()
                    async let registration: Void = status.addLoginItem()
                    _ = await (notification, registration)
                }
            }
            renderWindow(OnboardingView(monitor: monitor, status: status, step: step), size: CGSize(width: 480, height: 620),
                         to: output.appendingPathComponent("\(name).png"))
        }
        renderWindow(OnboardingView(monitor: monitor, step: .usage, usageOnly: true), size: CGSize(width: 480, height: 620),
                     to: output.appendingPathComponent("usage-after-update.png"))
        exit(0)
    }

    /// `Porto --render-icon <dir>`: the icon set for AppIcon.icns, each size drawn
    /// from the vector artwork, plus a 1024 master.
    static func renderIcon(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        let iconset = output.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            writeIcon(size: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
            writeIcon(size: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        writeIcon(size: 1024, to: output.appendingPathComponent("appicon-1024.png"))
        // The website's home-screen icon: 180 px, full bleed, no transparency.
        let touch = ImageRenderer(content: AppIconView(size: 180, fullBleed: true))
        touch.scale = 1
        if let image = touch.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: output.appendingPathComponent("apple-touch-icon.png"))
        }
        exit(0)
    }

    /// `Porto --render-dmg-background <dir>`: background.png and @2x for dmg/.
    static func renderDMGBackground(directory: String) {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (scale, name) in [(1, "background.png"), (2, "background@2x.png")] {
            let renderer = ImageRenderer(content: DMGBackground())
            renderer.scale = CGFloat(scale)
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: output.appendingPathComponent(name))
        }
        exit(0)
    }

    /// The macOS icon grid: 824/1024 artwork centred on the canvas, leaving room for the shadow.
    private static func writeIcon(size: Int, to url: URL) {
        let canvas = CGFloat(size)
        let renderer = ImageRenderer(content: AppIconView(size: canvas * 824 / 1024).frame(width: canvas, height: canvas))
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    private static func configureAppearance() {
        // Show an overridden language in pickers without saving it.
        if let index = CommandLine.arguments.firstIndex(of: "--ui-language"), let value = CommandLine.arguments.dropFirst(index + 1).first {
            var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
            domain[Preferences.language] = value
            UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        }
        // Override only this process; never the Mac's appearance.
        if let index = CommandLine.arguments.firstIndex(of: "--appearance"), let value = CommandLine.arguments.dropFirst(index + 1).first {
            guard value == "light" || value == "dark" else {
                fputs("--appearance must be light or dark\n", stderr)
                exit(1)
            }
            NSApp.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
        }
    }

    /// AppKit-backed controls (toggles, pickers, forms) don't draw in
    /// ImageRenderer, so render them in a real off-screen window instead.
    /// Settings keeps its title bar like the real window; the popover and
    /// onboarding hide theirs.
    static func renderWindow<V: View>(_ view: V, size: CGSize, titleBar: Bool = false, to url: URL) {
        let host = NSHostingView(rootView: LocalizedView { view })
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSApp.effectiveAppearance
        window.titlebarAppearsTransparent = !titleBar
        window.titleVisibility = titleBar ? .visible : .hidden
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        // Capturing your own window needs no Screen Recording permission.
        // CGWindowListCreateImage is hidden from the Swift SDK, so look it up.
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        let includingWindow: UInt32 = 1 << 3, boundsIgnoreFraming: UInt32 = 1 << 0, bestResolution: UInt32 = 1 << 3
        guard let image = createImage(.null, includingWindow, UInt32(window.windowNumber), boundsIgnoreFraming | bestResolution)?.takeRetainedValue() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
