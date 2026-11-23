import ServiceManagement
import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome, leaks, tools, vercel, terminal, usage, done
}

struct OnboardingView: View {
    @ObservedObject var monitor: ServerMonitor
    @StateObject var status = OnboardingStatus()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State var step: OnboardingStep = .welcome
    /// Shows only the usage step, for people who onboarded before it existed.
    var usageOnly = false
    var close: () -> Void = {}

    @AppStorage(Preferences.language) private var language = InterfaceLanguage.system.rawValue
    @AppStorage(Preferences.onboarded) private var onboarded = false
    @AppStorage(Preferences.vercelPreviews) private var previews = false
    @AppStorage(Preferences.shareUsage) private var shareUsage = true
    @AppStorage(Preferences.usageAsked) private var usageAsked = false
    @AppStorage(Preferences.thresholdGB) private var thresholdGB = 2.0
    @AppStorage(Preferences.cleanUpIdleHours) private var idleHours = 4
    @State private var hero: DotGlyph = .porthole
    @State private var command = CommandLineTool.state
    @State private var commandError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    DotMatrixView(glyph: hero).frame(height: 112)
                    VStack(spacing: 8) {
                        Text(title).font(Theme.displaySans).foregroundStyle(Theme.text1)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(message)
                            .font(Theme.body)
                            .foregroundStyle(OnboardingStyle.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    card
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .padding(EdgeInsets(top: 40, leading: 32, bottom: 20, trailing: 32))
            }
            SectionDivider()
            HStack {
                if !usageOnly {
                    // Where you are: the current step stretches into a bar, finished ones stay lit.
                    HStack(spacing: 5) {
                        ForEach(OnboardingStep.allCases, id: \.rawValue) { item in
                            Capsule()
                                .fill(item == step ? Theme.text1 : (item.rawValue < step.rawValue ? Theme.text3 : Theme.outline))
                                .frame(width: item == step ? 18 : 6, height: 6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(step.rawValue + 1) / \(OnboardingStep.allCases.count)")
                }
                Spacer()
                HStack(spacing: 8) { actions }
            }
            .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 12))
            .frame(height: 56)
        }
        .frame(width: 480, height: 620)
        .background(Theme.windowBackground)
        .onAppear {
            updateHero(animated: false)
            loadStep()
        }
        .onChange(of: step) { _, _ in
            updateHero(animated: !reduceMotion)
            loadStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from System Settings: re-read permissions.
            if step == .leaks { Task { await status.refreshSetup(force: true) } }
        }
    }

    // MARK: - Copy

    private var title: String {
        switch step {
        case .welcome: return "Porto"
        case .leaks: return L10n.text("Stay ahead of leaks")
        case .tools: return L10n.text("Your tools, at a glance.")
        case .vercel: return L10n.text("Vercel previews")
        case .terminal: return L10n.text("Porto TUI")
        case .usage: return L10n.text("Help shape Porto")
        case .done: return L10n.text("You’re set")
        }
    }

    private var message: String {
        switch step {
        case .welcome: return L10n.text("Every dev server on your Mac, in the menu bar. What it is, what branch it’s on, and what it’s costing you.")
        case .leaks: return L10n.text("Porto warns you when a server starts eating memory. Nothing about your servers leaves your Mac.")
        case .tools: return L10n.text("Porto reads local session files and process info to put your servers in context.")
        case .vercel: return L10n.text("See the preview deployment for whatever branch each server is running. Optional.")
        case .terminal: return L10n.text("Type porto in any terminal to browse, open and stop your servers, with the same details and Clean up. Optional.")
        case .usage: return L10n.text("Share which features you use, once a day. Nothing about your servers, projects or Mac is included.")
        case .done: return L10n.text("The dots settle into the ring in your menu bar. Press ⌃⌥⌘P any time to open it.")
        }
    }

    // MARK: - Cards

