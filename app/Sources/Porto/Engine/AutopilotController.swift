import Foundation

/// One line of Autopilot's history.
struct AutopilotLogEntry: Identifiable {
    enum Verb { case pause, stop, resume, unload }
    enum Source { case rules, kalon, user }
    enum Outcome { case asked, done, failed, skipped, declined, resumed, undone }

    let id = UUID()
    let time: Date
    let verb: Verb
    let name: String
    let key: ServerKey?
    var reason: String
    let source: Source
    var outcome: Outcome

    var title: String {
        // A string, so the port is never grouped like a quantity ("5,173").
        let port = String(key?.port ?? 0)
        switch (verb, outcome) {
        case (.unload, .asked): return L10n.text("Porto wants to unload idle Kalon models")
        case (.unload, _): return L10n.text("Unloaded idle Kalon models")
        case (.stop, .asked): return L10n.format("Porto wants to stop %@ :%@", name, port)
        case (.pause, .asked): return L10n.format("Porto wants to pause %@ :%@", name, port)
        case (.stop, _): return L10n.format("Stopped %@ :%@", name, port)
        case (.pause, _): return L10n.format("Paused %@ :%@", name, port)
        case (.resume, _): return L10n.format("Resumed %@ :%@", name, port)
        }
    }

    var outcomeLabel: String? {
        switch outcome {
        case .asked: return L10n.text("Waiting for approval")
        case .done: return nil
        case .failed: return L10n.text("Failed")
        case .skipped: return L10n.text("No longer idle")
        case .declined: return L10n.text("Not now")
        case .resumed: return L10n.text("Resumed")
        case .undone: return L10n.text("Undone")
        }
    }

    var sourceLabel: String {
        switch source {
        case .rules: return L10n.text("Rules")
        case .kalon: return "Kalon"
        case .user: return L10n.text("You")
        }
    }
}

/// Runs the Autopilot policy after every scan in the menu bar app: asks or
/// acts, keeps track of what it paused so that always gets resumed, and
/// consults Kalon off the scan path when there's a choice to make.
@MainActor
final class AutopilotController: ObservableObject {
    static let shared = AutopilotController()
    static let logLimit = 50

    @Published private(set) var log: [AutopilotLogEntry] = []
    /// Servers Autopilot has paused, with every process it stopped.
    @Published private(set) var paused: [ServerKey: [pid_t: Date]] = [:]
    @Published private(set) var kalonStatus: KalonStatus?

    private weak var monitor: ServerMonitor?
    private let kalon = KalonClient.shared
    private var state = AutopilotState()
    private var kalonCheckedAt = Date.distantPast
    /// Kalon's answer for the current decision; `advice` is nil when it had none.
    private var consulted: (advice: KalonAdvice?, until: Date)?
    private var adviceTask: Task<Void, Never>?
    private var asks: [UUID: (action: AutopilotAction, server: Server?)] = [:]
    private var stopped: [UUID: Server] = [:]
    private var terminationSource: DispatchSourceSignal?

    private var defaults: UserDefaults { .standard }

