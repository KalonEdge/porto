import AppKit

/// UserDefaults keys and defaults for every setting. Views bind with
/// `@AppStorage(Preferences.x)`; the engine reads the defaults directly.
enum Preferences {
    // General
    static let language = "general.language"
    static let appearance = "general.appearance"
    static let iconStyle = "general.iconStyle"
    static let editor = "general.editor"
    static let terminal = "general.terminal"
    static let hotkey = "general.hotkey"
    static let scanInterval = "general.scanInterval"
    static let onboarded = "general.onboarded"
    static let shareUsage = "general.shareUsage"
    /// Set once the usage question has been asked.
    static let usageAsked = "general.usageAsked"

    // Alerts
    static let thresholdGB = "alerts.thresholdGB"
    static let leakWarnings = "alerts.leakWarnings"
    static let snoozeMinutes = "alerts.snoozeMinutes"
    static let startStop = "alerts.startStop"

    // Clean up
    static let cleanUpMode = "cleanup.mode"
    static let cleanUpNotify = "cleanup.notify"
    static let cleanUpDeletedWorktree = "cleanup.deletedWorktree"
    static let cleanUpIdleHours = "cleanup.idleHours"
    static let cleanUpRunningDays = "cleanup.runningDays"
    static let protectedProcesses = "cleanup.protected"
    static let forceQuitSeconds = "cleanup.forceQuitSeconds"

    // Autopilot
    static let autopilotMode = "autopilot.mode"
    static let autopilotMemoryPercent = "autopilot.memoryPercent"
    static let autopilotCPUPercent = "autopilot.cpuPercent"
    static let autopilotIdleMinutes = "autopilot.idleMinutes"
    static let autopilotUseKalon = "autopilot.useKalon"
    static let kalonURL = "autopilot.kalonURL"
    /// Ports the user marked "Keep running".
    static let autopilotPinned = "autopilot.pinned"
    /// Servers Autopilot has paused, so they can be resumed after a relaunch.
    static let autopilotPaused = "autopilot.paused"

    // Integrations
    static let linkClaude = "integrations.claude"
    static let linkCodex = "integrations.codex"
    static let linkConductor = "integrations.conductor"
    static let showBranches = "integrations.branches"
    static let vercelPreviews = "integrations.vercelPreviews"
    static let githubPullRequests = "integrations.githubPullRequests"

    // Ports and processes
    static let minPort = "ports.min"
    static let maxPort = "ports.max"
    static let allowlist = "ports.allowlist"

    // Remembered view state
    static let cpuShowsAll = "servers.cpuShowsAll"
    static let infoExpanded = "detail.infoExpanded"
    static let processesExpanded = "detail.processesExpanded"

    enum IconStyle: String, CaseIterable {
        case ring, ringCount, count
        var label: String {
            switch self {
            case .ring: return "Ring"
            case .ringCount: return "Ring + count"
            case .count: return "Count"
            }
        }
    }

    /// The app's look: the Mac's own, or always light or always dark.
    enum Appearance: String, CaseIterable {
        case system, light, dark
        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
        /// nil follows macOS, including its automatic light and dark switching.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Applies the saved appearance to every window, menu and alert. The menu
    /// bar icon keeps following the menu bar itself.
    @MainActor static func applyAppearance() {
        let saved = UserDefaults.standard.string(forKey: appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        NSApp.appearance = saved.nsAppearance
    }

    enum CleanUpMode: String, CaseIterable {
        case off, ask, automatic
        var label: String {
            switch self {
            case .off: return "Off"
            case .ask: return "Ask"
            case .automatic: return "Automatic"
            }
        }
    }

    enum AutopilotMode: String, CaseIterable {
        case off, ask, automatic
        var label: String {
            switch self {
            case .off: return "Off"
            case .ask: return "Ask first"
            case .automatic: return "Automatic"
            }
        }
    }

    static let defaultProtected = ["postgres", "redis-server", "mongod", "mysqld", "mysql", "mariadbd", "mariadb",
                                   "clickhouse", "clickhouse-server", "elasticsearch", "opensearch", "nginx", "docker-proxy",
                                   "Kalon", "ollama", "kalon"]
    /// Databases and model servers stay protected whatever the saved list says.
    static let builtInProtected: Set<String> = ["postgres", "redis-server", "mongod", "mysqld", "mysql", "mariadbd", "mariadb",
                                                "clickhouse", "clickhouse-server", "elasticsearch", "opensearch",
                                                "Kalon", "kalon", "ollama"]

    static let defaultAllowlist: Set<String> = [
        "node", "npm", "npx", "deno", "bun",
        "Python", "python", "python3", "uvicorn", "gunicorn", "flask", "django",
        "ruby", "rails", "puma", "unicorn",
        "php", "php-fpm",
        "java", "gradle", "mvn",
        "go", "air",
        "cargo", "rustc",
        "dotnet",
        "beam.smp", "elixir", "mix",
        "nginx", "httpd", "apache",
        "postgres", "mysql", "mysqld", "redis-server", "mongod",
        "docker-proxy",
    ]

    static func register() {
        UserDefaults.standard.register(defaults: [
            language: InterfaceLanguage.system.rawValue,
            appearance: Appearance.system.rawValue,
            iconStyle: IconStyle.ringCount.rawValue,
            editor: "auto",
            terminal: "com.apple.Terminal",
            hotkey: true,
            scanInterval: 2.0,
            shareUsage: true,
            thresholdGB: 2.0,
            leakWarnings: true,
            snoozeMinutes: 60,
            startStop: false,
            cleanUpMode: CleanUpMode.ask.rawValue,
            cleanUpNotify: true,
            cleanUpDeletedWorktree: true,
            cleanUpIdleHours: 4,
            cleanUpRunningDays: 3,
            protectedProcesses: defaultProtected,
            forceQuitSeconds: 3.0,
            autopilotMode: AutopilotMode.ask.rawValue,
            autopilotMemoryPercent: 90,
            autopilotCPUPercent: 90,
            autopilotIdleMinutes: 30,
            autopilotUseKalon: true,
            kalonURL: KalonClient.defaultURL,
            autopilotPinned: [Int](),
            linkClaude: true,
            linkCodex: true,
            linkConductor: true,
            showBranches: true,
            // Both call out through `gh`, so they're opt-in.
            vercelPreviews: false,
            githubPullRequests: false,
            minPort: 3000,
            maxPort: 65535,
        ])
    }
}
