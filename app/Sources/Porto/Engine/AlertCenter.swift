import AppKit
import UserNotifications

/// Watches scans for servers that need attention and posts notifications with
/// Details, Stop and Snooze. Each alert fires once and re-arms only after its
/// condition clears, so a server hovering at the threshold doesn't nag.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    private enum Kind: String { case memory, leak }
    private enum Action {
        static let category = "server-alert"
        static let details = "details"
        static let stop = "stop"
        static let snooze = "snooze"
    }

    /// What an Autopilot notification offers.
    enum AutopilotNotice: String {
        case ask = "autopilot-ask"
        case paused = "autopilot-paused"
        case stopped = "autopilot-stopped"
        /// Nothing to undo: the server can't be started again, or models were unloaded.
        case done = "autopilot-done"

        static let approve = "autopilot-approve"
        static let decline = "autopilot-decline"
        static let resume = "autopilot-resume"
        static let undo = "autopilot-undo"
    }

    /// How long a server must stay over the threshold before it alerts.
    private let sustainFor: TimeInterval = 30

    private weak var monitor: ServerMonitor?
    private var fired: [String: Set<Kind>] = [:]
    private var overSince: [String: Date] = [:]
    private var snoozedUntil: [Int: Date] = [:]
    private var knownPorts: Set<Int>?

    /// Notifications need a real app bundle; `swift run` and snapshots don't have one.
    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func start(monitor: ServerMonitor) {
        self.monitor = monitor
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Action.category, actions: [
                UNNotificationAction(identifier: Action.details, title: L10n.text("Details"), options: [.foreground]),
                UNNotificationAction(identifier: Action.stop, title: L10n.text("Stop"), options: [.destructive]),
                UNNotificationAction(identifier: Action.snooze, title: L10n.text("Snooze"), options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: AutopilotNotice.ask.rawValue, actions: [
                UNNotificationAction(identifier: AutopilotNotice.approve, title: L10n.text("Approve"), options: []),
                UNNotificationAction(identifier: AutopilotNotice.decline, title: L10n.text("Not now"), options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: AutopilotNotice.paused.rawValue, actions: [
                UNNotificationAction(identifier: AutopilotNotice.resume, title: L10n.text("Resume"), options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: AutopilotNotice.stopped.rawValue, actions: [
                UNNotificationAction(identifier: AutopilotNotice.undo, title: L10n.text("Undo"), options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: AutopilotNotice.done.rawValue, actions: [], intentIdentifiers: []),
        ])
        // Before onboarding, its setup step asks with context instead.
        guard UserDefaults.standard.bool(forKey: Preferences.onboarded) else { return }
        Task {
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func evaluate(_ servers: [Server], threshold: UInt64) {
        let now = Date()
        var live = Set<String>()

        for server in servers where !server.isProtected {
            let key = "\(server.port)-\(server.rootPid)"
            live.insert(key)
            var kinds = fired[key] ?? []

            // Over the threshold for a while. Re-arms below 90% to avoid flapping.
            if server.memory >= threshold {
                let since = overSince[key] ?? now
                overSince[key] = since
                if now.timeIntervalSince(since) >= sustainFor, !kinds.contains(.memory) {
                    kinds.insert(.memory)
                    post(server, kind: .memory,
                         title: L10n.format(":%@ %@ is using %@", String(server.port), server.project.name, Format.bytesString(server.memory)),
                         body: L10n.format("That's over your %@ GB alert. %@", Format.trim(Double(threshold) / Format.gigabyte), context(for: server)))
                }
            } else if Double(server.memory) < Double(threshold) * 0.9 {
                overSince[key] = nil
                kinds.remove(.memory)
            }

            // Fast growth. Re-arms once growth falls back under half the trigger.
            if UserDefaults.standard.bool(forKey: Preferences.leakWarnings), server.isLeaking(), !kinds.contains(.leak) {
                kinds.insert(.leak)
                let window = server.history.first.map { L10n.duration(now.timeIntervalSince($0.time)) } ?? L10n.text("10 min")
                post(server, kind: .leak,
                     title: L10n.format(":%@ %@ is leaking", String(server.port), server.project.name),
                     body: L10n.format("%@ grew %@ in %@ and is now using %@.", server.project.framework ?? L10n.text("It"),
                                       Format.bytesString(UInt64(max(server.memoryGrowth, 0))), window, Format.bytesString(server.memory)))
            } else if server.memoryGrowth < 250_000_000 {
                kinds.remove(.leak)
            }
            fired[key] = kinds
        }

        fired = fired.filter { live.contains($0.key) }
        overSince = overSince.filter { live.contains($0.key) }
        snoozedUntil = snoozedUntil.filter { $0.value > now }
        announceStartStop(servers)
    }

    // MARK: - Posting

    private func post(_ server: Server, kind: Kind, title: String, body: String) {
        guard isAvailable else { return }
        if let until = snoozedUntil[server.port], until > Date() { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Action.category
        content.threadIdentifier = "port-\(server.port)"
        content.userInfo = Self.identity(of: server)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(kind.rawValue)-\(server.port)-\(server.rootPid)", content: content, trigger: nil))
        Usage.record(.memoryAlert)
    }

    /// Which run of a server a notification is about, so Stop never lands on
    /// whatever took over the port since.
    nonisolated static func identity(of server: Server) -> [String: Any] {
        var info: [String: Any] = ["port": server.port, "rootPid": Int(server.rootPid)]
        if let started = server.startedAt { info["startedAt"] = started.timeIntervalSince1970 }
        return info
    }

    /// Whether the server is still the one the notification was posted for.
    nonisolated static func matches(_ server: Server, rootPid: Int?, startedAt: Double?) -> Bool {
        guard let rootPid, let startedAt, Int(server.rootPid) == rootPid, let serverStart = server.startedAt else { return false }
        return abs(serverStart.timeIntervalSince1970 - startedAt) < 1
    }

    /// Autopilot asking first (Approve, Not now), or saying what it did (Resume, Undo).
    func postAutopilot(id: UUID, title: String, body: String, notice: AutopilotNotice) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = notice.rawValue
        content.threadIdentifier = "autopilot"
        content.userInfo = ["autopilot": id.uuidString]
        if notice == .ask { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "autopilot-\(id.uuidString)", content: content, trigger: nil))
    }

    private func announceStartStop(_ servers: [Server]) {
        let ports = Set(servers.map(\.port))
        defer { knownPorts = ports }
        guard let known = knownPorts, isAvailable, UserDefaults.standard.bool(forKey: Preferences.startStop) else { return }
        for server in servers where !known.contains(server.port) {
            let content = UNMutableNotificationContent()
            content.title = L10n.format(":%@ %@ started", String(server.port), server.project.name)
            content.body = context(for: server)
            content.userInfo = Self.identity(of: server)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "start-\(server.port)", content: content, trigger: nil))
        }
        for port in known.subtracting(ports) {
            let content = UNMutableNotificationContent()
            content.title = L10n.format(":%@ stopped", String(port))
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stop-\(port)", content: content, trigger: nil))
        }
    }

    /// "3 servers can be cleaned up" (Ask) or "Stopped 3 servers" (Automatic).
    func announceCleanUp(_ servers: [Server], stopped: Bool) {
        guard isAvailable, !servers.isEmpty else { return }
        let content = UNMutableNotificationContent()
        let count = L10n.format("%d %@", servers.count, L10n.counted("server", "servers", count: servers.count))
        content.title = stopped ? L10n.format("Stopped %@", count) : L10n.format("%@ can be cleaned up", count)
        content.body = servers.map { ":\($0.port) \($0.project.name)" }.joined(separator: ", ")
            + " · " + Format.bytesString(servers.reduce(0) { $0 + $1.memory }) + (stopped ? L10n.text(" freed") : "")
        if servers.count == 1 { content.userInfo = Self.identity(of: servers[0]) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "cleanup-\(Date().timeIntervalSince1970)", content: content, trigger: nil))
    }

    private func context(for server: Server) -> String {
        [server.project.branch, server.agent.map { L10n.format("%@ session", $0.kind.rawValue) }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let port = info["port"] as? Int
        let rootPid = info["rootPid"] as? Int
        let startedAt = info["startedAt"] as? Double
        let autopilot = (info["autopilot"] as? String).flatMap(UUID.init(uuidString:))
        let action = response.actionIdentifier
        Task { @MainActor in
            if let autopilot {
                AutopilotController.shared.handleNotification(action: action, id: autopilot)
            } else {
                self.handle(action: action, port: port, rootPid: rootPid, startedAt: startedAt)
            }
            completionHandler()
        }
    }

    private func handle(action: String, port: Int?, rootPid: Int?, startedAt: Double?) {
        guard let monitor else { return }
        guard let port else {
            StatusItemOpener.open()
            return
        }
        switch action {
        case Action.stop:
            // Only the run the alert was about; the port may belong to something else by now.
            if let server = monitor.server(port: port), Self.matches(server, rootPid: rootPid, startedAt: startedAt),
               ProcessControl.isSameProcess(server.rootPid, startedAt: server.startedAt) {
                Usage.record(.stop)
                monitor.stop(server)
            }
        case Action.snooze:
            let minutes = UserDefaults.standard.integer(forKey: Preferences.snoozeMinutes)
            snoozedUntil[port] = Date().addingTimeInterval(TimeInterval(max(minutes, 1) * 60))
        default:
            // Details, or a click on the notification itself.
            monitor.pendingRoute = .detail(port: port)
            StatusItemOpener.open()
        }
    }
}
