import Foundation

struct AutopilotSettings: Equatable {
    var mode = Preferences.AutopilotMode.ask
    /// Share of physical memory in use at which Autopilot acts.
    var memoryPercent = 90.0
    /// Whole-Mac CPU at which Autopilot acts.
    var cpuPercent = 90.0
    var idleMinutes = 30
    var useKalon = true
    /// Ports marked "Keep running".
    var pinned: Set<Int> = []

    static func saved(in defaults: UserDefaults = .standard) -> AutopilotSettings {
        func percent(_ key: String) -> Double {
            let value = defaults.double(forKey: key)
            return value > 0 ? min(max(value, 50), 99) : 90
        }
        return AutopilotSettings(
            mode: Preferences.AutopilotMode(rawValue: defaults.string(forKey: Preferences.autopilotMode) ?? "") ?? .ask,
            memoryPercent: percent(Preferences.autopilotMemoryPercent),
            cpuPercent: percent(Preferences.autopilotCPUPercent),
            idleMinutes: max(defaults.integer(forKey: Preferences.autopilotIdleMinutes), 1),
            useKalon: defaults.bool(forKey: Preferences.autopilotUseKalon),
            pinned: Set((defaults.array(forKey: Preferences.autopilotPinned) as? [Int]) ?? []))
    }
}

/// What the policy needs to know about one server.
struct AutopilotServer: Equatable {
    var key: ServerKey
    var name: String
    var kind = ServerKind.dev
    var isProtected = false
    var memory: UInt64 = 0
    var cpu = 0.0
    /// Highest CPU over the last two minutes.
    var recentCPU = 0.0
    var connections = 0
    var lastRequestAt: Date?
    var idleFor: TimeInterval = 0
    /// When the coding agent that started it last wrote to its transcript.
    var transcriptModifiedAt: Date?
    var sharesTree = false
}

extension AutopilotServer {
    init(_ server: Server, now: Date, transcriptModifiedAt: Date?) {
        self.init(key: server.key, name: server.project.name, kind: server.kind, isProtected: server.isProtected,
                  memory: server.memory, cpu: server.cpu,
                  recentCPU: server.history.filter { now.timeIntervalSince($0.time) <= 120 }.map(\.cpu).max() ?? server.cpu,
                  connections: server.connections, lastRequestAt: server.lastRequestAt,
                  idleFor: now.timeIntervalSince(server.lastActive), transcriptModifiedAt: transcriptModifiedAt,
                  sharesTree: !server.sharesTreeWith.isEmpty)
    }
}

struct AutopilotSnapshot {
    var servers: [AutopilotServer]
    var pressure = MemoryPressure.normal
    var memoryUsedPercent = 0.0
    var memoryTotal: UInt64 = 0
    var systemCPU: Double?
    /// nil when Kalon can't be reached.
    var kalonBusy: Bool?
}

enum AutopilotAction: Equatable {
    case pause(ServerKey)
    case resume(ServerKey)
    case stop(ServerKey)
    case unloadKalonModels
}

/// What Autopilot remembers between scans.
struct AutopilotState {
    var memoryOverScans = 0
    var cpuOverScans = 0
    var calmScans = 0
    /// Memory tripped the threshold and hasn't yet fallen far enough below it.
    var relievingMemory = false
    var unloadedThisEpisode = false
    var paused: Set<ServerKey> = []
    /// When each server was last paused, stopped, resumed or asked about.
    var lastActed: [ServerKey: Date] = [:]
    var actionTimes: [Date] = []
    /// Memory that recent stops should give back once they finish.
    var pendingFreed: [(at: Date, bytes: UInt64)] = []

