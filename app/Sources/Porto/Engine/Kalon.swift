import Foundation

/// Recognises local model servers and the apps around them by process name and path.
enum KalonFamily {
    static let bundleIdentifier = "ai.kalon.desktop"
    /// Listeners that are always scanned, whatever the watch list says.
    static let aiNames: Set<String> = ["Kalon", "ollama", "llama-server", "LM Studio"]

    private static let lock = NSLock()
    private nonisolated(unsafe) static var bundleIdentifiers: [String: String] = [:]

    static func isKalon(comm: String, path: String?) -> Bool {
        if comm == "Kalon" { return true }
        guard let path else { return false }
        return path.contains("/Kalon.app/") || bundleIdentifier(containing: path) == bundleIdentifier
    }

    static func isAI(comm: String, path: String?) -> Bool {
        if aiNames.contains(comm) || isKalon(comm: comm, path: path) { return true }
        guard let path else { return false }
        let name = (path as NSString).lastPathComponent
        return name == "ollama" || name == "llama-server" || path.contains("/Ollama.app/") || path.contains("/LM Studio.app/")
    }

    /// Muxora's listeners are short-lived helpers, not servers.
    static func isMuxora(comm: String, path: String?) -> Bool {
        if comm == "Muxora" { return true }
        guard let path else { return false }
        return path.contains("/Muxora.app/") || bundleIdentifier(containing: path) == "app.muxora.Muxora"
    }

    private static func bundleIdentifier(containing path: String) -> String? {
        guard path.contains(".app/"), let bundle = AppUsageScanner.appBundle(containing: path) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = bundleIdentifiers[bundle] { return cached }
        let identifier = Bundle(path: bundle)?.bundleIdentifier ?? ""
        bundleIdentifiers[bundle] = identifier
        return identifier
    }
}

struct KalonStatus: Equatable {
    enum Flavor: String { case kalon = "Kalon", ollama = "Ollama" }
    var flavor: Flavor
    var version: String?
    var active = 0
    var queued = 0
    var generating = 0

    /// Requests through the API only; the app's own chats show up as CPU instead.
    var isBusy: Bool { active > 0 || queued > 0 || generating > 0 }
}

struct KalonModel: Equatable {
    let name: String
    let size: UInt64
    /// The app's own model, which it never unloads.
    let isPrimary: Bool
}

/// One server as Kalon gets to see it: numbers and a cleaned-up name, nothing else.
struct KalonCandidate: Equatable {
    let port: Int
    let name: String
    let memoryMB: Int
    let cpu: Double
    let idleMinutes: Int
    let connections: Int
    let uptimeMinutes: Int
}

struct KalonAdvice: Equatable {
    var pause: [Int]
    var stop: [Int]
    var reason: String
}

/// Body and HTTP status, or nil when the server can't be reached in time.
protocol KalonTransport: Sendable {
    func send(_ request: URLRequest) async -> (data: Data, status: Int)?
}

struct URLSessionKalonTransport: KalonTransport {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = KalonClient.adviceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async -> (data: Data, status: Int)? {
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        return (data, http.statusCode)
    }
}

