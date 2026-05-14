// DashboardCommand.swift
//
// `issues-dashboard` CLI entry point. Mirrors IssuesCommand/IssuesCommand.swift
// for argument parsing, path resolution, and exit-code contract. On success,
// constructs an IssueStore, starts the 1 s poll loop, and hands off to
// SwiftTUI's Application run loop (which blocks until Ctrl-C).

import Foundation
import SwiftTUI

@main
struct DashboardCommand {
    private static let cliVersion = "1.0.0"

    private static let usage = """
    usage: issues-dashboard [<path>]
           issues-dashboard -h | --help
           issues-dashboard --version

      issues-dashboard                 Render a terminal dashboard for the
                                       current directory. Prefers
                                       $PWD/project-issues or $PWD/issues if
                                       present; otherwise uses $PWD itself.
      issues-dashboard <path>          Render the dashboard for <path>.
                                       Absolute, relative, or `~`-prefixed
                                       paths are accepted.
      issues-dashboard -h | --help     Print this usage and exit 0.
      issues-dashboard --version       Print the CLI version and exit 0.

    Exit codes:
      0  Clean exit (Ctrl-C from inside the TUI).
      1  Argument or filesystem error (e.g. <path> is not a directory).
    """

    private enum CLIError: Error {
        case usage(String)
        case notADirectory(String)
    }

    static func main() async {
        do {
            try await run()
            exit(0)
        } catch CLIError.usage(let detail) {
            FileHandle.standardError.write(Data("error: \(detail)\n\n\(usage)\n".utf8))
            exit(1)
        } catch CLIError.notADirectory(let path) {
            FileHandle.standardError.write(Data("error: not a directory: \(path)\n".utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run() async throws {
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
        let folderURL = URL(fileURLWithPath: targetPath, isDirectory: true)

        let store = IssueStore(folderURL: folderURL, interval: 1.0)
        store.start()

        // SwiftTUI's Application.start() installs its own SIGINT handler
        // and calls dispatchMain(), which blocks the calling thread.
        Application(rootView: ContentView(store: store)).start()
    }

    private static func resolveTargetPath(arg: String?) throws -> String {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath

        if let arg, !arg.isEmpty {
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
}