    @ViewBuilder private var card: some View {
        switch step {
        case .welcome:
            OnboardingCard {
                OnboardingRow(title: L10n.text("Language")) {
                    Picker(L10n.text("Language"), selection: $language) {
                        ForEach(InterfaceLanguage.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 210)
                }
                RowDivider()
                OnboardingRow(title: monitor.servers.isEmpty
                              ? L10n.text("No servers running right now")
                              : L10n.format("Found %d %@ running", monitor.servers.count, L10n.counted("server", "servers", count: monitor.servers.count))) {
                    Text(monitor.servers.prefix(3).map { ":\($0.port)" }.joined(separator: " ") + (monitor.servers.count > 3 ? " …" : ""))
                        .font(Theme.mono).foregroundStyle(Theme.text2)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        case .leaks:
            VStack(spacing: 18) {
                OnboardingCard {
                    OnboardingSummary(title: status.setupSummary, detail: L10n.format("%d of 2 ready", status.readyCount))
                    RowDivider()
                    OnboardingRow(title: L10n.text("Notifications"),
                                  caption: status.notifications == .action("Not allowed", button: "Settings…") ? L10n.text("Allow in System Settings") : L10n.text("Memory and leak alerts")) {
                        OnboardingConfirmation(state: status.notifications, action: notificationAction)
                    }
                    RowDivider()
                    OnboardingRow(title: L10n.text("Launch at login"),
                                  caption: status.login == .action("Needs approval", button: "Settings…") ? L10n.text("Approve in System Settings") : L10n.text("Opens when you sign in")) {
                        OnboardingConfirmation(state: status.login, action: loginAction)
                    }
                }
                if let error = status.notificationError ?? status.loginError {
                    Text(error).font(OnboardingStyle.label).foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button(L10n.text("You can change these in Settings.")) { openWindow(id: "settings") }
                    .buttonStyle(.plain).font(OnboardingStyle.label).foregroundStyle(OnboardingStyle.secondary)
            }
        case .tools:
            OnboardingCard {
                OnboardingSummary(
                    title: status.isScanning ? L10n.text("Checking this Mac…")
                        : L10n.format("%d %@ detected", status.detectedCount, L10n.counted("tool", "tools", count: status.detectedCount)),
                    detail: status.isScanning ? L10n.format("%d of 4 found", status.detectedCount) : L10n.text("Scan complete")
                )
                ForEach(OnboardingTool.allCases, id: \.self) { tool in
                    RowDivider()
                    OnboardingRow(title: tool.name, icon: AnyView(toolIcon(tool))) {
                        OnboardingConfirmation(state: status.tools[tool] ?? .loading("Checking…"), monospaced: true)
                    }
                }
            }
        case .vercel:
            OnboardingCard {
                OnboardingRow(title: L10n.text("Show preview buttons"),
                              caption: GitHubLookup.isAvailable ? L10n.text("Uses Vercel’s GitHub deployments through gh") : L10n.text("Needs the GitHub CLI (gh)")) {
                    Toggle("", isOn: $previews).labelsHidden().toggleStyle(.switch)
                }
                .disabled(!GitHubLookup.isAvailable)
            }
        case .terminal:
            VStack(spacing: 18) {
                OnboardingCard {
                    OnboardingRow(title: L10n.text("porto command"), caption: commandCaption, icon: AnyView(ToolIcon(systemName: "terminal"))) {
                        OnboardingConfirmation(state: commandState, monospaced: true) {
                            commandError = CommandLineTool.install()
                            command = CommandLineTool.state
                        }
                    }
                }
                if let commandError {
                    Text(commandError).font(OnboardingStyle.label).foregroundStyle(Theme.amber)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button(L10n.text("You can remove it in Settings.")) { openWindow(id: "settings") }
                    .buttonStyle(.plain).font(OnboardingStyle.label).foregroundStyle(OnboardingStyle.secondary)
            }
        case .usage:
            VStack(spacing: 18) {
                OnboardingCard {
                    OnboardingRow(title: L10n.text("Share anonymous usage"), caption: L10n.text("Feature names only, like Clean up or Stop")) {
                        Toggle("", isOn: Binding(get: { shareUsage }, set: { Usage.setSharing($0) })).labelsHidden().toggleStyle(.switch)
                    }
                }
                Button(L10n.text("See exactly what’s sent. You can change this in Settings.")) {
                    NSWorkspace.shared.open(AppInfo.repository.appendingPathComponent("blob/main/app/Sources/Porto/Engine/Usage.swift"))
                }
                .buttonStyle(.plain).font(OnboardingStyle.label).foregroundStyle(OnboardingStyle.secondary)
            }
        case .done:
            OnboardingCard {
                OnboardingRow(title: L10n.text("Alert when a server uses more than")) {
                    HStack(spacing: 6) {
                        TextField("", value: $thresholdGB, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder).font(Theme.mono).multilineTextAlignment(.trailing).frame(width: 48)
                        Text("GB").font(Theme.mono).foregroundStyle(Theme.text3)
                    }
                }
                RowDivider()
                OnboardingRow(title: L10n.text("Suggest cleaning up idle servers after")) {
                    Picker("", selection: $idleHours) {
                        ForEach([1, 2, 4, 8, 24], id: \.self) { Text(L10n.format("%dh", $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    @ViewBuilder private func toolIcon(_ tool: OnboardingTool) -> some View {
        switch tool {
        case .claude: ToolIcon(agent: .claudeCode)
        case .codex: ToolIcon(agent: .codex)
        case .conductor: ToolIcon(systemName: "square.grid.2x2")
        case .github: ToolIcon(systemName: "arrow.triangle.branch")
        }
    }

    private var commandState: OnboardingRowState {
        switch command {
        case .installed: return .success("Installed")
        case .notInstalled: return .action("Not installed", button: "Install…")
        case .other: return .action("Taken", button: "Replace…")
        case .unavailable: return .unavailable("Unavailable")
        }
    }

    private var commandCaption: String {
        switch command {
        case .installed: return L10n.text("Ready in new terminal windows")
        case .notInstalled: return L10n.format("Adds %@", CommandLineTool.linkPath)
        case .other: return L10n.format("%@ is already something else", CommandLineTool.linkPath)
        case .unavailable: return L10n.text("Move Porto to Applications first")
        }
    }

    private func loadStep() {
        // In-flight work survives moving between steps; returning shows cached
        // results instead of replaying a scan. Reads never change preferences.
        switch step {
        case .leaks: Task { await status.refreshSetup() }
        case .tools: Task { await status.scanTools() }
        case .terminal: command = CommandLineTool.state
        default: break
        }
    }

    private func notificationAction() {
        if case .action(_, "Settings…") = status.notifications {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
        } else {
            Task { await status.allowNotifications() }
        }
    }

    private func loginAction() {
        if case .action(_, "Settings…") = status.login {
            SMAppService.openSystemSettingsLoginItems()
        } else {
            Task { await status.addLoginItem() }
        }
    }

    // MARK: - Actions

    @ViewBuilder private var actions: some View {
        switch step {
        case .welcome:
            Button(L10n.text("Get started")) { go(.leaks) }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        case .vercel:
            Button(L10n.text("Back")) { go(.tools) }.buttonStyle(PillButtonStyle())
            Button(L10n.text("Skip")) {
                previews = false
                go(.terminal)
            }
            .buttonStyle(PillButtonStyle())
            Button(L10n.text("Continue")) { go(.terminal) }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        case .usage where usageOnly:
            Button(L10n.text("Done")) { finish() }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        case .done:
            Button(L10n.text("Open Porto")) { finish() }.buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        default:
            Button(L10n.text("Back")) { go(OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome) }.buttonStyle(PillButtonStyle())
            Button(L10n.text("Continue")) { go(OnboardingStep(rawValue: step.rawValue + 1) ?? .done) }
                .buttonStyle(PillButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ next: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { step = next }
    }

    private func finish() {
        onboarded = true
        usageAsked = true
        close()
        if !usageOnly { StatusItemOpener.open() }
    }

    private func updateHero(animated: Bool) {
        switch step {
        case .welcome: hero = .porthole
        case .leaks: hero = .leak
        case .tools: hero = .prompt
        case .vercel: hero = .triangle
        case .terminal: hero = .cursor
        case .usage: hero = .bars
        case .done:
            // The celebration: a spark, a burst, a fade, then the ring settles.
            let frames: [DotGlyph] = [
                DotGlyph(rows: [".....", ".....", "..#..", ".....", "....."]),
                DotGlyph(rows: [".....", "..#..", ".###.", "..#..", "....."]),
                .burst,
                DotGlyph(rows: ["#...#", ".....", ".....", ".....", "#...#"]),
                .porthole,
            ]
            guard animated, !reduceMotion else {
                hero = .porthole
                return
            }
            for (index, frame) in frames.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * Double(index)) {
                    if step == .done { hero = frame }
                }
            }
        }
    }
}

// MARK: - Pieces

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        VStack(spacing: 0) { content }
            .background(OnboardingStyle.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
    }
}

private struct RowDivider: View {
    var body: some View { SectionDivider().padding(.leading, Theme.Space.m) }
}

private struct OnboardingRow<Control: View>: View {
    let title: String
    var caption: String?
    var icon: AnyView?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let icon { icon }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.bodyMedium).foregroundStyle(Theme.text1)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    Text(caption).font(OnboardingStyle.label).foregroundStyle(OnboardingStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, caption == nil ? 10 : 12)
        .frame(minHeight: caption == nil ? 48 : 60)
        .accessibilityElement(children: .contain)
    }
}

/// A tool's mark in an outlined tile: the same hairline as the card around it.
private struct ToolIcon: View {
    var agent: AgentKind?
    var systemName: String?

    init(agent: AgentKind) { self.agent = agent }
    init(systemName: String) { self.systemName = systemName }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Group {
            if let agent {
                AgentGlyph(kind: agent, size: 14, color: Theme.text1)
            } else if let systemName {
                Image(systemName: systemName).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text1)
            }
        }
        .frame(width: 28, height: 28)
        .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
