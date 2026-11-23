import Foundation

/// One reading of a server's whole process tree.
struct Sample: Equatable {
    let time: Date
    let memory: UInt64
    let cpu: Double
}

struct ServerProcess: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let depth: Int
    let memory: UInt64
    var id: pid_t { pid }
}

enum ServerStatus {
    case running
    /// Over the memory threshold, or leaking.
    case attention
    /// Idle for over an hour, or its folder is gone.
    case idle
}

/// Why Clean up suggests stopping a server.
enum CleanUpReason: Equatable {
    case worktreeDeleted
    case idle(TimeInterval)
    case longRunning(TimeInterval)
    case leaking(UInt64)

    var isLeak: Bool {
        if case .leaking = self { return true }
        return false
    }
}

/// What a server is for, worked out from its working directory.
struct ProjectInfo: Equatable {
    var name: String
    var root: String?
    var framework: String?
    var branch: String?
    var isWorktree = false
    var worktreeName: String?
    var hasVercel = false
}

enum AgentKind: String {
    case claudeCode = "Claude Code"
    case codex = "Codex"

    var resumeCommand: String {
        switch self {
        case .claudeCode: return "claude --resume"
        case .codex: return "codex resume"
        }
    }
}

/// The coding-agent session that started a server.
struct AgentSession: Equatable {
    let kind: AgentKind
    let id: String
    let title: String?
    let transcript: URL?
    let startedAt: Date?
    /// Where the agent was started, which is where it has to be resumed.
    let directory: String?

    var shortID: String { String(id.prefix(8)) }
}

enum ServerKind: String {
    case dev
    /// A local model server such as Kalon or Ollama.
    case ai
}

/// One run of a server: the port, and the root process by pid and start time.
struct ServerKey: Hashable {
    let port: Int
    let rootPid: pid_t
    let startedAt: Date?
}

/// A listening port and everything known about the process tree behind it.
struct Server: Identifiable {
    let port: Int
    let pid: pid_t
    let rootPid: pid_t
    let processName: String
    var addresses: [String]
    var cwd: String?
    var cwdExists: Bool
    var command: String?
    var launch: ProcArgs?
    /// Where the launcher ran, e.g. the folder `npm run dev` was typed in.
    var launchDirectory: String?
    var startedAt: Date?
    var project: ProjectInfo
    var conductorWorkspace: String?
    var agent: AgentSession?
    var processes: [ServerProcess]
    /// Start time of every process in the tree, so a reused pid is never signalled.
    var processStarts: [pid_t: Date]
    var memory: UInt64
    var cpu: Double
    var connections: Int
    var history: [Sample]
    var lastActive: Date
    var isProtected: Bool
    var kind: ServerKind = .dev
    /// Other ports served by the same process tree; stopping this one would take them down too.
    var sharesTreeWith: [Int] = []
    /// Client connections that appeared since the previous scan.
    var clientChurn = 0
    var lastRequestAt: Date?
    /// Its root process is stopped (SIGSTOP).
    var isPaused = false

    var id: Int { port }
    var key: ServerKey { ServerKey(port: port, rootPid: rootPid, startedAt: startedAt) }
    var url: URL { URL(string: "http://localhost:\(port)")! }

    var uptime: TimeInterval? { startedAt.map { Date().timeIntervalSince($0) } }
    var idleFor: TimeInterval { Date().timeIntervalSince(lastActive) }

    /// Memory growth across the recorded history (up to ten minutes), once there are two minutes of it.
    var memoryGrowth: Int64 {
        guard let first = history.first, let last = history.last,
              last.time.timeIntervalSince(first.time) >= 120 else { return 0 }
        return Int64(last.memory) - Int64(first.memory)
    }

    func isLeaking(threshold: UInt64 = 500 * 1_048_576) -> Bool {
        memoryGrowth >= Int64(threshold)
    }

    func status(alertThreshold: UInt64) -> ServerStatus {
        if !cwdExists { return .idle }
        if memory >= alertThreshold || isLeaking() { return .attention }
        if idleFor > 60 * 60 { return .idle }
        return .running
    }

    /// A short place name: the Conductor workspace, the git worktree, or the parent folder.
    var locationLabel: String {
        if let conductorWorkspace { return conductorWorkspace }
        if let worktree = project.worktreeName { return worktree }
        guard let root = project.root ?? cwd else { return project.name }
        return ((root as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
    }

    /// The folder, shortened for one line: "~/…/workspaces/porto".
    var shortFolder: String? {
        guard let cwd else { return nil }
        let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
        let parts = abbreviated.split(separator: "/")
        guard parts.count > 3 else { return abbreviated }
        // Keep the leading slash so /private/… doesn't read as a relative path.
        return (abbreviated.hasPrefix("/") ? "/" : "") + "\(parts.first!)/…/" + parts.suffix(2).joined(separator: "/")
    }
}

/// Memory one app uses, its helper processes folded in (every "Chrome Helper" counts toward Chrome).
struct AppMemory: Identifiable, Equatable {
    let id: String
    let name: String
    let bundlePath: String?
    /// Set for coding agents, which have no app bundle of their own.
    let agent: AgentKind?
    let memory: UInt64
}
