import Combine
import Foundation

@MainActor
final class ServerMonitor: ObservableObject {
    @Published private(set) var servers: [Server] = [] {
        didSet {
            // Port identities stay stable across reordering, filtering and restarts.
            for port in servers.map(\.port).sorted() where portColors[port] == nil {
                portColors[port] = portColors.count
            }
        }
    }
    private var portColors: [Int: Int] = [:]
    @Published private(set) var hasScanned = false
    @Published private(set) var systemMemory: SystemMemory?
    /// Whole-Mac CPU, as a share of all cores.
    @Published private(set) var systemCPU: Double?
    @Published private(set) var memoryPressure = MemoryPressure.normal
    /// Memory by app for everything that isn't a dev server, largest first.
    @Published private(set) var otherApps: [AppMemory] = []
    @Published private(set) var allowlist: Set<String>
    @Published private(set) var minPort: Int
    @Published private(set) var maxPort: Int
    /// A page to open next time the popover appears, e.g. from a notification's Details button.
    @Published var pendingRoute: PopoverRoute?

    /// Off in the terminal UI, so it never duplicates the menu bar app's
    /// notifications or automatic clean up.
    var handlesAlerts = true

    let github = GitHubLookup()
    private let engine = ScanEngine()
    private let appUsage = AppUsageScanner()
    private let cpuSampler = SystemCPUSampler()
    private let queue = DispatchQueue(label: "com.porto.scan", qos: .utility)
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var isScanning = false
    private var settingsObserver: AnyCancellable?
    /// Servers already handled by Clean up (announced or stopped), by port and root pid.
    private var handledCleanUps = Set<String>()

    private var defaults: UserDefaults { .standard }

    init() {
        let defaults = UserDefaults.standard
        allowlist = defaults.stringArray(forKey: Preferences.allowlist).map(Set.init) ?? Preferences.defaultAllowlist
        minPort = min(max(defaults.integer(forKey: Preferences.minPort), 1), 65535)
        maxPort = min(max(defaults.integer(forKey: Preferences.maxPort), 1), 65535)
    }

    // MARK: - Settings

    /// Memory above which a server needs attention.
    var alertThreshold: UInt64 {
        let gigabytes = defaults.double(forKey: Preferences.thresholdGB)
        return UInt64((gigabytes > 0 ? gigabytes : 2) * Format.gigabyte)
    }

    var idleThreshold: TimeInterval { TimeInterval(max(defaults.integer(forKey: Preferences.cleanUpIdleHours), 1)) * 3600 }
    var longRunningThreshold: TimeInterval { TimeInterval(max(defaults.integer(forKey: Preferences.cleanUpRunningDays), 1)) * 86400 }
    var cleanUpMode: Preferences.CleanUpMode {
        Preferences.CleanUpMode(rawValue: defaults.string(forKey: Preferences.cleanUpMode) ?? "") ?? .ask
    }

    private var scanConfig: ScanConfig {
        ScanConfig(minPort: minPort, maxPort: maxPort, allowlist: allowlist,
                   protected: Set(defaults.stringArray(forKey: Preferences.protectedProcesses) ?? Preferences.defaultProtected),
                   linkClaude: defaults.bool(forKey: Preferences.linkClaude),
                   linkCodex: defaults.bool(forKey: Preferences.linkCodex),
                   linkConductor: defaults.bool(forKey: Preferences.linkConductor),
                   showBranches: defaults.bool(forKey: Preferences.showBranches))
    }

    // MARK: - Scanning

