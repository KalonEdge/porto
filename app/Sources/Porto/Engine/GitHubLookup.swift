import Foundation

struct PreviewDeployment: Equatable {
    enum State: Equatable { case ready, building, failed }
    let url: URL
    let state: State
    let createdAt: Date?
}

struct PullRequestInfo: Equatable {
    let number: Int
    let title: String
    let url: URL
    let state: String
}

/// Finds a branch's Vercel preview and pull request through the GitHub CLI.
/// Vercel's GitHub integration records every preview as a GitHub deployment,
/// so no Vercel token is needed. Results are cached per branch.
@MainActor
final class GitHubLookup: ObservableObject {
    struct Result: Equatable {
        var preview: PreviewDeployment?
        var pullRequest: PullRequestInfo?
    }

    @Published private(set) var results: [String: Result] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var inFlight = Set<String>()
    private let queue = DispatchQueue(label: "com.porto.github", qos: .utility)

    nonisolated static let ghPath: String? = {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", NSHomeDirectory() + "/homebrew/bin/gh"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? which("gh")
    }()

    nonisolated static var isAvailable: Bool { ghPath != nil }

    private var wantsPreviews: Bool { UserDefaults.standard.bool(forKey: Preferences.vercelPreviews) }
    private var wantsPullRequests: Bool { UserDefaults.standard.bool(forKey: Preferences.githubPullRequests) }

    func result(for server: Server) -> Result? {
        Self.key(for: server).flatMap { results[$0] }
    }

    /// Refreshes when enabled and the cached result is older than `maxAge`.
    func refresh(_ server: Server, maxAge: TimeInterval = 120) {
        guard wantsPreviews || wantsPullRequests, let gh = Self.ghPath, let key = Self.key(for: server),
              let root = server.project.root, let branch = server.project.branch, !inFlight.contains(key) else { return }
        if let fetched = fetchedAt[key], Date().timeIntervalSince(fetched) < maxAge { return }
        inFlight.insert(key)
        let previews = wantsPreviews, pullRequests = wantsPullRequests
        queue.async {
            var result = Result()
            if previews { result.preview = Self.preview(gh: gh, root: root, branch: branch) }
            if pullRequests { result.pullRequest = Self.pullRequest(gh: gh, root: root, branch: branch) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.results[key] = result
                    self.fetchedAt[key] = Date()
                    self.inFlight.remove(key)
                }
            }
        }
    }

    private static func key(for server: Server) -> String? {
        guard let root = server.project.root, let branch = server.project.branch else { return nil }
        return root + "|" + branch
    }

    // MARK: - Queries

    nonisolated private static func preview(gh: String, root: String, branch: String) -> PreviewDeployment? {
        // Deployments are keyed by commit, so match them against the branch's recent commits.
        guard let commitList = run(gh, ["api", "repos/{owner}/{repo}/commits?sha=\(branch)&per_page=30", "--jq", ".[].sha"], in: root) else { return nil }
        let commits = commitList.split(separator: "\n").map(String.init)
        guard !commits.isEmpty,
              let deploymentsJSON = run(gh, ["api", "repos/{owner}/{repo}/deployments?per_page=50"], in: root),
              let deployments = try? JSONSerialization.jsonObject(with: Data(deploymentsJSON.utf8)) as? [[String: Any]] else { return nil }

        let rank = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($1, $0) })
        let newest = deployments
            .filter { ($0["environment"] as? String)?.localizedCaseInsensitiveContains("preview") == true }
            .compactMap { deployment -> (Int, [String: Any])? in
                guard let sha = deployment["sha"] as? String, let position = rank[sha] else { return nil }
                return (position, deployment)
            }
            .min { $0.0 < $1.0 }?.1
        guard let newest, let id = newest["id"] as? Int,
              let statusJSON = run(gh, ["api", "repos/{owner}/{repo}/deployments/\(id)/statuses?per_page=1"], in: root),
              let status = (try? JSONSerialization.jsonObject(with: Data(statusJSON.utf8)) as? [[String: Any]])?.first else { return nil }

        let link = (status["environment_url"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? status["target_url"] as? String
        guard let link, let url = URL(string: link), url.scheme == "https" else { return nil }
        let state: PreviewDeployment.State
        switch status["state"] as? String {
        case "success": state = .ready
        case "failure", "error": state = .failed
        default: state = .building
        }
        let created = (newest["created_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        return PreviewDeployment(url: url, state: state, createdAt: created)
    }

    nonisolated private static func pullRequest(gh: String, root: String, branch: String) -> PullRequestInfo? {
        guard let output = run(gh, ["pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", "number,title,url,state"], in: root),
              let pr = (try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])?.first,
              let number = pr["number"] as? Int, let link = pr["url"] as? String, let url = URL(string: link), url.scheme == "https" else { return nil }
        return PullRequestInfo(number: number, title: pr["title"] as? String ?? "", url: url, state: (pr["state"] as? String ?? "").capitalized)
    }

    // MARK: - Processes

    nonisolated private static func run(_ executable: String, _ arguments: [String], in directory: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func which(_ command: String) -> String? {
        guard let path = run("/bin/zsh", ["-lc", "command -v \(command)"], in: NSHomeDirectory()), path.hasPrefix("/") else { return nil }
        return path
    }
}
