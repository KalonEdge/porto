import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

enum OnboardingTool: CaseIterable, Hashable, Sendable {
    case claude, codex, conductor, github

    var name: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .conductor: return "Conductor"
        case .github: return "GitHub CLI"
        }
    }

    var evidence: String {
        switch self {
        case .claude: return "~/.claude"
        case .codex: return "~/.codex"
        case .conductor: return "Installed"
        case .github: return "gh"
        }
    }
}

/// One setup row's state. Labels are English keys, localized where shown.
enum OnboardingRowState: Equatable {
    case loading(String)
    case success(String)
    case action(String, button: String)
    case unavailable(String)

    var label: String {
        switch self {
        case .loading(let label), .success(let label), .action(let label, _), .unavailable(let label): return label
        }
    }

    var isLoading: Bool { if case .loading = self { return true }; return false }
    var isSuccess: Bool { if case .success = self { return true }; return false }
}

/// System operations behind onboarding, injectable so discovery stays
/// read-only and tests can exercise every outcome without real prompts.
struct OnboardingServices {
    var detect: @Sendable (OnboardingTool) async -> Bool
    var notifications: @Sendable () async -> UNAuthorizationStatus?
    var requestNotifications: @Sendable () async throws -> Void
    var login: @Sendable () async -> SMAppService.Status
    var registerLogin: @Sendable () async throws -> Void

    static let live = OnboardingServices(
        detect: { tool in
            await Task.detached(priority: .userInitiated) {
                switch tool {
                case .claude: return ToolDetection.claude
                case .codex: return ToolDetection.codex
                case .conductor: return ToolDetection.conductor
                case .github: return GitHubLookup.isAvailable
                }
            }.value
        },
        notifications: {
            guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return nil }
            return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        },
        requestNotifications: {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        },
        login: { await Task.detached(priority: .userInitiated) { SMAppService.mainApp.status }.value },
        registerLogin: { try await Task.detached(priority: .userInitiated) { try SMAppService.mainApp.register() }.value }
    )
}

@MainActor
final class OnboardingStatus: ObservableObject {
    @Published private(set) var tools: [OnboardingTool: OnboardingRowState] = [:]
    @Published private(set) var notifications: OnboardingRowState = .loading("Checking…")
    @Published private(set) var login: OnboardingRowState = .loading("Checking…")
    @Published private(set) var notificationError: String?
    @Published private(set) var loginError: String?
    private let services: OnboardingServices
    private var scanning = false
    private var refreshing = false
    private var requestingNotifications = false
    private var registeringLogin = false
    private var checkedSetup = false
    private var notificationRevision = 0
    private var loginRevision = 0

    init(services: OnboardingServices = .live) { self.services = services }

    var detectedCount: Int { tools.values.filter(\.isSuccess).count }
    var isScanning: Bool { tools.count < OnboardingTool.allCases.count || tools.values.contains(where: \.isLoading) }
    var readyCount: Int { [notifications, login].filter(\.isSuccess).count }
    var setupSummary: String {
        if requestingNotifications { return L10n.text("Waiting for permission…") }
        if registeringLogin { return L10n.text("Saving login item…") }
        if notifications.isLoading || login.isLoading { return L10n.text("Checking setup…") }
        return readyCount == 2 ? L10n.text("Setup complete") : L10n.text("Finish setup")
    }

    func scanTools() async {
        guard !scanning, isScanning else { return }
        scanning = true
        defer { scanning = false }
        // Each check publishes as it finishes, with no fake delay and no slow CLI
        // lookup holding up the folder checks.
        await withTaskGroup(of: Void.self) { group in
            for tool in OnboardingTool.allCases where tools[tool] == nil {
                group.addTask { await self.check(tool) }
            }
        }
    }

    private func check(_ tool: OnboardingTool) async {
        let found = await services.detect(tool)
        guard !Task.isCancelled else { return }
        tools[tool] = found ? .success(tool.evidence) : .unavailable("Not found")
    }