    /// Call once per scan, before `decide`.
    mutating func observe(_ snapshot: AutopilotSnapshot, settings: AutopilotSettings) {
        let memoryOver = snapshot.pressure >= .warning || snapshot.memoryUsedPercent >= settings.memoryPercent
        let cpuOver = (snapshot.systemCPU ?? 0) >= settings.cpuPercent
        memoryOverScans = memoryOver ? memoryOverScans + 1 : 0
        cpuOverScans = cpuOver ? cpuOverScans + 1 : 0
        calmScans = memoryOver || cpuOver ? 0 : calmScans + 1
        if memoryOverScans >= AutopilotPolicy.triggerScans { relievingMemory = true }
        if snapshot.pressure == .normal, snapshot.memoryUsedPercent < settings.memoryPercent - AutopilotPolicy.memoryMargin { relievingMemory = false }
        if calmScans >= AutopilotPolicy.releaseScans { unloadedThisEpisode = false }
    }

    /// Call when an action is carried out, or asked about.
    mutating func record(_ action: AutopilotAction, memory: UInt64 = 0, at now: Date) {
        switch action {
        case .pause(let key):
            paused.insert(key)
            lastActed[key] = now
            actionTimes.append(now)
        case .stop(let key):
            lastActed[key] = now
            actionTimes.append(now)
            pendingFreed.append((now, memory))
        case .resume(let key):
            paused.remove(key)
            lastActed[key] = now
        case .unloadKalonModels:
            unloadedThisEpisode = true
        }
        actionTimes.removeAll { now.timeIntervalSince($0) > 3600 }
        lastActed = lastActed.filter { now.timeIntervalSince($0.value) <= AutopilotPolicy.cooldown }
        pendingFreed.removeAll { now.timeIntervalSince($0.at) > AutopilotPolicy.pendingWindow }
    }
}

/// Decides what Autopilot does when the Mac runs short. Pure: everything it
/// knows comes in through the snapshot, the state and the settings.
enum AutopilotPolicy {
    enum Verb { case pause, stop }

    static let triggerScans = 3
    static let releaseScans = 5
    /// Stopping continues until memory is this far (in percent of RAM) below the threshold.
    static let memoryMargin = 5.0
    static let recentRequest: TimeInterval = 10 * 60
    static let recentTranscript: TimeInterval = 10 * 60
    static let minimumAge: TimeInterval = 15 * 60
    static let cooldown: TimeInterval = 15 * 60
    static let busyCPU = 5.0
    /// A server has to use at least this much CPU for pausing it to help.
    static let hogCPU = 10.0
    static let actionSpacing: TimeInterval = 60
    static let actionsPerHour = 6
    static let pendingWindow: TimeInterval = 120

    /// Servers in use right now: anything with an open connection, and the one
    /// that most recently took a request. Autopilot never touches them.
    static func activeServers(in snapshot: AutopilotSnapshot) -> Set<ServerKey> {
        var active = Set(snapshot.servers.filter { $0.connections > 0 }.map(\.key))
        let latest = snapshot.servers.filter { $0.lastRequestAt != nil }.max { $0.lastRequestAt! < $1.lastRequestAt! }
        if let latest { active.insert(latest.key) }
        return active
    }

    /// What Autopilot would act on now, most deserving first, or nil when
    /// there's no sustained pressure or nothing passes the gates.
    static func candidates(_ snapshot: AutopilotSnapshot, state: AutopilotState, settings: AutopilotSettings,
                           now: Date) -> (verb: Verb, servers: [AutopilotServer])? {
        let active = activeServers(in: snapshot)
        func eligible(_ verb: Verb) -> [AutopilotServer] {
            snapshot.servers.filter { passesGates($0, verb: verb, active: active, state: state, settings: settings, now: now) }
        }
        if wantsMemory(snapshot, state: state, settings: settings, now: now) {
            let idle = eligible(.stop).filter { $0.idleFor >= TimeInterval(settings.idleMinutes) * 60 }
                .sorted { ($0.memory, $1.key.port) > ($1.memory, $0.key.port) }
            if !idle.isEmpty { return (.stop, idle) }
        }
        if state.cpuOverScans >= triggerScans {
            let hogs = eligible(.pause).filter { $0.cpu >= hogCPU }.sorted { ($0.cpu, $1.key.port) > ($1.cpu, $0.key.port) }
            if !hogs.isEmpty { return (.pause, hogs) }
        }
        return nil
    }