    func start() {
        guard timer == nil else { return }
        scan()
        scheduleTimer()
        // Settings changes (interval, thresholds, integrations) apply on the next scan.
        settingsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleTimer()
                    self?.objectWillChange.send()
                }
            }
    }

    private func scheduleTimer() {
        let interval = max(defaults.double(forKey: Preferences.scanInterval), 1)
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
        // A little slack lets macOS coalesce the wake-ups with other timers.
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let config = scanConfig
        queue.async { [engine, appUsage, cpuSampler] in
            let result = engine.scan(config)
            let memory = ProcessTable.systemMemory()
            let pressure = ProcessTable.memoryPressure()
            let cpu = cpuSampler.sample()
            let apps = appUsage.scan(result.processes, excluding: Set(result.servers.flatMap { $0.processStarts.keys }))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(result.servers, memory: memory, pressure: pressure, cpu: cpu, apps: apps) }
            }
        }
    }

    private func apply(_ result: [Server], memory: SystemMemory, pressure: MemoryPressure, cpu: Double?, apps: [AppMemory]) {
        servers = result
        systemMemory = memory
        memoryPressure = pressure
        if let cpu { systemCPU = cpu }
        otherApps = apps
        hasScanned = true
        isScanning = false
        if handlesAlerts {
            AlertCenter.shared.evaluate(result, threshold: alertThreshold)
            handleCleanUp()
            AutopilotController.shared.evaluate(result, memory: memory, pressure: pressure, cpu: cpu)
        }
        // Keep previews and pull requests roughly fresh (a no-op when both are off).
        result.forEach { github.refresh($0, maxAge: 300) }
    }

    /// A synchronous scan, for snapshots and `porto list`.
    func scanNow() {
        let config = scanConfig
        let (result, memory, cpu, apps): (ScanResult, SystemMemory, Double?, [AppMemory]) = queue.sync {
            let result = engine.scan(config)
            let apps = appUsage.scan(result.processes, excluding: Set(result.servers.flatMap { $0.processStarts.keys }))
            return (result, ProcessTable.systemMemory(), cpuSampler.sample(), apps)
        }
        servers = result.servers
        systemMemory = memory
        memoryPressure = ProcessTable.memoryPressure()
        if let cpu { systemCPU = cpu }
        otherApps = apps
        hasScanned = true
    }

    // MARK: - Derived

    var totalMemory: UInt64 { Self.distinctTrees(servers).reduce(0) { $0 + $1.memory } }
    var totalCPU: Double { Self.distinctTrees(servers).reduce(0) { $0 + $1.cpu } }
    /// Servers' CPU as a share of the whole Mac, comparable with `systemCPU`.
    var serversShareOfCPU: Double { totalCPU / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)) }
    var needsAttention: Bool { servers.contains { status(of: $0) == .attention } }

    func server(port: Int) -> Server? { servers.first { $0.port == port } }
    func colorIndex(for port: Int) -> Int { portColors[port] ?? 0 }
    func status(of server: Server) -> ServerStatus { server.status(alertThreshold: alertThreshold) }

    /// One server per process tree, so ports that share a tree are counted once.
    nonisolated static func distinctTrees(_ servers: [Server]) -> [Server] {
        var seen = Set<pid_t>()
        return servers.filter { seen.insert($0.rootPid).inserted }
    }

    func cleanUpReason(for server: Server) -> CleanUpReason? {
        guard cleanUpMode != .off else { return nil }
        return Self.cleanUpReason(for: server, deletedWorktree: defaults.bool(forKey: Preferences.cleanUpDeletedWorktree),
                                  idleThreshold: idleThreshold, longRunningThreshold: longRunningThreshold)
    }

    /// A deleted worktree or a long uptime only counts once the server is also
    /// quiet: no connections, no recent CPU, nothing for ten minutes.
    nonisolated static func cleanUpReason(for server: Server, deletedWorktree: Bool, idleThreshold: TimeInterval,
                              longRunningThreshold: TimeInterval) -> CleanUpReason? {
        guard !server.isProtected else { return nil }
        let isInactive = server.connections == 0 && server.cpu < 2 && server.idleFor >= 10 * 60
        if !server.cwdExists { return deletedWorktree && isInactive ? .worktreeDeleted : nil }
        if server.idleFor >= idleThreshold { return .idle(server.idleFor) }
        if isInactive, let uptime = server.uptime, uptime >= longRunningThreshold { return .longRunning(uptime) }
        if server.isLeaking() { return .leaking(UInt64(max(server.memoryGrowth, 0))) }
        return nil
    }

    /// Servers worth suggesting in Clean up. Leaking ones are listed but never
    /// preselected, since they're usually still in use.
    var cleanUpCandidates: [(server: Server, reason: CleanUpReason)] {
        servers.compactMap { server in cleanUpReason(for: server).map { (server, $0) } }
    }

    var suggestedCleanUp: Set<Int> { Set(cleanUpCandidates.filter { !$0.reason.isLeak }.map(\.server.port)) }

    // MARK: - Automatic clean up

    /// In Ask mode, says once when servers start qualifying; in Automatic mode,
    /// stops them. Leaking servers are never stopped automatically.
    private func handleCleanUp() {
        let candidates = cleanUpCandidates.filter { !$0.reason.isLeak }
        let keys = Set(candidates.map { key(for: $0.server) })
        let fresh = candidates.filter { !handledCleanUps.contains(key(for: $0.server)) }
        handledCleanUps.formIntersection(keys)
        guard !fresh.isEmpty else { return }
        fresh.forEach { handledCleanUps.insert(key(for: $0.server)) }

        let notify = defaults.bool(forKey: Preferences.cleanUpNotify)
        switch cleanUpMode {
        case .off:
            return
        case .ask:
            if notify { AlertCenter.shared.announceCleanUp(fresh.map(\.server), stopped: false) }
        case .automatic:
            Usage.record(.autoCleanUp)
            fresh.forEach { stop($0.server) }
            if notify { AlertCenter.shared.announceCleanUp(fresh.map(\.server), stopped: true) }
        }
    }

    private func key(for server: Server) -> String { "\(server.port)-\(server.rootPid)" }

    // MARK: - Actions

    func stop(_ server: Server) {
        ProcessControl.stop(server) { [weak self] _ in self?.scan() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.scan() }
    }

    func restart(_ server: Server) {
        ProcessControl.restart(server) { [weak self] _ in self?.scan() }
    }

    // MARK: - Ports and processes

    func setPortRange(min: Int, max: Int) {
        minPort = min
        maxPort = max
        defaults.set(min, forKey: Preferences.minPort)
        defaults.set(max, forKey: Preferences.maxPort)
        scan()
    }

    func setAllowlist(_ processes: Set<String>) {
        allowlist = processes
        defaults.set(processes.sorted(), forKey: Preferences.allowlist)
        scan()
    }

    func resetAllowlist() {
        allowlist = Preferences.defaultAllowlist
        defaults.removeObject(forKey: Preferences.allowlist)
        scan()
    }
}