    func refreshSetup(force: Bool = false) async {
        guard !refreshing, force || !checkedSetup else { return }
        refreshing = true
        defer { refreshing = false }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshNotifications() }
            group.addTask { await self.refreshLogin() }
        }
        if !Task.isCancelled { checkedSetup = true }
    }

    private func refreshNotifications() async {
        guard !requestingNotifications else { return }
        let revision = notificationRevision
        let status = await services.notifications()
        // A permission request can start while the read is suspended.
        guard !Task.isCancelled, !requestingNotifications, revision == notificationRevision else { return }
        notifications = Self.notificationState(status)
        notificationError = nil
    }

    private func refreshLogin() async {
        guard !registeringLogin else { return }
        let revision = loginRevision
        let status = await services.login()
        guard !Task.isCancelled, !registeringLogin, revision == loginRevision else { return }
        login = Self.loginState(status)
        loginError = nil
    }

    func allowNotifications() async {
        guard case .action(_, "Allow…") = notifications, !requestingNotifications else { return }
        notificationRevision += 1
        requestingNotifications = true
        defer { requestingNotifications = false }
        notificationError = nil
        notifications = .loading("Waiting…")
        do {
            try await services.requestNotifications()
            notifications = Self.notificationState(await services.notifications())
        } catch {
            // Re-read: a failed request must never show as success.
            notifications = Self.notificationState(await services.notifications())
            if !notifications.isSuccess { notificationError = L10n.text("Couldn’t request notifications. Try again or check System Settings.") }
        }
    }

    func addLoginItem() async {
        guard case .action(_, "Add") = login, !registeringLogin else { return }
        loginRevision += 1
        registeringLogin = true
        defer { registeringLogin = false }
        loginError = nil
        login = .loading("Adding…")
        do {
            try await services.registerLogin()
            login = Self.loginState(await services.login())
        } catch {
            login = Self.loginState(await services.login())
            if !login.isSuccess { loginError = L10n.text("Couldn’t add the login item. Try again or check System Settings.") }
        }
    }

    static func notificationState(_ status: UNAuthorizationStatus?) -> OnboardingRowState {
        switch status {
        case .authorized, .provisional: return .success("Allowed")
        case .notDetermined: return .action("Not allowed", button: "Allow…")
        case .denied: return .action("Not allowed", button: "Settings…")
        default: return .unavailable("Unavailable")
        }
    }

    static func loginState(_ status: SMAppService.Status) -> OnboardingRowState {
        switch status {
        case .enabled: return .success("Added")
        case .notRegistered: return .action("Not added", button: "Add")
        case .requiresApproval: return .action("Needs approval", button: "Settings…")
        case .notFound: return .unavailable("Unavailable")
        @unknown default: return .unavailable("Unavailable")
        }
    }
}

/// Onboarding's palette: the approved dark values, adapted for light mode.
enum OnboardingStyle {
    static let secondary = Theme.adaptive(light: 0x64646C, dark: 0xA5A5AD)
    static let success = Theme.green
    static let surface = Theme.windowBackground
    static let divider = Theme.separator
    static let label = Font.custom("Geist-Regular", fixedSize: 12)
    static let evidence = Font.custom("GeistMono-Regular", fixedSize: 12)
}

struct OnboardingSummary: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Eyebrow(title, color: OnboardingStyle.secondary)
            Spacer(minLength: 8)
            Text(detail).font(Theme.monoCaption).foregroundStyle(OnboardingStyle.secondary)
        }
        .padding(.horizontal, Theme.Space.m)
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}

/// A setup row's trailing status: a label or button, then its dot mark.
struct OnboardingConfirmation: View {
    let state: OnboardingRowState
    var monospaced = false
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if case .action(_, let button) = state {
                    Button(L10n.text(button), action: action)
                        .buttonStyle(PillButtonStyle())
                        .accessibilityLabel("\(L10n.text(button)) — \(L10n.text(state.label))")
                } else {
                    Text(L10n.text(state.label))
                        .font(monospaced && state.isSuccess ? OnboardingStyle.evidence : OnboardingStyle.label)
                        .foregroundStyle(OnboardingStyle.secondary)
                }
            }
            .frame(width: L10n.language == .english ? 92 : 140, alignment: .trailing)
            OnboardingStatusMark(state: state)
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
    }
}

/// Only this 20pt slot animates: a dot spinner while loading, then a check
/// drawn a dot at a time. Confirmed values don't replay when navigating back.
struct OnboardingStatusMark: View {
    let state: OnboardingRowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many frames of the check are drawn.
    @State private var drawn = 0

    var body: some View {
        ZStack {
            if state.isLoading {
                DotSpinner(color: OnboardingStyle.secondary)
                    .transition(.opacity)
            } else if state.isSuccess {
                // The same unlit dots as the spinner, so only the lit dots change.
                DotSpinner(frames: [DotGlyph.checkStrokes[max(drawn, 1) - 1]], color: OnboardingStyle.success,
                           unlitColor: OnboardingStyle.secondary.opacity(0.12))
                    .transition(.opacity)
            } else {
                Image(systemName: "minus.circle").font(.system(size: 14, weight: .medium)).foregroundStyle(OnboardingStyle.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: state.isLoading)
        .onAppear { drawn = state.isSuccess ? DotGlyph.checkStrokes.count : 0 }
        .onChange(of: state.isSuccess) { _, success in
            drawn = success ? (reduceMotion ? DotGlyph.checkStrokes.count : 1) : 0
        }
        .onChange(of: reduceMotion) { _, _ in drawn = state.isSuccess ? DotGlyph.checkStrokes.count : 0 }
        // The next dot every half frame until the check is complete.
        .task(id: drawn) {
            guard (1..<DotGlyph.checkStrokes.count).contains(drawn) else { return }
            try? await Task.sleep(for: .seconds(DotSpinner.frameInterval / 2))
            if !Task.isCancelled { drawn += 1 }
        }
        .accessibilityLabel(state.isLoading ? L10n.text(state.label) : state.isSuccess ? L10n.text("Confirmed") : L10n.text(state.label))
    }
}
