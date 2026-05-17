import SwiftUI
import AppKit
import IssuesCore
import os.log

/// `Install Command Line Tools…` menu item (#0136). Lifted into its own
/// `View` so it can carry state for the in-flight install — `CommandGroup`'s
/// closure is a result builder, not a `View`, and can't host `@State`.
///
/// The button:
///
/// 1. Disables itself while an install is running so a double-click can't
///    spawn two concurrent authorization panels.
/// 2. Hops to a background queue for the actual install (the `osascript`
///    call blocks while the user types their password).
/// 3. Presents an `NSAlert` on the main actor with the outcome — either
///    success ("`issues` and `issues-dashboard` are now on your PATH") or
///    failure (the localized error). On sandbox fall-back, the alert
///    offers to reveal the install script in Finder.
struct InstallCLIMenuButton: View {
    @State private var isInstalling = false

    private static let logger = Logger(subsystem: Logging.subsystem, category: "InstallCLIMenuButton")

    var body: some View {
        Button("Install Command Line Tools\u{2026}") {
            performInstall()
        }
        .disabled(isInstalling)
    }

    private func performInstall() {
        guard !isInstalling else { return }
        isInstalling = true
        Self.logger.notice("Install Command Line Tools menu item invoked.")

        // Hop off the main actor: the elevated `osascript` call blocks the
        // calling thread while the auth panel is on screen. Detached so we
        // don't inherit the menu-action actor context.
        Task.detached(priority: .userInitiated) {
            let result: Result<CLIInstaller.InstallReport, Error>
            do {
                let report = try CLIInstaller.install()
                result = .success(report)
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                isInstalling = false
                presentAlert(for: result)
            }
        }
    }

    @MainActor
    private func presentAlert(for result: Result<CLIInstaller.InstallReport, Error>) {
        let alert = NSAlert()
        switch result {
        case .success(let report):
            if let fallback = report.fallbackScriptURL {
                alert.alertStyle = .warning
                alert.messageText = "Finish installing in Terminal"
                alert.informativeText = """
                Issues.app couldn't request administrator permission directly because of the macOS sandbox.

                A shell script has been saved to:
                \(fallback.path)

                Run it in Terminal with:
                  sudo sh "\(fallback.path)"

                After that, the issues and issues-dashboard commands will be on your PATH.
                """
                alert.addButton(withTitle: "Reveal in Finder")
                alert.addButton(withTitle: "OK")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([fallback])
                }
            } else {
                alert.alertStyle = .informational
                alert.messageText = "Command line tools installed"
                alert.informativeText = """
                The issues and issues-dashboard commands have been symlinked into \(report.directory).

                You can now run them from any terminal — try `issues --help`.
                """
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }

        case .failure(let error):
            alert.alertStyle = .warning
            alert.messageText = "Couldn't install command line tools"
            alert.informativeText = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
