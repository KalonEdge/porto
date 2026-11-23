import ServiceManagement
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case alerts = "Alerts"
    case cleanUp = "Clean up"
    case autopilot = "Autopilot"
    case ports = "Ports & processes"
    case integrations = "Integrations"
    case about = "About"

    var id: String { rawValue }

    var glyph: DotGlyph {
        switch self {
        case .general: return .porthole
        case .alerts: return .alert
        case .cleanUp: return .rising
        case .autopilot: return .bars
        case .ports: return .letterP
        case .integrations: return .prompt
        case .about: return .question
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: ServerMonitor
    @State private var pane: SettingsPane?

    init(monitor: ServerMonitor, initialPane: SettingsPane = .general) {
        self.monitor = monitor
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                HStack(spacing: 10) {
                    DotGridView(glyph: pane.glyph, size: 16)
                    Text(L10n.text(pane.rawValue)).font(self.pane == pane ? Theme.bodyMedium : Theme.body)
                        .foregroundStyle(Theme.text1)
                }
                .padding(.vertical, 2)
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(200)
            .scrollContentBackground(.hidden)
            .background(Theme.windowBackground)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane()
                case .alerts: AlertsPane()
                case .cleanUp: CleanUpPane()
                case .autopilot: AutopilotPane()
                case .ports: PortsPane(monitor: monitor)
                case .integrations: IntegrationsPane()
                case .about: AboutPane()
                }
            }
            .background(Theme.windowBackground)
            .font(Theme.body)
            .navigationTitle(L10n.text(pane?.rawValue ?? "Settings"))
        }
        .toolbarBackground(Theme.windowBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .frame(width: 740, height: 560)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @AppStorage(Preferences.language) private var language = InterfaceLanguage.system.rawValue
    @AppStorage(Preferences.appearance) private var appearance = Preferences.Appearance.system.rawValue
    @AppStorage(Preferences.iconStyle) private var iconStyle = Preferences.IconStyle.ringCount.rawValue
    @AppStorage(Preferences.editor) private var editor = "auto"
    @AppStorage(Preferences.terminal) private var terminal = "com.apple.Terminal"
    @AppStorage(Preferences.hotkey) private var hotkey = true
    @AppStorage(Preferences.scanInterval) private var scanInterval = 2.0
    @AppStorage(Preferences.shareUsage) private var shareUsage = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        SettingsPage {
            SettingsSection {
                SettingsPicker(L10n.text("Language"), selection: $language) {
                    ForEach(InterfaceLanguage.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                SettingsPicker(L10n.text("Appearance"), selection: $appearance) {
                    ForEach(Preferences.Appearance.allCases, id: \.rawValue) { Text(L10n.text($0.label)).tag($0.rawValue) }
                }
                .segmented()
                .onChange(of: appearance) { _, _ in Preferences.applyAppearance() }
                Text(L10n.text("Changes apply immediately.")).font(Theme.caption).foregroundStyle(Theme.text3)
            }
            SettingsSection {
                SettingsToggle(L10n.text("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                SettingsPicker(selection: $iconStyle) {
                    ForEach(Preferences.IconStyle.allCases, id: \.rawValue) { Text(L10n.text($0.label)).tag($0.rawValue) }
                } label: {
                    SettingLabel(L10n.text("Menu bar icon"), caption: L10n.text("Unlit dots stay hidden until there's something to show"))
                }
                .segmented()
            }
            SettingsSection(eyebrow: L10n.text("Opening")) {
                SettingsPicker(L10n.text("Open code in"), selection: $editor) {
                    Text(L10n.text("Automatic")).tag("auto")
                    ForEach(EditorLauncher.installedEditors, id: \.id) { Text($0.name).tag($0.id) }
                    Text("Finder").tag("finder")
                }
                SettingsPicker(selection: $terminal) {
                    ForEach(TerminalLauncher.installed, id: \.id) { Text($0.name).tag($0.id) }
                } label: {
                    SettingLabel(L10n.text("Resume sessions in"), caption: L10n.text("Terminal used by “Resume in Terminal”"))
                }
                SettingsToggle(isOn: $hotkey) {
                    SettingLabel(L10n.text("Show popover with ⌃⌥⌘P"), caption: L10n.text("Global shortcut"))
                }
                .onChange(of: hotkey) { _, enabled in HotKey.shared.setEnabled(enabled) }
            }
            SettingsSection(eyebrow: L10n.text("Terminal")) {
                CommandLineToolRow()
            }
            SettingsSection(eyebrow: L10n.text("Scanning")) {
                SettingsPicker(L10n.text("Scan every"), selection: $scanInterval) {
                    Text(L10n.text("1 second")).tag(1.0)
                    Text(L10n.text("2 seconds")).tag(2.0)
                    Text(L10n.text("5 seconds")).tag(5.0)
                    Text(L10n.text("10 seconds")).tag(10.0)
                }
            }
            SettingsSection {
                SettingsToggle(isOn: Binding(get: { shareUsage }, set: { Usage.setSharing($0) })) {
                    SettingLabel(L10n.text("Share anonymous usage"), caption: L10n.text("Once a day: that the app ran and which features you used"))
                }
            } header: {
                PaneHeader(L10n.text("Privacy"))
            } footer: {
                PaneFooter(L10n.text("Feature names only, like Clean up or Stop. Never your servers, projects, files or anything about your Mac."))
            }
        }
    }
}

/// Installs or removes the `porto` command.
private struct CommandLineToolRow: View {
    @State private var state = CommandLineTool.state
    @State private var error: String?

    var body: some View {
        HStack {
            SettingLabel(L10n.text("porto command"), caption: caption)
            Spacer()
            switch state {
            case .installed:
                Button(L10n.text("Remove")) { run(CommandLineTool.uninstall) }
            case .other:
                Button(L10n.text("Replace…")) { run(CommandLineTool.install) }
            case .notInstalled, .unavailable:
                Button(L10n.text("Install…")) { run(CommandLineTool.install) }
                    .disabled(state == .unavailable)
            }
        }
        // Pick up changes made outside the app, like removing the link by hand.
        .onAppear { state = CommandLineTool.state }
    }

    private var caption: String {
        if let error { return L10n.format("Couldn’t update %@: %@", CommandLineTool.linkPath, error) }
        switch state {
        case .installed: return L10n.text("Type porto in any terminal to see and stop your servers")
        case .notInstalled: return L10n.text("Adds porto to see and stop your servers from any terminal")
        case .unavailable: return L10n.text("Move Porto to Applications to add the porto command")
        case .other(let path):
            return FileManager.default.fileExists(atPath: path)
                ? L10n.format("%@ is another program: %@", CommandLineTool.linkPath, (path as NSString).abbreviatingWithTildeInPath)
                : L10n.text("porto points to a copy of Porto that’s no longer there")
        }
    }

    private func run(_ action: () -> String?) {
        error = action()
        state = CommandLineTool.state
    }
}

// MARK: - Alerts

private struct AlertsPane: View {
    @AppStorage(Preferences.thresholdGB) private var thresholdGB = 2.0
    @AppStorage(Preferences.leakWarnings) private var leakWarnings = true
    @AppStorage(Preferences.snoozeMinutes) private var snoozeMinutes = 60
    @AppStorage(Preferences.startStop) private var startStop = false

    var body: some View {
        SettingsPage {
            SettingsSection(eyebrow: L10n.text("Memory")) {
                SettingsRow(L10n.text("Alert when a server uses more than")) {
                    HStack(spacing: 6) {
                        TextField("", value: $thresholdGB, format: .number.precision(.fractionLength(0...1)))
                            .settingsField(inset: 2.5)
                            .font(Theme.mono)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                            .offset(x: -2.5)
                        Stepper("", value: $thresholdGB, in: 0.5...32, step: 0.5).settingsStepper()
                        Text("GB").font(Theme.mono).foregroundStyle(Theme.text3)
                    }
                    .padding(.top, 2)
                }
                SettingsToggle(isOn: $leakWarnings) {
                    SettingLabel(L10n.text("Warn about leaks"), caption: L10n.text("Grows more than 500 MB in 10 minutes"))
                }
                SettingsPicker(L10n.text("Snooze for"), selection: $snoozeMinutes) {
                    Text(L10n.text("15 minutes")).tag(15)
                    Text(L10n.text("1 hour")).tag(60)
                    Text(L10n.text("4 hours")).tag(240)
                    Text(L10n.text("1 day")).tag(1440)
                }
            }
            SettingsSection(eyebrow: L10n.text("Activity")) {
                SettingsToggle(isOn: $startStop) {
                    SettingLabel(L10n.text("Server started or stopped"), caption: L10n.text("Off by default: dev servers restart a lot"))
                }
            }
            SettingsSection {
                Button(L10n.text("Open Notification Settings…")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

// MARK: - Clean up

private struct CleanUpPane: View {
    @AppStorage(Preferences.cleanUpMode) private var mode = Preferences.CleanUpMode.ask.rawValue
    @AppStorage(Preferences.cleanUpNotify) private var notify = true
    @AppStorage(Preferences.cleanUpDeletedWorktree) private var deletedWorktree = true
    @AppStorage(Preferences.cleanUpIdleHours) private var idleHours = 4
    @AppStorage(Preferences.cleanUpRunningDays) private var runningDays = 3
    @AppStorage(Preferences.forceQuitSeconds) private var forceQuitSeconds = 3.0
    @State private var protected = UserDefaults.standard.stringArray(forKey: Preferences.protectedProcesses) ?? Preferences.defaultProtected

    var body: some View {
        SettingsPage {
            SettingsSection {
                SettingsPicker(selection: $mode) {
                    ForEach(Preferences.CleanUpMode.allCases, id: \.rawValue) { Text(L10n.text($0.label)).tag($0.rawValue) }
                } label: {
                    SettingLabel(L10n.text("When servers qualify"), caption: L10n.text("Ask lists them under Clean up. Automatic stops them for you."))
                }
                .segmented()
                SettingsToggle(isOn: $notify) {
                    SettingLabel(L10n.text("Send a notification"), caption: L10n.text("When new servers qualify, or after they're stopped automatically"))
                }
            }
            SettingsSection(eyebrow: L10n.text("Suggest stopping servers that")) {
                SettingsToggle(L10n.text("Belong to a deleted worktree"), isOn: $deletedWorktree)
                SettingsPicker(selection: $idleHours) {
                    ForEach([1, 2, 4, 8, 24], id: \.self) { Text($0 == 1 ? L10n.text("1 hour") : L10n.format("%d hours", $0)).tag($0) }
                } label: {
                    SettingLabel(L10n.text("Have been idle for"), caption: L10n.text("No CPU and no open connections"))
                }
                SettingsPicker(L10n.text("Have been running for"), selection: $runningDays) {
                    ForEach([1, 3, 7, 14], id: \.self) { Text($0 == 1 ? L10n.text("1 day") : L10n.format("%d days", $0)).tag($0) }
                }
            }
            SettingsSection(eyebrow: L10n.text("Never stop")) {
                SettingsRow(L10n.text("Protected processes")) { TokenEditor(tokens: $protected) }
                    .onChange(of: protected) { _, value in UserDefaults.standard.set(value, forKey: Preferences.protectedProcesses) }
            }
            SettingsSection(eyebrow: L10n.text("Stopping")) {
                SettingsPicker(selection: $forceQuitSeconds) {
                    ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { Text(L10n.format("%d seconds", Int($0))).tag($0) }
                } label: {
                    SettingLabel(L10n.text("Force quit after"), caption: L10n.text("Sends SIGTERM to the whole process tree first"))
                }
            }
        }
    }
}

// MARK: - Autopilot

private struct AutopilotPane: View {
    @ObservedObject private var autopilot = AutopilotController.shared
    @AppStorage(Preferences.autopilotMode) private var mode = Preferences.AutopilotMode.ask.rawValue
    @AppStorage(Preferences.autopilotMemoryPercent) private var memoryPercent = 90
    @AppStorage(Preferences.autopilotCPUPercent) private var cpuPercent = 90
    @AppStorage(Preferences.autopilotIdleMinutes) private var idleMinutes = 30
    @AppStorage(Preferences.autopilotUseKalon) private var useKalon = true
    @State private var kalonLine = L10n.text("Checking…")

    var body: some View {
        SettingsPage {
            SettingsSection {
                SettingsPicker(selection: $mode) {
                    ForEach(Preferences.AutopilotMode.allCases, id: \.rawValue) { Text(L10n.text($0.label)).tag($0.rawValue) }
                } label: {
                    SettingLabel(L10n.text("When the Mac runs short"), caption: L10n.text("Ask first sends a notification. Automatic acts, then tells you."))
                }
                .segmented()
            } footer: {
                PaneFooter(L10n.text("Autopilot never touches databases, model servers, servers with open connections or recent requests, or anything you marked Keep running."))
            }
            SettingsSection {
                percentRow(L10n.text("Act when memory reaches"), value: $memoryPercent)
                percentRow(L10n.text("Act when CPU reaches"), value: $cpuPercent)
                SettingsPicker(selection: $idleMinutes) {
                    Text(L10n.text("15 minutes")).tag(15)
                    Text(L10n.text("30 minutes")).tag(30)
                    Text(L10n.text("1 hour")).tag(60)
                    Text(L10n.format("%d hours", 2)).tag(120)
                } label: {
                    SettingLabel(L10n.text("Stop servers idle for"), caption: L10n.text("Under memory pressure, largest first. Under CPU pressure Autopilot pauses instead."))
                }
            }
            SettingsSection {
                SettingsToggle(isOn: $useKalon) {
                    SettingLabel(L10n.text("Ask Kalon for advice"), caption: kalonLine)
                }
            } footer: {
                PaneFooter(L10n.text("Kalon sees ports, project names and usage numbers only, and can only pick among servers the rules already allow."))
            }
            SettingsSection(eyebrow: L10n.text("Recent actions")) {
                let entries = Array(autopilot.log.suffix(10).reversed())
                if entries.isEmpty {
                    HStack(spacing: 10) {
                        DotGridView(glyph: .idle, size: 16)
                        Text(L10n.text("Nothing yet")).foregroundStyle(Theme.text3)
                    }
                } else {
                    ForEach(entries) { entry in row(entry) }
                }
            }
        }
        .task {
            // Live while the pane is open.
            while !Task.isCancelled {
                kalonLine = Self.describe(await autopilot.refreshKalonStatus())
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func percentRow(_ title: String, value: Binding<Int>) -> some View {
        SettingsRow(title) {
            HStack(spacing: 6) {
                Text("\(value.wrappedValue)%").font(Theme.monoMedium).foregroundStyle(Theme.text1)
                    .contentTransition(.numericText())
                    .animation(Theme.Motion.quick, value: value.wrappedValue)
                Stepper("", value: value, in: 70...98).settingsStepper()
            }
        }
    }

    private func row(_ entry: AutopilotLogEntry) -> some View {
        AutopilotLogRow(entry: entry) {
            if entry.outcome == .asked {
                Button(L10n.text("Approve")) { autopilot.approve(entry.id) }
            } else if entry.verb == .pause, entry.outcome == .done, let key = entry.key, autopilot.paused[key] != nil {
                Button(L10n.text("Resume")) { autopilot.resume(port: key.port) }
            } else if autopilot.canUndo(entry) {
                Button(L10n.text("Undo")) { autopilot.undo(entry.id) }
            }
        }
    }

    private static func describe(_ status: KalonStatus?) -> String {
        guard let status else {
            let isOpen = !NSRunningApplication.runningApplications(withBundleIdentifier: KalonFamily.bundleIdentifier).isEmpty
            return isOpen ? L10n.text("Kalon API server is off") : L10n.text("Kalon not running")
        }
        let name = [status.flavor.rawValue, status.version].compactMap { $0 }.joined(separator: " ")
        return status.isBusy ? L10n.format("%@ · busy", name) : L10n.format("%@ · ready", name)
    }
}

// MARK: - Ports & processes

private struct PortsPane: View {
    @ObservedObject var monitor: ServerMonitor
    @State private var minPort = 3000
    @State private var maxPort = 65535
    @State private var processes: [String] = []

    var body: some View {
        SettingsPage {
            SettingsSection(eyebrow: L10n.text("Ports")) {
                SettingsRow(L10n.text("Watch ports")) {
                    HStack(spacing: 6) {
                        TextField("", value: $minPort, format: .number.grouping(.never)).settingsField(inset: 2.5).frame(width: 64)
                        Text(L10n.text("to")).font(Theme.body).foregroundStyle(Theme.text3).offset(x: 2.5)
                        TextField("", value: $maxPort, format: .number.grouping(.never)).settingsField(inset: 2.5).frame(width: 64)
                    }
                    .padding(.top, 2)
                    .padding(.trailing, 2.5)
                    .font(Theme.mono)
                    .multilineTextAlignment(.trailing)
                }
                .onSubmit(commitPorts)
            }
            SettingsSection {
                SettingsRow(L10n.text("Watch processes")) { TokenEditor(tokens: $processes) }
                    .onChange(of: processes) { _, value in
                        if Set(value) != monitor.allowlist { monitor.setAllowlist(Set(value)) }
                    }
                Button(L10n.text("Reset to defaults")) {
                    monitor.resetAllowlist()
                    processes = monitor.allowlist.sorted()
                }
            } header: {
                PaneHeader(L10n.text("Processes"))
            } footer: {
                PaneFooter(L10n.text("Only servers run by these processes show up."))
            }
        }
        .onAppear {
            minPort = monitor.minPort
            maxPort = monitor.maxPort
            processes = monitor.allowlist.sorted()
        }
        .onDisappear(perform: commitPorts)
    }

    private func commitPorts() {
        let low = max(1, min(minPort, maxPort))
        let high = min(65535, max(minPort, maxPort))
        if low != monitor.minPort || high != monitor.maxPort { monitor.setPortRange(min: low, max: high) }
    }
}

// MARK: - Integrations

private struct IntegrationsPane: View {
    @AppStorage(Preferences.linkClaude) private var claude = true
    @AppStorage(Preferences.linkCodex) private var codex = true
    @AppStorage(Preferences.linkConductor) private var conductor = true
    @AppStorage(Preferences.showBranches) private var branches = true
    @AppStorage(Preferences.vercelPreviews) private var previews = false
    @AppStorage(Preferences.githubPullRequests) private var pullRequests = false

    var body: some View {
        SettingsPage {
            SettingsSection(eyebrow: L10n.text("Coding agents")) {
                SettingsToggle(isOn: $claude) {
                    SettingLabel("Claude Code", caption: ToolDetection.claude ? L10n.text("Link servers to the session that started them") : L10n.text("Not found in ~/.claude"))
                }
                SettingsToggle(isOn: $codex) {
                    SettingLabel("Codex", caption: ToolDetection.codex ? L10n.text("Link servers to Codex threads") : L10n.text("Not found in ~/.codex"))
                }
                SettingsToggle(isOn: $conductor) {
                    SettingLabel("Conductor", caption: ToolDetection.conductor ? L10n.text("Show workspace names") : L10n.text("Not installed"))
                }
            }
            SettingsSection(eyebrow: "Git") {
                SettingsToggle(L10n.text("Show branch names"), isOn: $branches)
            }
            SettingsSection {
                SettingsToggle(isOn: $previews) {
                    SettingLabel(L10n.text("Vercel previews"), caption: L10n.text("Preview button for each branch, from Vercel's GitHub deployments"))
                }
                SettingsToggle(isOn: $pullRequests) {
                    SettingLabel(L10n.text("Pull requests"), caption: L10n.text("Show the pull request for each branch"))
                }
            } header: {
                PaneHeader("GitHub")
            } footer: {
                PaneFooter(GitHubLookup.isAvailable ? L10n.text("Uses the GitHub CLI you're already signed in to.") : L10n.text("Needs the GitHub CLI (gh), which wasn't found."))
            }
            .disabled(!GitHubLookup.isAvailable)
            SettingsSection {
                PaneFooter(L10n.text("Agent and Git details come from local files only. The GitHub options above and app update checks use the network."))
            }
        }
    }
}

enum ToolDetection {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static var claude: Bool { FileManager.default.fileExists(atPath: home + "/.claude/projects") }
    static var codex: Bool { FileManager.default.fileExists(atPath: home + "/.codex/sessions") }
    static var conductor: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.conductor.app") != nil
            || FileManager.default.fileExists(atPath: home + "/Library/Application Support/com.conductor.app")
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject private var updater = Updater.shared

    private var version: String {
        AppInfo.build.map { L10n.format("Version %@ (%@)", AppInfo.version, $0) } ?? L10n.format("Version %@", AppInfo.version)
    }

    var body: some View {
        SettingsPage {
            SettingsSection {
                VStack(spacing: 0) {
                    AppIconView(size: 80)
                    Text("Porto").font(Theme.displaySans).foregroundStyle(Theme.text1)
                        .padding(.top, Theme.Space.m)
                    Text(L10n.text("Every dev server on your Mac, in the menu bar."))
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Space.xxs)
                    // The version, set like a part number.
                    Text(version).font(Theme.monoCaption).foregroundStyle(Theme.text2)
                        .padding(.horizontal, Theme.Space.xs)
                        .frame(height: 22)
                        .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 1))
                        .textSelection(.enabled)
                        .padding(.top, Theme.Space.s)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.m)
            }
            SettingsSection(eyebrow: L10n.text("Updates")) {
                if let reason = updater.unavailableReason {
                    Text(reason).foregroundStyle(Theme.text3)
                } else {
                    SettingsToggle(L10n.text("Automatically check for updates"),
                           isOn: Binding(get: { updater.automaticallyChecksForUpdates }, set: updater.setAutomaticallyChecksForUpdates))
                    SettingsToggle(isOn: Binding(get: { updater.automaticallyDownloadsUpdates }, set: updater.setAutomaticallyDownloadsUpdates)) {
                        SettingLabel(L10n.text("Download and install updates automatically"),
                                     caption: L10n.text("Installs when you quit. Some updates may ask to restart the app."))
                    }
                    .disabled(!updater.automaticallyChecksForUpdates)
                }
                HStack {
                    Button(L10n.text("Check for Updates…"), action: updater.checkForUpdates).disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let date = updater.lastUpdateCheckDate {
                        Text(L10n.format("Last checked %@", date.formatted(.dateTime.locale(L10n.locale)))).font(Theme.caption).foregroundStyle(Theme.text3)
                    }
                }
            }
            SettingsSection {
                ExternalLinkRow(label: L10n.text("Report a bug"), value: "GitHub Issues", url: FeedbackLink.issue(.bug))
                ExternalLinkRow(label: L10n.text("Suggest a feature"), value: "GitHub Issues", url: FeedbackLink.issue(.feature))
            } header: {
                PaneHeader(L10n.text("Feedback"))
            } footer: {
                PaneFooter(L10n.text("Opens a new issue with your app and macOS versions filled in. Nothing is sent until you submit it."))
            }
            if let tip = AppInfo.tipJar {
                SettingsSection {
                    ExternalLinkRow(label: L10n.text("Enjoying Porto?"), value: L10n.text("Tip jar"), url: tip)
                } header: {
                    PaneHeader(L10n.text("Support"))
                } footer: {
                    PaneFooter(L10n.text("Porto is free and open source. If it saves you time, you can leave a tip of any amount."))
                }
            }
            SettingsSection(eyebrow: L10n.text("Links")) {
                if let website = AppInfo.website {
                    ExternalLinkRow(label: L10n.text("Website"), value: website.host ?? website.absoluteString, url: website)
                }
                ExternalLinkRow(label: "GitHub", value: AppInfo.repository.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), url: AppInfo.repository)
            }
        }
    }
}

// MARK: - Shared

/// A form row that opens a URL, with a secondary value and an outward arrow.
struct ExternalLinkRow: View {
    let label: String
    let value: String
    let url: URL
    @State private var isHovered = false

    var body: some View {
        Link(destination: url) {
            SettingsRow(label) {
                HStack(spacing: 8) {
                    Text(value).font(Theme.mono)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(isHovered ? Theme.text1 : Theme.text2)
                .offset(y: 1)
            }
            .offset(y: -0.5)
            .frame(minHeight: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(url.absoluteString)
    }
}

/// A title with an optional caption underneath, for form rows.
struct SettingLabel: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).foregroundStyle(Theme.text1)
                .alignmentGuide(.settingsFirstLine) { $0[VerticalAlignment.center] }
            if let caption {
                Text(caption).font(Theme.caption).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A section's heading, in the same tracked capitals as the popover's labels.
struct PaneHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Eyebrow(title).padding(.bottom, 2)
    }
}

/// A section's footnote: leading-aligned under its card, the full width of it.
struct PaneFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(Theme.text3)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One thing Autopilot did or wants to do: a mark for the verb, what and why,
/// and the way to approve or reverse it.
struct AutopilotLogRow<Action: View>: View {
    let entry: AutopilotLogEntry
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).foregroundStyle(Theme.text1).lineLimit(1).truncationMode(.middle).help(entry.title)
                HStack(spacing: 6) {
                    Text(L10n.time(entry.time)).font(Theme.monoCaption).foregroundStyle(Theme.text2)
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.text3).lineLimit(1).help(detail)
                    if let outcome = entry.outcomeLabel {
                        Text(outcome).font(Theme.captionMedium).foregroundStyle(tint).fixedSize()
                    }
                }
            }
            Spacer(minLength: Theme.Space.xs)
            action
        }
    }

    private var detail: String {
        [entry.reason, entry.sourceLabel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var symbol: String {
        switch entry.verb {
        case .pause: return "pause.fill"
        case .stop: return "stop.fill"
        case .resume: return "play.fill"
        case .unload: return "eject.fill"
        }
    }

    /// Amber while it waits on you, red when it failed; everything settled is neutral.
    private var tint: Color {
        switch entry.outcome {
        case .asked: return Theme.amber
        case .failed: return Theme.softRed
        default: return Theme.text2
        }
    }
}

/// An editable list of process names, shown as removable chips.
struct TokenEditor: View {
    @Binding var tokens: [String]
    @State private var draft = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                TokenChip(token: token) { tokens.removeAll { $0 == token } }
            }
            // The prompt sits inside the field, so there is no title beside it.
            TextField("", text: $draft, prompt: Text(L10n.text("Add…")))
                .labelsHidden()
                .accessibilityLabel(L10n.text("Add…"))
                .settingsField()
                .font(Theme.body)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .frame(width: 88)
                .onSubmit {
                    let value = draft.trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty, !tokens.contains(value) { tokens.append(value) }
                    draft = ""
                }
        }
        .frame(maxWidth: 320, alignment: .trailing)
        // The grouped form sat the chips a point high in their row.
        .padding(.top, -1)
    }
}

/// A process name with its remove button: an outlined chip, never a grey one.
private struct TokenChip: View {
    let token: String
    let remove: () -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        HStack(spacing: 2) {
            Text(token).font(Theme.mono).foregroundStyle(Theme.text1)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isHovered ? Theme.text1 : Theme.text3)
                    .frame(width: 18, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Remove"))
            .accessibilityLabel(L10n.text("Remove") + " " + token)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .frame(height: 22)
        .background(isHovered ? Theme.hover : .clear, in: shape)
        .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
        .onHover { isHovered = $0 }
    }
}

/// Wraps its children onto new lines, right-aligned, like a token field.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? 320)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.maxX - row.width
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
