import Foundation
import ServiceManagement
import Testing
import UserNotifications
@testable import Porto

@MainActor
struct OnboardingStatusTests {
    private func services() -> OnboardingServices {
        OnboardingServices(detect: { _ in true }, notifications: { .notDetermined }, requestNotifications: {},
                           login: { .notRegistered }, registerLogin: {})
    }

    @Test func onlyConfirmedStatesReadAsDone() {
        #expect(OnboardingStatus.notificationState(.authorized) == .success("Allowed"))
        #expect(OnboardingStatus.notificationState(.provisional) == .success("Allowed"))
        #expect(OnboardingStatus.notificationState(.notDetermined) == .action("Not allowed", button: "Allow…"))
        #expect(OnboardingStatus.notificationState(.denied) == .action("Not allowed", button: "Settings…"))
        #expect(OnboardingStatus.notificationState(nil) == .unavailable("Unavailable"))
        #expect(OnboardingStatus.loginState(.enabled) == .success("Added"))
        #expect(OnboardingStatus.loginState(.notRegistered) == .action("Not added", button: "Add"))
        #expect(OnboardingStatus.loginState(.requiresApproval) == .action("Needs approval", button: "Settings…"))
        #expect(OnboardingStatus.loginState(.notFound) == .unavailable("Unavailable"))
    }

    @Test func toolsAppearAsEachCheckFinishes() async {
        let gates = Dictionary(uniqueKeysWithValues: OnboardingTool.allCases.map { ($0, Gate<Bool>()) })
        let calls = Locked(0)
        var services = services()
        services.detect = { tool in
            calls.update { $0 += 1 }
            return await gates[tool]!.wait()
        }
        let model = OnboardingStatus(services: services)
        let scan = Task { await model.scanTools() }
        await eventually { calls.value == 4 }

        await gates[.claude]!.resolve(true)
        await eventually { model.tools[.claude] == .success("~/.claude") }
        #expect(model.isScanning)
        #expect(model.detectedCount == 1)
        #expect(model.tools[.github] == nil)

        await gates[.codex]!.resolve(false)
        await gates[.conductor]!.resolve(true)
        await gates[.github]!.resolve(true)
        await scan.value
        #expect(!model.isScanning)
        #expect(model.detectedCount == 3)
        #expect(model.tools[.codex] == .unavailable("Not found"))

        // Results are kept: going back to the step doesn't scan again.
        await model.scanTools()
        #expect(calls.value == 4)
    }

    @Test func refreshingOnlyReads() async {
        let reads = Locked(0)
        var services = services()
        services.notifications = {
            reads.update { $0 += 1 }
            return .authorized
        }
        services.login = { .enabled }
        services.requestNotifications = { Issue.record("Refreshing must not ask for notification permission") }
        services.registerLogin = { Issue.record("Refreshing must not add a login item") }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        await model.refreshSetup()
        #expect(reads.value == 1)
        #expect(model.readyCount == 2)
        #expect(model.setupSummary == L10n.text("Setup complete"))
        await model.refreshSetup(force: true)
        #expect(reads.value == 2)
    }

    @Test func notificationRequestWaitsForTheRealAnswer() async {
        let answer = Gate<Void>()
        let status = Locked(UNAuthorizationStatus.notDetermined)
        let requests = Locked(0)
        var services = services()
        services.notifications = { status.value }
        services.requestNotifications = {
            requests.update { $0 += 1 }
            await answer.wait()
        }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        #expect(model.notifications == .action("Not allowed", button: "Allow…"))

        let request = Task { await model.allowNotifications() }
        await eventually { requests.value == 1 }
        #expect(model.notifications == .loading("Waiting…"))
        // A second click and a refresh while the prompt is up change nothing.
        await model.allowNotifications()
        await model.refreshSetup(force: true)
        #expect(requests.value == 1)
        #expect(model.notifications == .loading("Waiting…"))

        status.update { $0 = .authorized }
        await answer.resolve(())
        await request.value
        #expect(model.notifications == .success("Allowed"))
        #expect(model.notificationError == nil)
    }

    @Test func failedRequestsShowWhatTheSystemSays() async {
        struct Failure: Error {}
        var services = services()
        services.notifications = { .denied }
        services.requestNotifications = { throw Failure() }
        services.login = { .notRegistered }
        services.registerLogin = { throw Failure() }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        // Denied offers Settings…, not another request.
        await model.allowNotifications()
        #expect(model.notifications == .action("Not allowed", button: "Settings…"))
        #expect(model.notificationError == nil)

        await model.addLoginItem()
        #expect(model.login == .action("Not added", button: "Add"))
        #expect(model.loginError != nil)
        #expect(model.readyCount == 0)
    }

    @Test func loginItemThatNeedsApprovalSaysSo() async {
        let registered = Locked(false)
        var services = services()
        services.login = { registered.value ? .requiresApproval : .notRegistered }
        services.registerLogin = { registered.update { $0 = true } }
        let model = OnboardingStatus(services: services)
        await model.refreshSetup()
        await model.addLoginItem()
        #expect(model.login == .action("Needs approval", button: "Settings…"))
        #expect(model.loginError == nil)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(condition())
    }
}

/// Holds a service call until the test lets it finish.
private actor Gate<Value: Sendable> {
    private var value: Value?
    private var waiting: [CheckedContinuation<Value, Never>] = []

    func wait() async -> Value {
        if let value { return value }
        return await withCheckedContinuation { waiting.append($0) }
    }

    func resolve(_ value: Value) {
        self.value = value
        waiting.forEach { $0.resume(returning: value) }
        waiting.removeAll()
    }
}

/// A value the fake services change from any thread.
private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value { lock.withLock { stored } }

    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}
