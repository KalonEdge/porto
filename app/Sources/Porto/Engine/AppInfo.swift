import Foundation

/// The app's version and links, from Info.plist so a release can point them
/// anywhere without a code change (see build-app.sh).
enum AppInfo {
    private static func value(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    static var version: String { value("CFBundleShortVersionString") ?? "dev" }
    static var build: String? { value("CFBundleVersion") }

    /// The project's source repository, for issues and the About pane.
    static var repository: URL { URL(string: value("PortoRepository") ?? "https://github.com/KalonEdge/porto")! }

    /// The website, when this build names one: the About pane links it and the tip jar lives at /tip.
    static var website: URL? { value("PortoWebsite").flatMap(URL.init(string:)) }

    static var tipJar: URL? { website?.appendingPathComponent("tip") }
}

/// Prefilled GitHub issue links, so reports arrive with what's needed to reproduce them.
enum FeedbackLink {
    enum Kind { case bug, feature }

    static func issue(_ kind: Kind) -> URL {
        let label: String
        let body: String
        switch kind {
        case .bug:
            label = "bug"
            body = """
            **What happened?**


            **What did you expect?**


            **Steps to reproduce**
            1.

            ---
            \(environment)
            """
        case .feature:
            label = "enhancement"
            body = """
            **What would you like Porto to do?**


            **Why would it help?**


            ---
            \(environment)
            """
        }
        var components = URLComponents(url: AppInfo.repository.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "labels", value: label), URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    /// App version and build, macOS version and chip. Nothing about servers, projects or paths.
    static var environment: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let chip = "Apple silicon"
        #else
        let chip = "Intel"
        #endif
        return "Porto \(AppInfo.version) (\(AppInfo.build ?? "dev")) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(chip)"
    }
}
