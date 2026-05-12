import AppKit
import Foundation

// MARK: - Constants

/// Version bumped by hand for v1. Will move to a build-time injection
/// from `MARKETING_VERSION` when the CLI is integrated into the Xcode
/// project (#0119 follow-up).
private let cliVersion = "1.0.0"

private let usage = """
usage: issues [<path>]
       issues -h | --help
       issues --version

  issues                 Open or focus the current directory in Issues.app.
                         Prefers $PWD/project-issues or $PWD/issues if
                         present; otherwise uses $PWD itself.
  issues <path>          Open or focus <path> in Issues.app. Absolute,
                         relative, or `~`-prefixed paths are accepted.
  issues -h | --help     Print this usage and exit 0.
  issues --version       Print the CLI version and exit 0.

Exit codes:
  0  URL dispatched (fire-and-forget; does not wait for the app to ack).
  1  Argument or filesystem error (e.g. <path> is not a directory).
  2  LaunchServices error (e.g. Issues.app is not installed).
"""

// MARK: - Errors

private enum CLIError: Error {
    case usage(String)
    case notADirectory(String)
    case openFailed(String)
}

// MARK: - Entry point

@MainActor
func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())

    if args.contains("-h") || args.contains("--help") {
        print(usage)
        return
    }
    if args.contains("--version") {
        print(cliVersion)
        return
    }
    if args.count > 1 {
        throw CLIError.usage("expected zero or one path argument; got \(args.count)")
    }

    let targetPath = try resolveTargetPath(arg: args.first)
    try dispatch(targetPath: targetPath)
}

/// Resolves the absolute path the CLI should hand to the app. With no
/// argument, prefers `$PWD/project-issues` then `$PWD/issues` then `$PWD`
/// itself — matching the spec's "if the cwd looks like an issues folder"
/// behaviour. With an argument, expands `~` and resolves relative paths
/// against `$PWD` before standardising.
private func resolveTargetPath(arg: String?) throws -> String {
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath

    if let arg = arg, !arg.isEmpty {
        let expanded = (arg as NSString).expandingTildeInPath
        let absolute: String
        if (expanded as NSString).isAbsolutePath {
            absolute = expanded
        } else {
            absolute = (cwd as NSString).appendingPathComponent(expanded)
        }
        let standardized = (absolute as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue else {
            throw CLIError.notADirectory(standardized)
        }
        return standardized
    }

    // No argument — prefer a project-issues / issues subdirectory if one
    // exists below cwd, otherwise use cwd itself.
    for candidate in ["project-issues", "issues"] {
        let path = (cwd as NSString).appendingPathComponent(candidate)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return (path as NSString).standardizingPath
        }
    }
    var cwdIsDir: ObjCBool = false
    guard fm.fileExists(atPath: cwd, isDirectory: &cwdIsDir), cwdIsDir.boolValue else {
        throw CLIError.notADirectory(cwd)
    }
    return (cwd as NSString).standardizingPath
}

/// Builds the `issues:///open?path=…` URL and asks LaunchServices to open
/// it. Fires-and-forgets — does not wait for the app to ack. If the app
/// is not yet running, LaunchServices launches it; if it is, the URL is
/// delivered via SwiftUI's `onOpenURL`.
@MainActor
private func dispatch(targetPath: String) throws {
    var comps = URLComponents()
    comps.scheme = "issues"
    comps.host = ""
    comps.path = "/open"
    comps.queryItems = [URLQueryItem(name: "path", value: targetPath)]
    guard let url = comps.url else {
        throw CLIError.openFailed("failed to construct URL for path \(targetPath)")
    }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true

    let group = DispatchGroup()
    group.enter()
    var openError: Error?
    NSWorkspace.shared.open(url, configuration: config) { _, error in
        if let error {
            openError = error
        }
        group.leave()
    }
    // Wait up to 5 seconds for LaunchServices to ack the open. The spec
    // calls for fire-and-forget, but waiting for the callback gives a real
    // exit code when Issues.app isn't installed — otherwise the CLI would
    // exit 0 even when nothing happened.
    let timeout = DispatchTime.now() + .seconds(5)
    if group.wait(timeout: timeout) == .timedOut {
        return
    }
    if let openError {
        throw CLIError.openFailed(openError.localizedDescription)
    }
}

// MARK: - Main

do {
    try MainActor.assumeIsolated {
        try run()
    }
    exit(0)
} catch CLIError.usage(let detail) {
    FileHandle.standardError.write(Data("error: \(detail)\n\n\(usage)\n".utf8))
    exit(1)
} catch CLIError.notADirectory(let path) {
    FileHandle.standardError.write(Data("error: not a directory: \(path)\n".utf8))
    exit(1)
} catch CLIError.openFailed(let detail) {
    FileHandle.standardError.write(Data("error: could not open Issues.app: \(detail)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
