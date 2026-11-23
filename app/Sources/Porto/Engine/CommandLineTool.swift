import Foundation

/// The `porto` command: a symlink in /usr/local/bin to this app's executable,
/// which runs the terminal UI when invoked by that name. Linking the app's own
/// path rather than copying it keeps the command current through updates.
enum CommandLineTool {
    static let linkPath = "/usr/local/bin/porto"

    enum State: Equatable {
        /// Not running from a stable app bundle, e.g. `swift run` or a translocated download.
        case unavailable
        case notInstalled
        case installed
        /// Something else is at the link path: another copy, a missing app or a different tool.
        case other(String)
    }

    /// Only an app bundle in a stable location can be linked to.
    static var executablePath: String? {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
              !path.contains("/AppTranslocation/") else { return nil }
        return path
    }

    static var state: State {
        guard let target = executablePath else { return .unavailable }
        let files = FileManager.default
        guard let destination = try? files.destinationOfSymbolicLink(atPath: linkPath) else {
            return files.fileExists(atPath: linkPath) ? .other(linkPath) : .notInstalled
        }
        let resolved = URL(fileURLWithPath: destination, relativeTo: URL(fileURLWithPath: "/usr/local/bin")).resolvingSymlinksInPath().path
        return resolved == target ? .installed : .other(resolved)
    }

    /// Links the command, asking for an administrator password only when
    /// /usr/local/bin isn't writable. Returns an error message, or nil on
    /// success or when the password prompt is cancelled.
    static func install() -> String? {
        guard let target = executablePath else { return L10n.text("Move Porto to Applications first.") }
        let files = FileManager.default
        let directory = (linkPath as NSString).deletingLastPathComponent
        if files.isWritableFile(atPath: directory) {
            do {
                if (try? files.destinationOfSymbolicLink(atPath: linkPath)) != nil || files.fileExists(atPath: linkPath) {
                    try files.removeItem(atPath: linkPath)
                }
                try files.createSymbolicLink(atPath: linkPath, withDestinationPath: target)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        return runAsAdministrator("mkdir -p \(shellQuote(directory)) && ln -sfn \(shellQuote(target)) \(shellQuote(linkPath))")
    }

    /// Removes the link, but only when it's Porto's.
    static func uninstall() -> String? {
        guard state == .installed else { return nil }
        if FileManager.default.isWritableFile(atPath: (linkPath as NSString).deletingLastPathComponent) {
            do {
                try FileManager.default.removeItem(atPath: linkPath)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        return runAsAdministrator("rm -f \(shellQuote(linkPath))")
    }

    private static func runAsAdministrator(_ command: String) -> String? {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        guard let error else { return nil }
        // -128: the password prompt was cancelled.
        if error[NSAppleScript.errorNumber] as? Int == -128 { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? L10n.text("The command couldn’t be installed.")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