    /// Called once by the menu bar app. Anything a previous run left paused
    /// (a crash, a force quit) runs again before the first scan.
    func start(monitor: ServerMonitor) {
        self.monitor = monitor
        for entry in defaults.array(forKey: Preferences.autopilotPaused) as? [[String: Any]] ?? [] {
            ProcessControl.resume(Self.processes(from: entry))
        }
        defaults.removeObject(forKey: Preferences.autopilotPaused)

        // `kill` and logout send SIGTERM, which skips applicationWillTerminate.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { AutopilotController.shared.resumeAll() }
            exit(0)
        }
        source.resume()
        terminationSource = source
    }

    // MARK: - Every scan

    func evaluate(_ servers: [Server], memory: SystemMemory, pressure: MemoryPressure, cpu: Double?) {
        let now = Date()
        let settings = AutopilotSettings.saved(in: defaults)
        reconcile(servers)
        guard settings.mode != .off else {
            if !paused.isEmpty { resumeAll() }
            state = AutopilotState()
            return
        }
        // Transcripts and Kalon are only worth a close look once something is near a threshold.
        let strained = pressure >= .warning || memory.usedPercent >= settings.memoryPercent - AutopilotPolicy.memoryMargin
            || (cpu ?? 0) >= settings.cpuPercent
        refreshKalon(servers: servers, settings: settings, strained: strained, now: now)
        let snapshot = snapshot(servers, memory: memory, pressure: pressure, cpu: cpu, transcripts: strained, now: now)
        state.paused = Set(paused.keys)
        state.observe(snapshot, settings: settings)
        if let consulted, consulted.until < now { self.consulted = nil }

        var actions = AutopilotPolicy.decide(snapshot, state: state, settings: settings, now: now, advice: consulted?.advice)
        let needsChoice = actions.contains { $0.isPauseOrStop }
        if needsChoice, consulted == nil, settings.useKalon, kalonStatus != nil,
           let candidates = AutopilotPolicy.candidates(snapshot, state: state, settings: settings, now: now), candidates.servers.count > 1 {
            // Hold the action until Kalon has answered or given up; a later scan picks it up.
            if adviceTask == nil { consult(candidates, snapshot: snapshot, servers: servers, memory: memory) }
            actions.removeAll { $0.isPauseOrStop }
        }

        for action in actions {
            switch action {
            case .resume(let key):
                resume(key, source: .rules, reason: L10n.text("Pressure eased"))
            case .unloadKalonModels:
                state.record(action, at: now)
                let entry = append(.unload, name: "Kalon", key: nil, reason: L10n.text("Memory pressure"), source: .rules,
                                   outcome: settings.mode == .ask ? .asked : .done)
                if settings.mode == .ask {
                    asks[entry] = (action, nil)
                    AlertCenter.shared.postAutopilot(id: entry, title: L10n.text("Porto wants to unload idle Kalon models"),
                                                     body: L10n.text("Memory pressure"), notice: .ask)
                } else {
                    unloadKalonModels(entry: entry)
                }
            case .pause(let key), .stop(let key):
                guard let server = servers.first(where: { $0.key == key }) else { continue }
                let advised = AutopilotPolicy.isAdvised(action, advice: consulted?.advice)
                var reason = Self.reason(for: action, server: server)
                if advised, let text = consulted?.advice?.reason, !text.isEmpty { reason += " · Kalon: " + text }
                consulted = nil
                state.record(action, memory: server.memory, at: now)
                let entry = append(action.verb, name: server.project.name, key: key, reason: reason, source: advised ? .kalon : .rules,
                                   outcome: settings.mode == .ask ? .asked : .done)
                if settings.mode == .ask {
                    asks[entry] = (action, server)
                    AlertCenter.shared.postAutopilot(id: entry, title: title(of: entry), body: reason, notice: .ask)
                } else {
                    perform(action, server: server, entry: entry, notify: true)
                }
            }
        }
    }

    private func snapshot(_ servers: [Server], memory: SystemMemory, pressure: MemoryPressure, cpu: Double?,
                          transcripts: Bool, now: Date) -> AutopilotSnapshot {
        let kalonCPU = servers.filter { $0.kind == .ai }.map(\.cpu).max() ?? 0
        return AutopilotSnapshot(
            servers: servers.map { server in
                let modified = transcripts ? server.agent?.transcript.flatMap {
                    try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                } : nil
                return AutopilotServer(server, now: now, transcriptModifiedAt: modified)
            },
            pressure: pressure, memoryUsedPercent: memory.usedPercent, memoryTotal: memory.total, systemCPU: cpu,
            kalonBusy: kalonStatus.map { $0.isBusy || kalonCPU >= KalonClient.busyCPU })
    }

    /// Forgets paused servers that went away, so nothing is resumed by a stale pid.
    private func reconcile(_ servers: [Server]) {
        let gone = paused.keys.filter { key in
            !servers.contains { $0.key == key } || !ProcessControl.isSameProcess(key.rootPid, startedAt: key.startedAt)
        }
        guard !gone.isEmpty else { return }
        gone.forEach { paused[$0] = nil }
        persist()
    }

    // MARK: - Kalon

    private func refreshKalon(servers: [Server], settings: AutopilotSettings, strained: Bool, now: Date) {
        guard servers.contains(where: { $0.kind == .ai }) || (settings.useKalon && strained),
              now.timeIntervalSince(kalonCheckedAt) >= (strained ? 10 : 60) else { return }
        kalonCheckedAt = now
        Task { kalonStatus = await kalon.status() }
    }

    /// For Settings, which shows the status live.
    func refreshKalonStatus() async -> KalonStatus? {
        kalonCheckedAt = Date()
        kalonStatus = await kalon.status()
        return kalonStatus
    }

    private func consult(_ candidates: (verb: AutopilotPolicy.Verb, servers: [AutopilotServer]), snapshot: AutopilotSnapshot,
                         servers: [Server], memory: SystemMemory) {
        let described = candidates.servers.map { candidate in
            KalonCandidate(port: candidate.key.port, name: candidate.name, memoryMB: Int(candidate.memory / 1_048_576), cpu: candidate.cpu,
                           idleMinutes: Int(candidate.idleFor / 60), connections: candidate.connections,
                           uptimeMinutes: Int((candidate.key.startedAt.map { Date().timeIntervalSince($0) } ?? 0) / 60))
        }
        let pressure = snapshot.pressure
        let cpuBound = candidates.verb == .pause
        let free = memory.free
        adviceTask = Task {
            let advice = await kalon.advise(candidates: described, pressure: pressure, cpuBound: cpuBound, freeMemory: free)
            consulted = (advice, Date().addingTimeInterval(30))
            adviceTask = nil
        }
    }

    private func unloadKalonModels(entry: UUID) {
        let cpu = monitor?.servers.filter { $0.kind == .ai }.map(\.cpu).max() ?? 0
        Task {
            let names = await kalon.unloadIdlePoolModels(processCPU: cpu)
            update(entry) {
                $0.outcome = .done
                $0.reason = names.isEmpty ? L10n.text("Nothing to unload") : names.joined(separator: ", ")
            }
        }
    }

    // MARK: - Acting

    private func perform(_ action: AutopilotAction, server: Server, entry: UUID, notify: Bool) {
        // The scan this was decided on may be seconds or minutes old by now.
        guard let live = monitor?.server(port: server.port), live.key == server.key, isStillFair(live, for: action),
              ProcessControl.isSameProcess(live.rootPid, startedAt: live.startedAt) else {
            update(entry) { $0.outcome = .skipped }
            return
        }
        switch action {
        case .pause:
            guard ProcessControl.pause(live) else {
                update(entry) { $0.outcome = .failed }
                return
            }
            paused[live.key] = live.processStarts
            persist()
            update(entry) { $0.outcome = .done }
            if notify { AlertCenter.shared.postAutopilot(id: entry, title: title(of: entry), body: reason(of: entry), notice: .paused) }
            monitor?.scan()
        case .stop:
            stopped[entry] = live
            let canUndo = live.launch != nil && live.cwdExists
            ProcessControl.stop(live) { [weak self] outcome in
                self?.update(entry) { $0.outcome = outcome == .stopped ? .done : .failed }
                self?.monitor?.scan()
            }
            update(entry) { $0.outcome = .done }
            if notify { AlertCenter.shared.postAutopilot(id: entry, title: title(of: entry), body: reason(of: entry), notice: canUndo ? .stopped : .done) }
        default:
            break
        }
    }

    /// The gates again, on the server as it is now. A shared tree, a
    /// connection or fresh activity since the decision all call it off.
    private func isStillFair(_ server: Server, for action: AutopilotAction) -> Bool {
        guard server.sharesTreeWith.isEmpty, !server.isProtected, server.kind == .dev, let monitor else { return false }
        let now = Date()
        let settings = AutopilotSettings.saved(in: defaults)
        let snapshot = snapshot(monitor.servers, memory: monitor.systemMemory ?? SystemMemory(total: 0, used: 0), pressure: monitor.memoryPressure,
                                cpu: monitor.systemCPU, transcripts: true, now: now)
        guard let current = snapshot.servers.first(where: { $0.key == server.key }) else { return false }
        // The ask itself started the cooldown; it doesn't count against carrying it out.
        var fresh = state
        fresh.lastActed[server.key] = nil
        fresh.paused.remove(server.key)
        var verb = AutopilotPolicy.Verb.pause
        if case .stop = action {
            guard current.idleFor >= TimeInterval(settings.idleMinutes) * 60 else { return false }
            verb = .stop
        }
        return AutopilotPolicy.passesGates(current, verb: verb, active: AutopilotPolicy.activeServers(in: snapshot),
                                           state: fresh, settings: settings, now: now)
    }

    // MARK: - Answers

    func handleNotification(action: String, id: UUID) {
        switch action {
        case AlertCenter.AutopilotNotice.approve: approve(id)
        case AlertCenter.AutopilotNotice.decline: decline(id)
        case AlertCenter.AutopilotNotice.resume: if let key = entry(id)?.key { resume(key, source: .user, reason: "") }
        case AlertCenter.AutopilotNotice.undo: undo(id)
        default: StatusItemOpener.open()
        }
    }

    func approve(_ id: UUID) {
        guard let ask = asks.removeValue(forKey: id) else { return }
        if let server = ask.server {
            perform(ask.action, server: server, entry: id, notify: false)
        } else {
            unloadKalonModels(entry: id)
        }
    }

    func decline(_ id: UUID) {
        guard asks.removeValue(forKey: id) != nil else { return }
        update(id) { $0.outcome = .declined }
    }

    /// Starts a stopped server again with the command it was running.
    func undo(_ id: UUID) {
        guard let server = stopped.removeValue(forKey: id) else { return }
        ProcessControl.restart(server) { [weak self] launched in
            self?.update(id) { $0.outcome = launched ? .undone : .failed }
            self?.monitor?.scan()
        }
    }

    func canUndo(_ entry: AutopilotLogEntry) -> Bool {
        entry.verb == .stop && entry.outcome == .done && stopped[entry.id].map { $0.launch != nil && $0.cwdExists } == true
    }

    // MARK: - Paused servers

    func isPaused(_ server: Server) -> Bool { paused[server.key] != nil }

    /// Opening a paused server, in the popover or the browser, brings it back.
    func resume(port: Int) {
        guard let key = paused.keys.first(where: { $0.port == port }) else { return }
        resume(key, source: .user, reason: L10n.text("You opened it"))
    }

    private func resume(_ key: ServerKey, source: AutopilotLogEntry.Source, reason: String) {
        guard let processes = paused.removeValue(forKey: key) else { return }
        ProcessControl.resume(processes)
        persist()
        state.record(.resume(key), at: Date())
        for index in log.indices where log[index].key == key && log[index].verb == .pause && log[index].outcome == .done {
            log[index].outcome = .resumed
        }
        let name = monitor?.servers.first { $0.key == key }?.project.name ?? log.last { $0.key == key }?.name ?? ""
        append(.resume, name: name, key: key, reason: reason, source: source, outcome: .done)
        monitor?.scan()
    }

    /// On quit, and when Autopilot is turned off: nothing stays paused behind Porto's back.
    func resumeAll() {
        for processes in paused.values { ProcessControl.resume(processes) }
        for index in log.indices where log[index].verb == .pause && log[index].outcome == .done { log[index].outcome = .resumed }
        paused = [:]
        persist()
    }

    private func persist() {
        guard !paused.isEmpty else { return defaults.removeObject(forKey: Preferences.autopilotPaused) }
        defaults.set(paused.map { key, processes -> [String: Any] in
            ["port": key.port, "pid": Int(key.rootPid), "start": key.startedAt?.timeIntervalSince1970 ?? 0,
             "processes": Dictionary(uniqueKeysWithValues: processes.map { (String($0.key), $0.value.timeIntervalSince1970) })]
        }, forKey: Preferences.autopilotPaused)
    }

    private static func processes(from entry: [String: Any]) -> [pid_t: Date] {
        var result: [pid_t: Date] = [:]
        for (pid, start) in entry["processes"] as? [String: Double] ?? [:] {
            if let pid = pid_t(pid) { result[pid] = Date(timeIntervalSince1970: start) }
        }
        return result
    }

    // MARK: - Log

    @discardableResult
    private func append(_ verb: AutopilotLogEntry.Verb, name: String, key: ServerKey?, reason: String,
                        source: AutopilotLogEntry.Source, outcome: AutopilotLogEntry.Outcome) -> UUID {
        let entry = AutopilotLogEntry(time: Date(), verb: verb, name: name, key: key, reason: reason, source: source, outcome: outcome)
        log.append(entry)
        for dropped in log.dropLast(Self.logLimit) {
            asks[dropped.id] = nil
            stopped[dropped.id] = nil
        }
        log = Array(log.suffix(Self.logLimit))
        return entry.id
    }

    private func update(_ id: UUID, _ change: (inout AutopilotLogEntry) -> Void) {
        guard let index = log.firstIndex(where: { $0.id == id }) else { return }
        change(&log[index])
    }

    private func entry(_ id: UUID) -> AutopilotLogEntry? { log.first { $0.id == id } }
    private func title(of id: UUID) -> String { entry(id)?.title ?? "" }
    private func reason(of id: UUID) -> String { entry(id)?.reason ?? "" }

    private static func reason(for action: AutopilotAction, server: Server) -> String {
        if case .pause = action { return L10n.format("Using %@ CPU · CPU pressure", Format.percent(server.cpu)) }
        return L10n.format("Idle %@, %@ · memory pressure", L10n.duration(server.idleFor, short: true), Format.bytesString(server.memory))
    }
}

extension AutopilotAction {
    var isPauseOrStop: Bool {
        switch self {
        case .pause, .stop: return true
        default: return false
        }
    }

    var verb: AutopilotLogEntry.Verb {
        switch self {
        case .pause: return .pause
        case .stop: return .stop
        case .resume: return .resume
        case .unloadKalonModels: return .unload
        }
    }
}