/// Talks to Kalon (or Ollama) on this Mac: whether it's up and busy, which
/// models it holds, and which idle servers it would let go of.
actor KalonClient {
    static let shared = KalonClient()
    static let defaultURL = "http://127.0.0.1:11434"
    static let statusTimeout: TimeInterval = 1.5
    static let connectTimeout: TimeInterval = 3
    static let adviceTimeout: TimeInterval = 20
    /// Kalon's process CPU above which it counts as generating.
    static let busyCPU = 20.0

    private let transport: KalonTransport
    private let fixedURL: URL?
    private var isAdvising = false

    init(transport: KalonTransport = URLSessionKalonTransport(), baseURL: URL? = nil) {
        self.transport = transport
        fixedURL = baseURL
    }

    private var baseURL: URL {
        fixedURL ?? UserDefaults.standard.string(forKey: Preferences.kalonURL).flatMap(URL.init(string:)) ?? URL(string: Self.defaultURL)!
    }

    // MARK: - Status

    func status() async -> KalonStatus? {
        await status(timeout: Self.statusTimeout)
    }

    private func status(timeout: TimeInterval) async -> KalonStatus? {
        guard let root = await get("", timeout: timeout), root.status == 200 else { return nil }
        let banner = String(decoding: root.data, as: UTF8.self)
        var status: KalonStatus
        if banner.contains("Kalon is running") {
            status = KalonStatus(flavor: .kalon)
        } else if banner.contains("Ollama is running") {
            status = KalonStatus(flavor: .ollama)
        } else {
            return nil
        }
        if let version = await json("api/version", timeout: timeout)?["version"] as? String { status.version = version }
        if status.flavor == .kalon, let health = await json("health", timeout: timeout) {
            status.active = health["active"] as? Int ?? 0
            status.queued = health["queued"] as? Int ?? 0
            status.generating = (health["generating"] as? [Any])?.count ?? 0
        }
        return status
    }

    func loadedModels() async -> [KalonModel] {
        guard let models = await json("api/ps", timeout: Self.statusTimeout)?["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { model in
            guard let name = model["name"] as? String else { return nil }
            let expires = model["expires_at"] as? String ?? ""
            return KalonModel(name: name, size: (model["size"] as? NSNumber)?.uint64Value ?? 0, isPrimary: expires.hasPrefix("9999-"))
        }
    }

    /// Asks Kalon to let go of pool models nobody is using. The app's primary
    /// model stays, and nothing happens while it's generating.
    func unloadIdlePoolModels(processCPU: Double = 0) async -> [String] {
        guard processCPU < Self.busyCPU, let status = await status(), !status.isBusy else { return [] }
        var unloaded: [String] = []
        for model in await loadedModels() where !model.isPrimary {
            let body: [String: Any] = ["model": model.name, "keep_alive": 0]
            if let response = await post("api/generate", body: body, timeout: Self.adviceTimeout), response.status == 200 {
                unloaded.append(model.name)
            }
        }
        return unloaded
    }

    // MARK: - Advice

    /// Which of the candidates Kalon would pause or stop. Nil when it isn't
    /// reachable, is busy, has no suitable model, or answers with nothing usable.
    /// One request at a time; a second call while one is running returns nil.
    func advise(candidates: [KalonCandidate], pressure: MemoryPressure, cpuBound: Bool = false, freeMemory: UInt64? = nil) async -> KalonAdvice? {
        guard !isAdvising, !candidates.isEmpty else { return nil }
        isAdvising = true
        defer { isAdvising = false }

        guard let status = await status(timeout: Self.connectTimeout), !status.isBusy,
              let model = await adviceModel(pressure: pressure, freeMemory: freeMemory) else { return nil }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt(cpuBound: cpuBound)],
                ["role": "user", "content": Self.prompt(for: candidates)],
            ],
            "temperature": 0,
            "max_tokens": 300,
            "keep_alive": "30s",
            "stream": false,
        ]
        guard let response = await post("v1/chat/completions", body: body, timeout: Self.adviceTimeout), response.status == 200,
              let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let choice = (object["choices"] as? [[String: Any]])?.first,
              let content = (choice["message"] as? [String: Any])?["content"] as? String else { return nil }
        return Self.parseAdvice(content, candidates: Set(candidates.map(\.port)))
    }

    /// A model that's already in memory, else the smallest installed one that
    /// can follow the prompt. Never loads one while memory is critical, or one
    /// that wouldn't fit in what's free.
    private func adviceModel(pressure: MemoryPressure, freeMemory: UInt64?) async -> String? {
        let resident = await loadedModels().map(\.name)
        if let model = resident.first(where: { !Self.isReasoning($0) }) ?? resident.first { return model }
        guard pressure < .critical, let models = await json("api/tags", timeout: Self.connectTimeout)?["models"] as? [[String: Any]] else { return nil }
        let installed: [(name: String, size: UInt64)] = models.compactMap { model in
            guard let name = model["name"] as? String,
                  let parameters = ((model["details"] as? [String: Any])?["parameter_size"] as? String).flatMap(Self.parameterCount),
                  parameters >= 1_000_000_000 else { return nil }
            return (name, (model["size"] as? NSNumber)?.uint64Value ?? 0)
        }
        return Self.pickModel(from: installed, freeMemory: freeMemory)
    }

    static func pickModel(from installed: [(name: String, size: UInt64)], freeMemory: UInt64?) -> String? {
        let fitting = installed.filter { model in freeMemory.map { model.size <= $0 / 2 } ?? true }
        let ordered = fitting.sorted { ($0.size, $0.name) < ($1.size, $1.name) }
        return (ordered.first { !isReasoning($0.name) } ?? ordered.first)?.name
    }

    /// Reasoning models think out loud for longer than the answer is worth.
    static func isReasoning(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("r1") || lowered.contains("think")
    }

    /// "1.5B" is 1.5 billion parameters, "494M" under half a billion.
    static func parameterCount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard let unit = trimmed.last, let value = Double(trimmed.dropLast()) else { return Double(trimmed) }
        switch unit {
        case "K": return value * 1_000
        case "M": return value * 1_000_000
        case "B": return value * 1_000_000_000
        case "T": return value * 1_000_000_000_000
        default: return nil
        }
    }

    // MARK: - Prompt

    static func systemPrompt(cpuBound: Bool) -> String {
        """
        This Mac is short on \(cpuBound ? "CPU" : "memory"). Each line describes one idle local development server. \
        Choose which to \(cpuBound ? "pause" : "stop") to relieve it, using only ports from the list. \
        Prefer servers that are large and have been idle longest; leave out any that look in use. \
        Reply with JSON only, no other text: {"pause":[ports],"stop":[ports],"reason":"one short sentence"}
        """
    }

    /// Numbers and a cleaned-up name per server. Commands, paths, environments
    /// and session titles never leave the scan.
    static func prompt(for candidates: [KalonCandidate]) -> String {
        candidates.map { candidate in
            "port=\(candidate.port) name=\(sanitize(candidate.name)) memory_mb=\(candidate.memoryMB) cpu_percent=\(Int(candidate.cpu.rounded()))"
                + " idle_minutes=\(candidate.idleMinutes) connections=\(candidate.connections) uptime_minutes=\(candidate.uptimeMinutes)"
        }.joined(separator: "\n")
    }

    /// Letters, digits and a little punctuation, at most 40 characters, so a
    /// folder name can't smuggle instructions into the prompt.
    static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.@"))
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter(allowed.contains)))
        return cleaned.isEmpty ? "server" : String(cleaned.prefix(40))
    }

    /// Reads the first JSON object in the reply that has the expected shape,
    /// whatever the model wrapped around it. Ports outside the candidates are dropped.
    static func parseAdvice(_ text: String, candidates: Set<Int>) -> KalonAdvice? {
        let visible = text.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression)
        for block in jsonBlocks(in: visible) {
            guard let data = block.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["pause"] != nil || object["stop"] != nil else { continue }
            func ports(_ key: String) -> [Int] {
                var seen = Set<Int>()
                return ((object[key] as? [Any]) ?? []).compactMap { value -> Int? in
                    if let number = value as? Int { return number }
                    if let text = value as? String { return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: ": "))) }
                    return nil
                }.filter { candidates.contains($0) && seen.insert($0).inserted }
            }
            let pause = ports("pause")
            // Pausing wins when a port is named twice; it can be undone.
            let stop = ports("stop").filter { !pause.contains($0) }
            let reason = (object["reason"] as? String ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
            return KalonAdvice(pause: pause, stop: stop, reason: String(String(String.UnicodeScalarView(reason)).prefix(160)))
        }
        return nil
    }

    /// Every balanced top-level {…} in the text, in order.
    private static func jsonBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"" where depth > 0:
                inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}" where depth > 0:
                depth -= 1
                if depth == 0, let begin = start { blocks.append(String(text[begin...index])) }
            default:
                break
            }
        }
        return blocks
    }

    // MARK: - HTTP

    private func get(_ path: String, timeout: TimeInterval) async -> (data: Data, status: Int)? {
        var request = URLRequest(url: path.isEmpty ? baseURL : baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
        return await transport.send(request)
    }

    private func json(_ path: String, timeout: TimeInterval) async -> [String: Any]? {
        guard let response = await get(path, timeout: timeout), response.status == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: response.data) as? [String: Any]
    }

    private func post(_ path: String, body: [String: Any], timeout: TimeInterval) async -> (data: Data, status: Int)? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return await transport.send(request)
    }
}
