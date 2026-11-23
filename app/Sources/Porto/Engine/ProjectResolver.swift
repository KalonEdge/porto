import Foundation

/// Works out what a server is for from its working directory: the project's
/// manifest and name, framework, git branch, and whether it's a worktree.
final class ProjectResolver {
    private struct Cached {
        let info: ProjectInfo
        let gitHead: String?
        let resolvedAt: Date
    }

    private var cache: [String: Cached] = [:]
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func resolve(cwd: String?, command: String?) -> ProjectInfo {
        guard let cwd else { return ProjectInfo(name: "Unknown") }

        if let cached = cache[cwd], Date().timeIntervalSince(cached.resolvedAt) < 15 {
            var info = cached.info
            // Branches change often, and HEAD is cheap to re-read.
            if let head = cached.gitHead { info.branch = Self.branch(fromHead: head) }
            return info
        }

        var info = ProjectInfo(name: URL(fileURLWithPath: cwd).lastPathComponent)
        var gitHead: String?
        var foundManifest = false
        var directory = URL(fileURLWithPath: cwd)

        while directory.path != "/" && directory.path != home {
            let path = directory.path
            if !foundManifest, let manifest = Self.manifest(in: path, command: command) {
                info.name = manifest.name ?? directory.lastPathComponent
                info.framework = manifest.framework
                info.root = path
                info.hasVercel = FileManager.default.fileExists(atPath: path + "/.vercel/project.json")
                foundManifest = true
            }
            if gitHead == nil, let git = Self.gitHead(in: path) {
                gitHead = git.headPath
                info.isWorktree = git.isWorktree
                if git.isWorktree { info.worktreeName = directory.lastPathComponent }
                if info.root == nil { info.root = path }
            }
            if foundManifest && gitHead != nil { break }
            directory.deleteLastPathComponent()
        }

        if let gitHead { info.branch = Self.branch(fromHead: gitHead) }
        cache[cwd] = Cached(info: info, gitHead: gitHead, resolvedAt: Date())
        return info
    }

    // MARK: - Manifests

    private static func manifest(in directory: String, command: String?) -> (name: String?, framework: String?)? {
        let files = FileManager.default
        if let data = files.contents(atPath: directory + "/package.json"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var dependencies: [String: String] = [:]
            for key in ["dependencies", "devDependencies"] {
                (json[key] as? [String: String])?.forEach { dependencies[$0.key] = $0.value }
            }
            return (json["name"] as? String, javaScriptFramework(dependencies, command: command))
        }
        if let text = try? String(contentsOfFile: directory + "/pyproject.toml", encoding: .utf8) {
            return (tomlName(text, section: "project") ?? tomlName(text, section: "tool.poetry"), pythonFramework(command: command, manifest: text))
        }
        if let text = try? String(contentsOfFile: directory + "/Cargo.toml", encoding: .utf8) {
            return (tomlName(text, section: "package"), "Rust")
        }
        if let text = try? String(contentsOfFile: directory + "/go.mod", encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.hasPrefix("module ") }) {
            let module = line.dropFirst("module ".count).trimmingCharacters(in: .whitespaces)
            return (module.split(separator: "/").last.map(String.init), "Go")
        }
        if files.fileExists(atPath: directory + "/Gemfile") {
            return (nil, files.fileExists(atPath: directory + "/config/application.rb") ? "Rails" : "Ruby")
        }
        return nil
    }

    private static let javaScriptFrameworks: [(package: String, label: String)] = [
        ("next", "Next.js"), ("nuxt", "Nuxt"), ("@remix-run/dev", "Remix"), ("astro", "Astro"),
        ("@sveltejs/kit", "SvelteKit"), ("expo", "Expo"), ("@angular/core", "Angular"), ("vite", "Vite"),
        ("react-scripts", "Create React App"), ("hono", "Hono"), ("express", "Express"),
    ]

    private static func javaScriptFramework(_ dependencies: [String: String], command: String?) -> String? {
        if command?.lowercased().contains("storybook") == true {
            let version = dependencies["storybook"] ?? dependencies.first { $0.key.hasPrefix("@storybook/") }?.value
            return version.map { labelled("Storybook", version: $0) } ?? "Storybook"
        }
        for framework in javaScriptFrameworks {
            if let version = dependencies[framework.package] { return labelled(framework.label, version: version) }
        }
        return nil
    }

    /// "Next.js 14" from "^14.2.3".
    private static func labelled(_ name: String, version: String) -> String {
        let major = version.drop { !$0.isNumber }.prefix { $0.isNumber }
        return major.isEmpty ? name : "\(name) \(major)"
    }

    private static func pythonFramework(command: String?, manifest: String) -> String {
        let haystack = (command ?? "").lowercased() + manifest.lowercased()
        let known = [("django", "Django"), ("fastapi", "FastAPI"), ("flask", "Flask"), ("uvicorn", "Uvicorn"), ("gunicorn", "Gunicorn")]
        return known.first { haystack.contains($0.0) }?.1 ?? "Python"
    }

    private static func tomlName(_ text: String, section: String) -> String? {
        var inSection = false
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line == "[\(section)]"
                continue
            }
            guard inSection, line.hasPrefix("name"), let quote = line.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let rest = line[line.index(after: quote)...]
            if let end = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) { return String(rest[..<end]) }
        }
        return nil
    }

    // MARK: - Git

    private static func gitHead(in directory: String) -> (headPath: String, isWorktree: Bool)? {
        let gitPath = directory + "/.git"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return (gitPath + "/HEAD", false) }
        // Worktrees and submodules have a `.git` file pointing at the real git dir.
        guard let contents = try? String(contentsOfFile: gitPath, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        var gitDir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !gitDir.hasPrefix("/") { gitDir = directory + "/" + gitDir }
        return (gitDir + "/HEAD", gitDir.contains("/worktrees/"))
    }

    private static func branch(fromHead headPath: String) -> String? {
        guard let head = try? String(contentsOfFile: headPath, encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") { return String(trimmed.dropFirst("ref: refs/heads/".count)) }
        // A detached HEAD shows its short commit.
        return trimmed.isEmpty ? nil : String(trimmed.prefix(7))
    }
}
