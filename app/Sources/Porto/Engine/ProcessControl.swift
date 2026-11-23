import Darwin
import Foundation

enum ProcessControl {
    static var forceQuitDelay: TimeInterval {
        let seconds = UserDefaults.standard.double(forKey: Preferences.forceQuitSeconds)
        return seconds > 0 ? seconds : 3
    }

    enum StopOutcome { case stopped, failed }

    /// SIGTERM to every process in the server's tree, then SIGKILL to anything
    /// still running after the grace period. Each pid is checked against its
    /// start time first, so a pid the system has reused is never signalled.
    static func stop(_ server: Server, completion: (@MainActor (StopOutcome) -> Void)? = nil) {
        stop(server.processStarts, grace: forceQuitDelay, completion: completion)
    }

    /// Paused processes are continued first, since a stopped process can't act
    /// on SIGTERM. Only what's still alive after the grace period is killed.
    static func stop(_ targets: [pid_t: Date], grace: TimeInterval, completion: (@MainActor (StopOutcome) -> Void)? = nil) {
        for (pid, start) in targets where isSameProcess(pid, startedAt: start) {
            kill(pid, SIGCONT)
            kill(pid, SIGTERM)
        }
        func finish(_ outcome: StopOutcome) {
            if let completion { DispatchQueue.main.async { MainActor.assumeIsolated { completion(outcome) } } }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
            let survivors = targets.filter { isSameProcess($0.key, startedAt: $0.value) }
            guard !survivors.isEmpty else { return finish(.stopped) }
            for pid in survivors.keys { kill(pid, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                finish(survivors.contains { isSameProcess($0.key, startedAt: $0.value) } ? .failed : .stopped)
            }
        }
    }

    /// SIGSTOP to every process in the tree, parents first so none of them
    /// reacts to a stopped child. False when nothing could be paused.
    @discardableResult
    static func pause(_ targets: [pid_t: Date]) -> Bool {
        signal(targets.sorted { $0.value < $1.value }.map { ($0.key, $0.value) }, SIGSTOP)
    }

    /// SIGCONT to every process in the tree, children first.
    @discardableResult
    static func resume(_ targets: [pid_t: Date]) -> Bool {
        signal(targets.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }, SIGCONT)
    }

    @discardableResult static func pause(_ server: Server) -> Bool { pause(server.processStarts) }
    @discardableResult static func resume(_ server: Server) -> Bool { resume(server.processStarts) }

    private static func signal(_ targets: [(pid: pid_t, start: Date)], _ signal: Int32) -> Bool {
        var delivered = false
        for target in targets where isSameProcess(target.pid, startedAt: target.start) {
            if kill(target.pid, signal) == 0 { delivered = true }
        }
        return delivered
    }

    /// Stops the server and runs the same command again, in the same folder, with
    /// the same environment. Output goes to ~/Library/Logs/Porto/port-<port>.log.
    static func restart(_ server: Server, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard let launch = server.launch, let cwd = server.launchDirectory ?? server.cwd,
              FileManager.default.fileExists(atPath: cwd), let command = shellCommand(for: launch) else {
            if let completion { DispatchQueue.main.async { MainActor.assumeIsolated { completion(false) } } }
            return
        }
        stop(server) { _ in
            DispatchQueue.global().async {
                // Give the kernel a moment to release the port.
                for _ in 0..<20 where !isPortFree(server.port) { usleep(250_000) }
                let launched = spawn(command, environment: launch.environment, cwd: cwd, port: server.port)
                if let completion { DispatchQueue.main.async { MainActor.assumeIsolated { completion(launched) } } }
            }
        }
    }

    /// The command line to run again. npm and Next.js overwrite their argv with a
    /// title (`npm run dev -p 3000`), which is what was typed, so that runs
    /// through a shell; intact argv is re-quoted as it was.
    static func shellCommand(for launch: ProcArgs) -> String? {
        let args = launch.arguments.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = args.first else { return nil }
        if ["sh", "bash", "zsh", "dash"].contains((first as NSString).lastPathComponent), args.count >= 3, args[1] == "-c" {
            return args[2]
        }
        if args.count == 1, first.contains(" ") {
            if let paren = first.range(of: " (") { return String(first[..<paren.lowerBound]) }
            return first
        }
        let executable = first.hasPrefix("/") ? first : launch.executablePath
        return ([executable] + args.dropFirst()).map(shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=@%+,"))
        if value.unicodeScalars.allSatisfy(safe.contains) { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func spawn(_ command: String, environment: [String: String], cwd: String, port: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = environment.isEmpty ? ProcessInfo.processInfo.environment : environment
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Porto")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("port-\(port).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: log) {
            process.standardOutput = handle
            process.standardError = handle
        }
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    /// Whether the pid is still the live process that started at `startedAt`.
    static func isSameProcess(_ pid: pid_t, startedAt: Date?) -> Bool {
        guard pid > 1, pid != getpid(), let snapshot = ProcessTable.snapshot(pid), !snapshot.isZombie else { return false }
        guard let startedAt else { return true }
        return abs(snapshot.startTime.timeIntervalSince(startedAt)) < 1
    }

    /// Whether nothing is accepting connections on the port any more.
    private static func isPortFree(_ port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return true }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result != 0
    }
}
