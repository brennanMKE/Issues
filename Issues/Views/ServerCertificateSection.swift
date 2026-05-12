import SwiftUI

#if os(macOS)
import AppKit

/// "Server certificate" section in the host settings sheet (#0115).
/// Displays the current TLS cert's SHA-256 fingerprint in two rows of
/// eight 4-char hex quads (32 chars per row, ssh-keygen-style density),
/// lets the user copy the raw 64-char hex, and offers a confirm-gated
/// rotate action.
struct ServerCertificateSection: View {

    @Bindable var controller: RemoteHostController
    @State private var showingRotateConfirm: Bool = false
    @State private var rotateError: String?

    var body: some View {
        Section("Server certificate") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fingerprint (SHA-256):")
                    .font(.callout)
                Text(formattedFingerprint)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Button("Copy fingerprint") {
                        copyToPasteboard(controller.currentFingerprint)
                    }
                    .disabled(controller.currentFingerprint.isEmpty)

                    Button("Rotate certificate\u{2026}") {
                        showingRotateConfirm = true
                    }
                    .disabled(controller.currentFingerprint.isEmpty)
                }

                Text("Rotation invalidates every existing access token. All viewers will need a fresh token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let rotateError {
                    Text(rotateError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog(
            "Confirm certificate rotation",
            isPresented: $showingRotateConfirm,
            titleVisibility: .visible
        ) {
            Button("Rotate", role: .destructive) { rotate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rotating the certificate invalidates every access token issued against the current certificate. All connected viewers will be disconnected and must paste a new token before they can reconnect.")
        }
    }

    /// Renders the 64-char hex as two rows of eight space-separated
    /// 4-char quads (e.g. `a3f1 e0c0 82b4 1d77 9b6e 4f3a c8d2 1e5b\n7a0c …`).
    /// Empty input renders a placeholder em-dash.
    private var formattedFingerprint: String {
        let hex = controller.currentFingerprint
        guard hex.count == 64 else { return "—" }
        let quads = stride(from: 0, to: 64, by: 4).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 4)
            return String(hex[start..<end])
        }
        let firstRow = quads.prefix(8).joined(separator: " ")
        let secondRow = quads.suffix(8).joined(separator: " ")
        return "\(firstRow)\n\(secondRow)"
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func rotate() {
        rotateError = nil
        do {
            _ = try controller.rotateCertificate()
        } catch {
            rotateError = "Couldn't rotate: \(error.localizedDescription)"
        }
    }
}

#endif
