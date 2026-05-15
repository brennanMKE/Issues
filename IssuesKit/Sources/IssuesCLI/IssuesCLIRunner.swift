import AppKit
import Foundation

public enum IssuesCLIRunner {
    private static let cliVersion = "1.0.0"

    private static let usage = """
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
      0  URL dispatched (waits for LaunchServices to ack so a missing app
         surfaces a non-zero exit; near-instant when Issues.app is running).
      1  Argument or filesystem error (e.g. <path> is not a directory).
      2  LaunchServices error (e.g. Issues.app is not installed).
    """

    private enum CLIError: Error {
        case usage(String)
        case notADirectory(String)
        case openFailed(String)
    }

    public static func main() async {
        do {
            try await run()
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
        try await dispatch(targetPath: targetPath)
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

    private static func dispatch(targetPath: String) async throws {
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

        do {
            _ = try await NSWorkspace.shared.open(url, configuration: config)
        } catch {
            throw CLIError.openFailed(error.localizedDescription)
        }
    }
}