    /// At most one pause or stop per call. Kalon's advice may pick or reorder
    /// among the candidates; ports it names outside them are ignored, and
    /// without a usable pick the rules decide.
    static func decide(_ snapshot: AutopilotSnapshot, state: AutopilotState, settings: AutopilotSettings, now: Date,
                       advice: KalonAdvice? = nil) -> [AutopilotAction] {
        guard settings.mode != .off else { return [] }
        // Back to normal for long enough: let everything run again.
        if state.calmScans >= releaseScans {
            return state.paused.sorted { $0.port < $1.port }.map(AutopilotAction.resume)
        }
        var actions: [AutopilotAction] = []
        let memoryShort = state.memoryOverScans >= triggerScans
        if memoryShort, !state.unloadedThisEpisode, snapshot.kalonBusy == false, snapshot.servers.contains(where: { $0.kind == .ai }) {
            actions.append(.unloadKalonModels)
        }
        guard isWithinRateLimit(state, now: now),
              let (verb, servers) = candidates(snapshot, state: state, settings: settings, now: now) else { return actions }
        let target = chosen(from: servers, verb: verb, advice: advice) ?? servers[0]
        actions.append(verb == .stop ? .stop(target.key) : .pause(target.key))
        return actions
    }

    /// Whether Kalon's advice, rather than the rules, picked this action.
    static func isAdvised(_ action: AutopilotAction, advice: KalonAdvice?) -> Bool {
        switch action {
        case .stop(let key): return advice?.stop.contains(key.port) ?? false
        case .pause(let key): return advice?.pause.contains(key.port) ?? false
        default: return false
        }
    }

    private static func chosen(from servers: [AutopilotServer], verb: Verb, advice: KalonAdvice?) -> AutopilotServer? {
        guard let advice else { return nil }
        for port in verb == .stop ? advice.stop : advice.pause {
            if let server = servers.first(where: { $0.key.port == port }) { return server }
        }
        return nil
    }

    private static func isWithinRateLimit(_ state: AutopilotState, now: Date) -> Bool {
        if let last = state.actionTimes.last, now.timeIntervalSince(last) < actionSpacing { return false }
        return state.actionTimes.filter { now.timeIntervalSince($0) < 3600 }.count < actionsPerHour
    }

    /// Memory has tripped the threshold and, allowing for stops still in
    /// progress, isn't yet comfortably below it.
    private static func wantsMemory(_ snapshot: AutopilotSnapshot, state: AutopilotState, settings: AutopilotSettings, now: Date) -> Bool {
        guard state.memoryOverScans >= triggerScans || state.relievingMemory else { return false }
        if snapshot.pressure >= .warning { return true }
        let pending = state.pendingFreed.filter { now.timeIntervalSince($0.at) <= pendingWindow }.reduce(UInt64(0)) { $0 + $1.bytes }
        let estimated = snapshot.memoryUsedPercent - (snapshot.memoryTotal > 0 ? Double(pending) / Double(snapshot.memoryTotal) * 100 : 0)
        return estimated >= settings.memoryPercent - memoryMargin
    }

    /// The hard gates. A server that fails any of them is never acted on.
    static func passesGates(_ server: AutopilotServer, verb: Verb, active: Set<ServerKey>, state: AutopilotState,
                            settings: AutopilotSettings, now: Date) -> Bool {
        if server.isProtected || server.kind == .ai || server.sharesTree { return false }
        if settings.pinned.contains(server.key.port) || active.contains(server.key) || state.paused.contains(server.key) { return false }
        if server.connections > 0 { return false }
        if let request = server.lastRequestAt, now.timeIntervalSince(request) < recentRequest { return false }
        if let transcript = server.transcriptModifiedAt, now.timeIntervalSince(transcript) < recentTranscript { return false }
        // An unknown start time can't be told apart from a server that just started.
        guard let started = server.key.startedAt, now.timeIntervalSince(started) >= minimumAge else { return false }
        if let acted = state.lastActed[server.key], now.timeIntervalSince(acted) < cooldown { return false }
        // Under CPU pressure the busy one is the target, as long as nobody is using it.
        if verb == .stop, server.recentCPU >= busyCPU { return false }
        return true
    }
}
