import SwiftUI

#if os(macOS)

/// Disconnect / expired-token banner for remote tabs (#0104). Reads the
/// active store's `remoteConnectionState`; renders nothing for
/// `connected` (or for local tabs, where the state is `nil`). Surfaces
/// the appropriate action button per state:
///
///   - `.reconnecting`        → spinner + "Reload now"
///   - `.disconnected`        → exclamation + "Reload now"
///   - `.tokenInvalid`        → red icon + "Paste new token" (opens the
///                              picker, which lands in its token-paste phase)
///   - `.folderUnavailable`   → yellow icon + "Manage subscriptions"
///                              (placeholder; full sheet ships in #0098)
///
/// Banners are dismissible per-session via the trailing `×`; dismissal
/// resets the next time the connection state changes.
struct RemoteConnectionBanner: View {

    @Bindable var store: IssueStore
    /// Per-session dismissal. Keyed off the state's discriminant so a
    /// `reconnecting → reconnecting (different since:)` transition
    /// doesn't accidentally un-dismiss.
    @State private var dismissedKey: String?

    var body: some View {
        if let state = store.remoteConnectionState, state != .connected, dismissedKey != Self.discriminant(of: state) {
            HStack(alignment: .top, spacing: 10) {
                icon(for: state)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: state))
                        .font(.callout.bold())
                    Text(detail(for: state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let action = action(for: state) {
                    Button(action.label) { action.handler() }
                        .controlSize(.regular)
                }
                Button {
                    dismissedKey = Self.discriminant(of: state)
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(background(for: state))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.appBorder)
                    .frame(height: 1)
            }
            .onChange(of: state) { _, newState in
                // Re-show the banner if the state's discriminant changed
                // (e.g. reconnecting → disconnected).
                if Self.discriminant(of: newState) != dismissedKey {
                    dismissedKey = nil
                }
            }
        }
    }

    // MARK: - State → view glue

    private func icon(for state: RemoteConnectionState) -> some View {
        switch state {
        case .connected:
            return AnyView(EmptyView())
        case .reconnecting:
            return AnyView(
                ProgressView()
                    .controlSize(.small)
            )
        case .disconnected:
            return AnyView(
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            )
        case .tokenInvalid:
            return AnyView(
                Image(systemName: "lock.slash.fill")
                    .foregroundStyle(.red)
            )
        case .folderUnavailable:
            return AnyView(
                Image(systemName: "questionmark.folder.fill")
                    .foregroundStyle(.orange)
            )
        }
    }

    private func title(for state: RemoteConnectionState) -> String {
        switch state {
        case .connected: return ""
        case .reconnecting: return "Reconnecting to \(store.displayName)…"
        case .disconnected: return "Disconnected from \(store.displayName)"
        case .tokenInvalid: return "Access token was revoked or expired"
        case .folderUnavailable: return "Folder no longer shared by host"
        }
    }

    private func detail(for state: RemoteConnectionState) -> String {
        switch state {
        case .connected: return ""
        case .reconnecting(let since): return "Trying again — since \(Self.timeOnly(since))"
        case .disconnected(let reason): return "Showing the last-known content. (\(reason))"
        case .tokenInvalid: return "Generate a new token in Issues.app on the host, then paste it."
        case .folderUnavailable: return "Choose another folder on the host, or close this tab."
        }
    }

    private func action(for state: RemoteConnectionState) -> (label: String, handler: () -> Void)? {
        switch state {
        case .connected: return nil
        case .reconnecting, .disconnected:
            return ("Reload now", { store.reload() })
        case .tokenInvalid:
            return ("Paste new token", { AppCommandsController.shared.openRemoteFolderPicker?() })
        case .folderUnavailable:
            // #0098 (manage subscriptions) is the proper home; until it
            // lands, route the user back to the picker.
            return ("Manage subscriptions", { AppCommandsController.shared.openRemoteFolderPicker?() })
        }
    }

    @ViewBuilder
    private func background(for state: RemoteConnectionState) -> some View {
        switch state {
        case .tokenInvalid:
            Color.red.opacity(0.08)
        case .folderUnavailable, .disconnected:
            Color.orange.opacity(0.08)
        default:
            Color.appBackgroundCard.opacity(0.6)
        }
    }

    private static func discriminant(of state: RemoteConnectionState) -> String {
        switch state {
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .disconnected: return "disconnected"
        case .tokenInvalid: return "tokenInvalid"
        case .folderUnavailable: return "folderUnavailable"
        }
    }

    private static func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#endif
