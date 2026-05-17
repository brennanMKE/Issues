import Foundation
import AppKit
import IssuesCore
import os.log

/// Installs the bundled `issues` and `issues-dashboard` command-line tools
/// onto the user's `PATH` (#0136).
///
/// Design choices (documented in `project-issues/0136.md`):
///
/// - **Symlink, not copy.** A symlink under `/usr/local/bin` keeps pointing at
///   whatever binary lives inside the currently-installed `.app`, so upgrading
///   the app upgrades the CLI for free. If the user moves the `.app`, they
///   re-run *Install Command Line Tools…*.
/// - **Destination: `/usr/local/bin`.** Conventional, already on every Mac
///   user's `PATH`. On Apple Silicon `/usr/local/bin` doesn't exist by
///   default, so the installer creates it via the same elevated shell
///   invocation.
/// - **Authorization via `osascript … with administrator privileges`.** No
///   helper tool, no SMJobBless / SMAppService daemon — overkill for a
///   one-shot `ln -sf`. `osascript` triggers the standard macOS
///   authentication panel.
/// - **Idempotent.** `ln -sf` overwrites cleanly. Re-running the command
///   silently refreshes the symlinks.
///
/// **Sandbox interaction:** Issues.app ships sandboxed
/// (`com.apple.security.app-sandbox = true`). Spawning `osascript` from a
/// sandboxed app is blocked at the OS level — the call fails with
/// "Operation not permitted" or similar. To keep the sandbox intact, the
/// installer falls back to writing a small shell script into the user's
/// Downloads folder and surfaces a Finder reveal so the user can run it
/// manually. Disabling the sandbox or shipping a privileged helper would be
/// required for a fully automated experience; both are out of scope for
/// this issue.
nonisolated enum CLIInstaller {
    /// The standard install location. On Apple Silicon `/usr/local/bin` may
    /// not exist; the elevated shell creates it on demand.
    static let installDirectory = "/usr/local/bin"

    /// Names of the binaries we expect to find inside `Contents/MacOS/`.
    static let binaryNames: [String] = ["issues", "issues-dashboard"]

    /// Successful install outcome. Surfaced to the UI so the confirmation
    /// alert can describe exactly what happened.
    struct InstallReport {
        /// The directory where the symlinks were created (always
        /// `/usr/local/bin` today, but kept on the report so future
        /// destinations don't need a UI change).
        let directory: String
        /// Full paths of the binaries inside the app bundle that were
        /// linked to. Useful in the confirmation copy ("symlinked to …").
        let sourcePaths: [URL]
        /// Whether the installer fell back to writing a shell script
        /// because the in-app authorization path was blocked (sandbox).
        let fallbackScriptURL: URL?
    }

    /// Failure surface for the menu action. Specific cases let the alert
    /// give the user something actionable rather than a stack trace.
    enum InstallError: LocalizedError {
        case bundleBinaryMissing(name: String, expectedPath: URL)
        case authorizationFailed(message: String)
        case fallbackWriteFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .bundleBinaryMissing(let name, let path):
                return "Couldn't find the bundled \(name) binary at \(path.path)."
            case .authorizationFailed(let message):
                return "The installer couldn't get permission to write to \(CLIInstaller.installDirectory). \(message)"
            case .fallbackWriteFailed(let error):
                return "Couldn't write the fallback install script: \(error.localizedDescription)"
            }
        }
    }

    private static let logger = Logger(subsystem: Logging.subsystem, category: "CLIInstaller")

    /// Resolve the absolute paths to the two CLI binaries inside the
    /// running `.app` bundle. The Issues target's Copy Files build phase
    /// places them under `Contents/SharedSupport/bin/` — NOT in
    /// `Contents/MacOS/`, where they would collide with the main
    /// `Issues` executable on a case-insensitive APFS volume (the CLI
    /// binary `issues` and the app binary `Issues` resolve to the same
    /// path on the default APFS configuration).
    static func bundledBinaryURLs() throws -> [URL] {
        let binDir = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("SharedSupport", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        return try binaryNames.map { name in
            let url = binDir.appendingPathComponent(name, isDirectory: false)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw InstallError.bundleBinaryMissing(name: name, expectedPath: url)
            }
            return url
        }
    }

    /// Run the install. Safe to call off the main thread; the caller is
    /// responsible for presenting any UI on the main actor.
    ///
    /// The flow:
    /// 1. Verify the two binaries are inside the running bundle.
    /// 2. Attempt elevated install via `osascript`. Sandbox often blocks
    ///    this — failure isn't fatal, we fall back.
    /// 3. On failure, write a shell script to `~/Downloads` and return
    ///    a `fallbackScriptURL` on the report so the UI can reveal it.
    static func install() throws -> InstallReport {
        let sources = try bundledBinaryURLs()
        logger.notice("Installing CLI tools from bundle: \(sources.map { $0.path }.joined(separator: ", "), privacy: .public)")

        let script = makeShellCommand(sources: sources)

        do {
            try runWithAdministratorPrivileges(shellCommand: script)
            logger.notice("CLI install succeeded via osascript.")
            return InstallReport(directory: installDirectory, sourcePaths: sources, fallbackScriptURL: nil)
        } catch {
            logger.error("Elevated install failed: \(String(describing: error), privacy: .public). Writing fallback script.")
            let fallback = try writeFallbackScript(shellCommand: script)
            return InstallReport(directory: installDirectory, sourcePaths: sources, fallbackScriptURL: fallback)
        }
    }

    // MARK: - Shell command

    /// Build a single-line shell command that:
    /// - Creates `/usr/local/bin` if needed.
    /// - Symlinks each source binary into it with `ln -sf` (idempotent).
    ///
    /// We deliberately quote each path with single quotes and escape any
    /// embedded single quote so spaces in the bundle path (e.g.
    /// `/Applications/Issues 2.app`) survive.
    private static func makeShellCommand(sources: [URL]) -> String {
        var parts: [String] = ["/bin/mkdir -p \(shellQuote(installDirectory))"]
        for source in sources {
            let dest = (installDirectory as NSString).appendingPathComponent(source.lastPathComponent)
            parts.append("/bin/ln -sf \(shellQuote(source.path)) \(shellQuote(dest))")
        }
        return parts.joined(separator: " && ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Elevated invocation

    /// Invoke `osascript` with `do shell script … with administrator
    /// privileges`. macOS shows the standard authentication panel. Throws
    /// `InstallError.authorizationFailed` on any non-zero exit or sandbox
    /// rejection.
    private static func runWithAdministratorPrivileges(shellCommand: String) throws {
        let osa = """
        do shell script \(appleScriptStringLiteral(shellCommand)) with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", osa]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw InstallError.authorizationFailed(message: "Couldn't launch osascript: \(error.localizedDescription)")
        }

        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // -128 is the AppleScript "user cancelled" reply; surface a
            // friendlier message than the raw osascript spew.
            if message.contains("User canceled") || message.contains("(-128)") {
                throw InstallError.authorizationFailed(message: "Authentication was cancelled.")
            }
            throw InstallError.authorizationFailed(message: message.isEmpty ? "Exit \(process.terminationStatus)." : message)
        }
    }

    /// Encode a Swift string as an AppleScript string literal — i.e. wrap in
    /// double quotes and backslash-escape any embedded backslash or quote.
    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Fallback script

    /// Write a self-contained shell script into the user's Downloads
    /// folder. The UI is expected to reveal it in Finder so the user can
    /// run it manually (`sudo sh ~/Downloads/install-issues-cli.sh`).
    ///
    /// The script starts with `#!/bin/sh`, `set -e`, and a short comment
    /// explaining what it does, so a user inspecting it before running
    /// `sudo` understands the change.
    private static func writeFallbackScript(shellCommand: String) throws -> URL {
        let downloads = (try? FileManager.default.url(
            for: .downloadsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        let target = downloads.appendingPathComponent("install-issues-cli.sh")

        let script = """
        #!/bin/sh
        # Issues.app — install the issues and issues-dashboard CLI tools.
        #
        # Run with: sudo sh "\(target.path)"
        #
        # This symlinks the two CLI binaries inside the running Issues.app
        # bundle into \(installDirectory) so they are on your PATH.
        set -e
        \(shellCommand)
        echo "Installed issues and issues-dashboard into \(installDirectory)."
        """

        do {
            try script.write(to: target, atomically: true, encoding: .utf8)
            // chmod +x so the user can `./install-issues-cli.sh` if they
            // prefer; running via `sh` works regardless.
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: target.path
            )
        } catch {
            throw InstallError.fallbackWriteFailed(underlying: error)
        }

        return target
    }
}
