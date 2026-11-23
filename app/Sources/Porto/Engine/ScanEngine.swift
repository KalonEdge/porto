import Foundation

struct ScanConfig {
    var minPort: Int
    var maxPort: Int
    var allowlist: Set<String>
    var protected: Set<String> = Set(Preferences.defaultProtected)
    var linkClaude = true
    var linkCodex = true
    var linkConductor = true
    var showBranches = true
}

/// Everything one scan learns.
struct ScanResult {
    var servers: [Server]
    var processes: [pid_t: ProcSnapshot]
}

/// CPU share per process, from the change in its CPU time between scans. Each
/// pid is measured once per scan, so ports that share a process tree all read
/// the same value instead of the second one reading zero.
struct CPUMeter {
    private var previous: [pid_t: (nanoseconds: UInt64, at: Date)] = [:]
    private var current: [pid_t: Double] = [:]

    /// Call once at the start of every scan.
    mutating func beginScan() { current = [:] }

    mutating func percent(pid: pid_t, nanoseconds: UInt64, at now: Date) -> Double {
        if let measured = current[pid] { return measured }
        var percent = 0.0
        if let previous = previous[pid], nanoseconds >= previous.nanoseconds {
            let elapsed = now.timeIntervalSince(previous.at)
            if elapsed > 0 { percent = Double(nanoseconds - previous.nanoseconds) / (elapsed * 1_000_000_000) * 100 }
        }
        previous[pid] = (nanoseconds, now)
        current[pid] = percent
        return percent
    }

    mutating func prune(keeping live: Set<pid_t>) {
        previous = previous.filter { live.contains($0.key) }
    }
}

/// Builds the server list from listening sockets and the process table. Keeps
/// what has to persist between scans (CPU deltas, histories, caches), so use it
/// from one serial queue only.
final class ScanEngine: @unchecked Sendable {
    static let historyWindow: TimeInterval = 10 * 60

