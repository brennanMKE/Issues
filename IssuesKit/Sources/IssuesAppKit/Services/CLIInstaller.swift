import Foundation
import AppKit
import IssuesCore
import os.log

/// Builds the shell command that installs the bundled `issues` and
/// `issues-dashboard` CLI tools onto the user's `PATH` (#0136).
///
/// **Why the app doesn't run the command itself:** Issues.app is sandboxed
/// (`com.apple.security.app-sandbox = true`). The sandbox blocks both
/// elevated `osascript` invocations (`do shell script … with administrator
/// privileges`) and writes to `~/Downloads` without an explicit user
/// grant, so the obvious "click to install" paths all fail. Rather than
/// drop the sandbox, the installer surfaces the exact command for the
/// user to run in Terminal — transparent (they see what's about to run
/// as root) and reliable (no sandbox interaction at all).
///
/// Design choices documented in `project-issues/0136.md`:
///
/// - **Symlink, not copy.** A symlink under `/usr/local/bin` keeps pointing
///   at whatever binary lives inside the currently-installed `.app`, so
///   upgrading the app upgrades the CLI for free.
/// - **Destination: `/usr/local/bin`.** Conventional, already on every Mac
///   user's `PATH`. On Apple Silicon `/usr/local/bin` doesn't exist by
///   default, so the command creates it.
/// - **Idempotent.** `ln -sf` overwrites cleanly. Re-running the command
///   silently refreshes the symlinks.
nonisolated enum CLIInstaller {
    /// The standard install location.
    static let installDirectory = "/usr/local/bin"

    /// Names of the binaries we expect to find inside the bundle.
    static let binaryNames: [String] = ["issues", "issues-dashboard"]

    /// The data the menu button needs to present its alert.
    struct InstallCommand {
        /// The install directory the symlinks will be created in
        /// (always `/usr/local/bin` today).
        let directory: String
        /// Absolute paths of the binaries inside the running `.app`
        /// bundle, in the same order as `binaryNames`. Used in the
        /// alert copy ("symlinked from …").
        let sourcePaths: [URL]
        /// The full shell command, ready to paste into Terminal. Starts
        /// with `sudo` and includes `mkdir -p` + `ln -sf` for both
        /// binaries.
        let shellCommand: String
    }

    enum InstallError: LocalizedError {
        case bundleBinaryMissing(name: String, expectedPath: URL)

        var errorDescription: String? {
            switch self {
            case .bundleBinaryMissing(let name, let path):
                return "Couldn't find the bundled \(name) binary at \(path.path)."
            }
        }
    }

    private static let logger = Logger(subsystem: Logging.subsystem, category: "CLIInstaller")

    /// Resolve the absolute paths to the two CLI binaries inside the
    /// running `.app` bundle. The Issues target's Copy Files build phase
    /// places them under `Contents/SharedSupport/bin/` — NOT in
    /// `Contents/MacOS/`, where they would collide with the main `Issues`
    /// executable on a case-insensitive APFS volume.
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

    /// Resolve the bundled binaries and build the shell command the user
    /// should run. The command is wrapped in a single `sudo sh -c '…'`
    /// invocation so the user only types their password once.
    static func makeInstallCommand() throws -> InstallCommand {
        let sources = try bundledBinaryURLs()
        let inner = makeInnerShellCommand(sources: sources)
        let command = "sudo sh -c \(shellQuote(inner))"
        logger.notice("Built install command for: \(sources.map { $0.path }.joined(separator: ", "), privacy: .public)")
        return InstallCommand(
            directory: installDirectory,
            sourcePaths: sources,
            shellCommand: command
        )
    }

    /// Build the inner shell command — `mkdir -p` plus one `ln -sf` per
    /// binary. Wrapped by `makeInstallCommand` inside a single `sudo sh
    /// -c '…'` so the whole thing runs under one auth prompt.
    private static func makeInnerShellCommand(sources: [URL]) -> String {
        var parts: [String] = ["mkdir -p \(shellQuote(installDirectory))"]
        for source in sources {
            let dest = (installDirectory as NSString).appendingPathComponent(source.lastPathComponent)
            parts.append("ln -sf \(shellQuote(source.path)) \(shellQuote(dest))")
        }
        return parts.joined(separator: " && ")
    }

    /// Quote a value as a POSIX single-quoted string, escaping any
    /// embedded single quote. Used both for the inner command and for
    /// wrapping the whole thing as `sh -c '…'`.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
