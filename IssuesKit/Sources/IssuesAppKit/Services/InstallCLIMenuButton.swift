import SwiftUI
import AppKit
import IssuesCore
import os.log

/// `Install Command Line Tools…` menu item (#0136).
///
/// Because Issues.app is sandboxed, the app itself can't elevate to write
/// into `/usr/local/bin`. Instead, this menu item shows the exact shell
/// command the user needs to run in Terminal, puts it on the clipboard,
/// and offers a one-click "Open Terminal" button. The user pastes, types
/// their `sudo` password, done — fully transparent, no entitlement or
/// privileged-helper gymnastics.
struct InstallCLIMenuButton: View {
    private static let logger = Logger(subsystem: Logging.subsystem, category: "InstallCLIMenuButton")

    var body: some View {
        Button("Install Command Line Tools\u{2026}") {
            presentInstallSheet()
        }
    }

    private func presentInstallSheet() {
        Self.logger.notice("Install Command Line Tools menu item invoked.")

        let alert = NSAlert()
        do {
            let command = try CLIInstaller.makeInstallCommand()
            alert.alertStyle = .informational
            alert.messageText = "Install issues and issues-dashboard"
            alert.informativeText = """
            Issues.app is sandboxed and can't write to \(command.directory) directly. Copy the command below, paste it into Terminal, and press Return. You'll be asked for your password.

            \(command.shellCommand)

            This symlinks the two CLI binaries from inside Issues.app into \(command.directory) so you can run them from any terminal.
            """
            alert.addButton(withTitle: "Copy & Open Terminal")
            alert.addButton(withTitle: "Copy")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                copyToPasteboard(command.shellCommand)
                openTerminal()
            case .alertSecondButtonReturn:
                copyToPasteboard(command.shellCommand)
            default:
                break
            }
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't prepare the install command"
            alert.informativeText = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }

    /// Open Terminal.app without sending it any text — sandboxed apps
    /// can't script Terminal directly (that needs an Apple Events
    /// entitlement), so the user pastes from the clipboard.
    private func openTerminal() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(terminal)
    }
}