    /// Processes that sit between a shell and the actual server, like `npm run dev`.
    private static let runners: Set<String> = [
        "node", "npm", "npx", "pnpm", "yarn", "bun", "bunx", "deno", "turbo", "nx",
        "python", "python3", "Python", "uv", "poetry", "pipenv",
        "ruby", "bundle", "rails", "go", "air", "cargo", "java", "gradle", "mvn",
        "dotnet", "php", "mix", "beam.smp", "elixir",
    ]
    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]
    private static let agentNames: Set<String> = ["claude", "codex", "Conductor"]
    /// Path fragments that mark an agent run through a runtime like node.
    private static let agentPathMarkers = ["@anthropic-ai/claude-code", "com.conductor.app", "/codex/"]

    private let projects = ProjectResolver()
    private let agents = AgentSessionResolver()
    private var cpuMeter = CPUMeter()
    /// Client endpoints connected to each server at the previous scan.
    private var previousClients: [String: Set<String>] = [:]
    private var lastRequest: [String: Date] = [:]
    private var histories: [String: [Sample]] = [:]
    private var lastActive: [String: Date] = [:]
    private var argsCache: [pid_t: (start: Date, args: ProcArgs?)] = [:]

    /// Whether a process name is on the allowlist, including versioned
    /// interpreters like `python3.12` or `ruby3.3` for `python`/`ruby`.
    static func isWatched(_ name: String, in allowlist: Set<String>) -> Bool {
        if allowlist.contains(name) { return true }
        let unversioned = name.replacingOccurrences(of: "[0-9][0-9.]*$", with: "", options: .regularExpression)
        return unversioned != name && !unversioned.isEmpty && (allowlist.contains(unversioned) || allowlist.contains(unversioned + "3"))
    }

    /// Whether anything in a server's tree is on the protected list, a built-in
    /// database or model server, or runs out of Kalon.app.
    static func isProtected(names: [String], paths: [String], protected: Set<String>) -> Bool {
        let all = protected.union(Preferences.builtInProtected)
        let candidates = names + paths.map { ($0 as NSString).lastPathComponent }
        return candidates.contains { isWatched($0, in: all) } || paths.contains { KalonFamily.isKalon(comm: "", path: $0) }
    }

    /// Fills in `sharesTreeWith` for servers whose process trees overlap.
    static func markSharedTrees(_ servers: inout [Server]) {
        let pids = servers.map { Set($0.processStarts.keys).union([$0.rootPid]) }
        for index in servers.indices {
            servers[index].sharesTreeWith = servers.indices
                .filter { $0 != index && !pids[$0].isDisjoint(with: pids[index]) }
                .map { servers[$0].port }
        }
    }

    func scan(_ config: ScanConfig) -> ScanResult {
        let now = Date()
        let processes = ProcessTable.all()
        cpuMeter.beginScan()

        // Only dev-server-like processes are worth asking for their sockets.
        var listeners: [Int: (pid: pid_t, name: String, addresses: [String])] = [:]
        var connections: [Int: Int] = [:]
        var clients: [Int: Set<String>] = [:]
        for process in processes.values.sorted(by: { $0.pid < $1.pid })
        where Self.isWatched(process.comm, in: config.allowlist) || KalonFamily.aiNames.contains(process.comm) {
            for socket in ProcessTable.tcpSockets(process.pid) {
                switch socket.state {
                case .established:
                    connections[socket.localPort, default: 0] += 1
                    clients[socket.localPort, default: []].insert("\(socket.remoteAddress):\(socket.remotePort)")
                case .listening:
                    guard socket.localPort >= config.minPort, socket.localPort <= config.maxPort else { continue }
                    if var existing = listeners[socket.localPort] {
                        if existing.pid == process.pid, !existing.addresses.contains(socket.localAddress) {
                            existing.addresses.append(socket.localAddress)
                            listeners[socket.localPort] = existing
                        }
                    } else {
                        listeners[socket.localPort] = (process.pid, process.comm, [socket.localAddress])
                    }
                }
            }
        }

        var children: [pid_t: [pid_t]] = [:]
        for process in processes.values { children[process.ppid, default: []].append(process.pid) }

        var servers: [Server] = []
        var seenKeys = Set<String>()
        var livePids = Set<pid_t>()

        for port in listeners.keys.sorted() {
            guard let socket = listeners[port], let listener = processes[socket.pid] else { continue }
            let root = rootProcess(for: listener, in: processes)
            let tree = descendants(of: root.pid, children: children, processes: processes)
            livePids.formUnion(tree.map(\.process.pid))

            var memory: UInt64 = 0
            var cpu = 0.0
            var nodes: [ServerProcess] = []
            var starts: [pid_t: Date] = [:]
            for (process, depth) in tree {
                let usage = ProcessTable.usage(process.pid)
                let footprint = usage?.footprint ?? 0
                memory += footprint
                if let usage { cpu += cpuMeter.percent(pid: process.pid, nanoseconds: usage.cpuNanoseconds, at: now) }
                starts[process.pid] = process.startTime
                nodes.append(ServerProcess(pid: process.pid, name: displayName(for: process), depth: depth, memory: footprint))
            }

            let rootArgs = args(for: root)
            let listenerPath = args(for: listener)?.executablePath
            if KalonFamily.isMuxora(comm: listener.comm, path: listenerPath) || KalonFamily.isMuxora(comm: root.comm, path: rootArgs?.executablePath) {
                continue
            }
            let isAI = KalonFamily.isAI(comm: listener.comm, path: listenerPath) || KalonFamily.isAI(comm: root.comm, path: rootArgs?.executablePath)
            // A model runner under its own server (`ollama runner`) isn't a server of its own.
            if isAI, let parent = processes[listener.ppid], KalonFamily.isAI(comm: parent.comm, path: args(for: parent)?.executablePath) {
                continue
            }
            let cwd = ProcessTable.currentDirectory(listener.pid) ?? ProcessTable.currentDirectory(root.pid)
            // Apps that embed a node or python backend aren't dev servers.
            if !isAI, cwd == "/" || [rootArgs?.executablePath, listenerPath].contains(where: { $0?.contains(".app/Contents/") == true }) {
                continue
            }
            let environment = inheritedEnvironment(from: listener, root: root, in: processes)
            let command = rootArgs.map { Self.prettyCommand($0.arguments, comm: root.comm) }
            var project = projects.resolve(cwd: cwd, command: command)
            if !config.showBranches { project.branch = nil }
            if isAI, project.root == nil {
                project.name = KalonFamily.isKalon(comm: listener.comm, path: listenerPath) ? "Kalon" : socket.name
            }

            // Restart from the highest process whose argv wasn't overwritten by a
            // title, like the `sh -c "next dev -p 3000"` npm spawns.
            let launcher = tree.map(\.process).first { Self.hasIntactArguments(args(for: $0)) } ?? root

            let key = "\(port)-\(root.pid)"
            seenKeys.insert(key)
            let inbound = connections[port] ?? 0
            if cpu >= 2 || inbound > 0 || lastActive[key] == nil { lastActive[key] = now }

            var history = histories[key] ?? []
            history.append(Sample(time: now, memory: memory, cpu: cpu))
            history.removeAll { now.timeIntervalSince($0.time) > Self.historyWindow }
            histories[key] = history

            let connected = clients[port] ?? []
            let churn = previousClients[key].map { connected.subtracting($0).count } ?? 0
            previousClients[key] = connected
            if churn > 0 { lastRequest[key] = now }

            servers.append(Server(
                port: port,
                pid: listener.pid,
                rootPid: root.pid,
                processName: socket.name,
                addresses: socket.addresses,
                cwd: cwd,
                cwdExists: cwd.map { FileManager.default.fileExists(atPath: $0) } ?? true,
                command: command,
                launch: args(for: launcher),
                launchDirectory: ProcessTable.currentDirectory(launcher.pid) ?? cwd,
                startedAt: root.startTime,
                project: project,
                conductorWorkspace: config.linkConductor ? environment["CONDUCTOR_WORKSPACE_NAME"] : nil,
                agent: agents.resolve(environment: environment, cwd: cwd, claude: config.linkClaude, codex: config.linkCodex),
                processes: nodes,
                processStarts: starts,
                memory: memory,
                cpu: cpu,
                connections: inbound,
                history: history,
                lastActive: lastActive[key] ?? now,
                isProtected: Self.isProtected(names: [socket.name] + tree.map(\.process.comm),
                                              paths: tree.compactMap { args(for: $0.process)?.executablePath },
                                              protected: config.protected),
                kind: isAI ? .ai : .dev,
                clientChurn: churn,
                lastRequestAt: lastRequest[key],
                isPaused: root.isStopped
            ))
        }
        Self.markSharedTrees(&servers)

        histories = histories.filter { seenKeys.contains($0.key) }
        lastActive = lastActive.filter { seenKeys.contains($0.key) }
        previousClients = previousClients.filter { seenKeys.contains($0.key) }
        lastRequest = lastRequest.filter { seenKeys.contains($0.key) }
        cpuMeter.prune(keeping: livePids)
        argsCache = argsCache.filter { processes[$0.key] != nil }
        return ScanResult(servers: servers, processes: processes)
    }

    // MARK: - Process tree

    /// Climbs from the listening process to the command that was actually run,
    /// from `next-server` up to `npm run dev`. Stops at shells, terminals and
    /// coding agents, so stopping a server never takes its launcher with it.
    private func rootProcess(for listener: ProcSnapshot, in processes: [pid_t: ProcSnapshot]) -> ProcSnapshot {
        var current = listener
        while current.ppid > 1, let parent = processes[current.ppid] {
            if Self.runners.contains(parent.comm), !isAgent(parent) {
                current = parent
                continue
            }
            // Package managers run scripts through `sh -c`; step over that shell
            // only when a package manager sits directly above it.
            if Self.shells.contains(parent.comm), parent.ppid > 1, let grandparent = processes[parent.ppid],
               Self.runners.contains(grandparent.comm), !isAgent(grandparent) {
                current = grandparent
                continue
            }
            break
        }
        return current
    }

    private func isAgent(_ process: ProcSnapshot) -> Bool {
        if Self.agentNames.contains(process.comm) { return true }
        guard let args = args(for: process) else { return false }
        let joined = ([args.executablePath] + args.arguments.prefix(3)).joined(separator: " ")
        return Self.agentPathMarkers.contains(where: joined.contains)
    }

    private func descendants(of root: pid_t, children: [pid_t: [pid_t]], processes: [pid_t: ProcSnapshot]) -> [(process: ProcSnapshot, depth: Int)] {
        guard let rootProcess = processes[root] else { return [] }
        var result: [(process: ProcSnapshot, depth: Int)] = []
        func visit(_ process: ProcSnapshot, depth: Int) {
            result.append((process, depth))
            for child in (children[process.pid] ?? []).sorted() {
                if let childProcess = processes[child] { visit(childProcess, depth: depth + 1) }
            }
        }
        visit(rootProcess, depth: 0)
        return result
    }

    /// Environments from the listener up through its launcher. Tools that rename
    /// their process (Next.js sets `process.title = "next-server"`) overwrite the
    /// memory their environment is read from, so session variables often only
    /// survive on a parent like `npm`.
    private func inheritedEnvironment(from listener: ProcSnapshot, root: ProcSnapshot, in processes: [pid_t: ProcSnapshot]) -> [String: String] {
        var chain: [ProcSnapshot] = [listener]
        var current = listener
        var extraHops = 2
        while current.ppid > 1, let parent = processes[current.ppid], chain.count < 10 {
            if chain.contains(where: { $0.pid == root.pid }) {
                guard extraHops > 0 else { break }
                extraHops -= 1
            }
            chain.append(parent)
            current = parent
        }
        var environment: [String: String] = [:]
        for process in chain.reversed() {
            environment.merge(args(for: process)?.environment ?? [:]) { _, closer in closer }
        }
        return environment
    }

    private static func hasIntactArguments(_ args: ProcArgs?) -> Bool {
        guard let args else { return false }
        let parts = args.arguments.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.count > 1 || (parts.count == 1 && !parts[0].contains(" "))
    }

    private func args(for process: ProcSnapshot) -> ProcArgs? {
        if let cached = argsCache[process.pid], cached.start == process.startTime { return cached.args }
        let args = ProcessTable.arguments(process.pid)
        argsCache[process.pid] = (process.startTime, args)
        return args
    }

    // MARK: - Names

    private func displayName(for process: ProcSnapshot) -> String {
        guard let args = args(for: process), !args.arguments.isEmpty else { return process.comm }
        let command = Self.prettyCommand(args.arguments, comm: process.comm)
        // Titles like "next-server (v16.0.0)" read better without the version.
        if let paren = command.range(of: " (") { return String(command[..<paren.lowerBound]) }
        return command
    }

    /// Turns raw argv into what someone would have typed: `node /…/npm-cli.js run dev` becomes `npm run dev`.
    static func prettyCommand(_ arguments: [String], comm: String) -> String {
        let arguments = arguments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = arguments.first else { return comm }
        var parts = arguments
        let executable = (first as NSString).lastPathComponent
        if ["node", "bun", "deno"].contains(executable), parts.count > 1 {
            let script = parts[1]
            let tools = ["npm", "npx", "pnpm", "yarn", "vite", "next", "astro", "nuxt", "storybook", "tsx", "turbo"]
            if let tool = tools.first(where: { script.contains("/\($0)/") || script.contains("/\($0)-cli") || (script as NSString).lastPathComponent == $0 }) {
                parts = [tool] + parts.dropFirst(2)
            } else if script.hasPrefix("/") || script.hasPrefix(".") {
                parts = [(script as NSString).lastPathComponent] + parts.dropFirst(2)
            }
        } else {
            parts[0] = executable
        }
        return parts.map { $0.hasPrefix("/") ? ($0 as NSString).lastPathComponent : $0 }.joined(separator: " ")
    }
}
