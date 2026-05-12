import SwiftUI
import os.log

#if os(macOS)

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "RemoteFolderPickerView")

/// Three-phase picker for opening one or more remote folders as tabs
/// (#0091 / #0096 / #0097). The phases share one window so the user
/// stays in flow:
///
/// 1. **Pick host** — manual `host:port` entry plus a "Recent" list and a
///    placeholder slot for Bonjour-discovered hosts (#0089, blocked on
///    multicast entitlement, surfaces empty state today).
/// 2. **Paste token** — single-line field; validated by a second
///    `GET /v1/host` call. On 200 the token is written to `ViewerTokenStore`.
/// 3. **Pick folders** — list of `FolderInfo` with checkboxes + select-all
///    / select-none. On Confirm, one `TabsModel.openRemoteTab(...)` per
///    checked folder, then the window closes.
struct RemoteFolderPickerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var model = RemoteFolderPickerModel()

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .host:
                RemotePickerHostPhase(model: model)
            case .token(let host, let port):
                RemotePickerTokenPhase(model: model, host: host, port: port)
            case .folders(let context):
                RemotePickerFoldersPhase(model: model, context: context, onComplete: { selectedFolders in
                    applySelection(context: context, folders: selectedFolders)
                })
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 540)
        .background(Color.appBackground)
        .onAppear {
            // Refresh the Recent list every time the window appears so a
            // newly-connected host shows immediately (without restarting
            // the app).
            model.refreshRecents()
        }
    }

    /// Resolves the picker's final selection into open tabs and closes the
    /// window. Each selected folder becomes its own tab via the existing
    /// `openRemoteTab` path; the bearer token is identical across tabs for
    /// a single host. We surface the main window too so the new tabs land
    /// somewhere visible.
    private func applySelection(context: RemoteFolderPickerModel.FoldersContext, folders: [FolderInfo]) {
        guard let tabs = AppCommandsController.shared.tabs else {
            logger.error("connect-folders: no tabs model available; closing")
            dismissWindow(id: "remotePicker")
            return
        }
        for folder in folders {
            tabs.openRemoteTab(
                host: context.host,
                port: context.port,
                token: context.token,
                folderId: folder.id,
                displayName: folder.name
            )
        }
        // Record the host in the Recent list with whatever display name
        // we learned via /v1/host so the next pick shows it labeled.
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: context.host,
            port: context.port,
            displayName: context.hostInfo?.displayName,
            lastUsedAt: Date()
        ))
        openWindow(id: "main")
        dismissWindow(id: "remotePicker")
    }
}

// MARK: - Picker model

/// View-model for the remote picker. `@Observable` + `@MainActor` so the
/// view layer can bind directly and async work in `validateHost` /
/// `validateToken` / `fetchFolders` stays on main.
@Observable
@MainActor
final class RemoteFolderPickerModel {

    /// Form-validated host text. Trimmed on advance.
    var hostText: String = ""
    /// Port text (raw, validated to a 1–65535 integer on advance).
    var portText: String = "51823"
    /// Paste-step token text. Trimmed on advance.
    var tokenText: String = ""
    /// Inline error shown under whichever field the current phase owns.
    /// Cleared whenever the user edits an input.
    var inlineError: String?
    /// `true` while an async request is in flight. Hides the Continue
    /// button's enabled state and shows a small progress indicator.
    var isBusy: Bool = false

    /// Currently-remembered hosts. Refreshed on `onAppear` and after a
    /// successful connect.
    var recents: [RemoteHostIdentity] = []

    /// Discovered hosts placeholder. Stays empty in this iteration —
    /// #0089 will populate it via Bonjour once the multicast entitlement
    /// (#0093) is approved.
    var discovered: [RemoteHostIdentity] = []

    var phase: Phase = .host

    /// Override-injectable client so tests can stub network behavior. The
    /// `URLSessionRemoteHostProbe` default suits production.
    var client: RemoteHostProbe = URLSessionRemoteHostProbe()

    init() {
        refreshRecents()
    }

    enum Phase {
        /// Initial step — pick a host or enter one manually.
        case host
        /// Token paste step. Carries the validated `(host, port)` pair so
        /// the title bar can show what we're connecting to.
        case token(host: String, port: UInt16)
        /// Folder list step. Carries everything the folder rows need to
        /// know in one bundle.
        case folders(FoldersContext)
    }

    /// State carried into the folder-list phase. The token is included so
    /// `Confirm` can spin up an `IssueStore` per chosen folder without
    /// reading the Keychain a second time.
    struct FoldersContext {
        let host: String
        let port: UInt16
        let token: String
        let hostInfo: HostInfo?
        let folders: [FolderInfo]
    }

    // MARK: - Validation

    /// Port parser. Empty / non-numeric / out-of-range all return `nil`;
    /// the picker treats `nil` as "Continue disabled".
    nonisolated static func parsePort(_ text: String) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed) else { return nil }
        guard value >= 1 && value <= 65535 else { return nil }
        return UInt16(value)
    }

    /// Returns `true` when both fields parse to something usable. Used by
    /// the Continue button's `disabled` modifier.
    nonisolated static func hostFieldsValid(hostText: String, portText: String) -> Bool {
        let host = hostText.trimmingCharacters(in: .whitespaces)
        if host.isEmpty { return false }
        return parsePort(portText) != nil
    }

    /// Token field passes the cheap shape check from #0096: starts with
    /// `iat_` and is long enough to look like a real token. Validation
    /// against the host happens in `validateToken`. Combined v2 form
    /// (#0113) is `iat_<43>.<64-hex>` — both halves separated by `.`.
    nonisolated static func tokenFieldValid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("iat_") && trimmed.count >= 5
    }

    // MARK: - Recents

    func refreshRecents() {
        recents = RemoteHostRecents.list()
    }

    func forget(_ identity: RemoteHostIdentity) {
        RemoteHostRecents.forget(id: identity.id)
        refreshRecents()
    }

    /// Resets the picker back to phase A. Used by the "Cancel" button on
    /// later phases and the "Back" affordance.
    func resetToHostPhase() {
        phase = .host
        inlineError = nil
        tokenText = ""
        isBusy = false
    }

    // MARK: - Async actions

    /// Phase A → Phase B. Probes `GET /v1/host` (no token) with a 3 s
    /// timeout. The picker treats:
    ///   - `unauthorized` as success → advance to the token phase.
    ///   - other failures as inline errors → stay on the host phase.
    /// Caller is expected to ensure `hostFieldsValid` first.
    func validateHost() async {
        let host = hostText.trimmingCharacters(in: .whitespaces)
        guard let port = Self.parsePort(portText) else {
            inlineError = "Enter a port between 1 and 65535."
            return
        }
        inlineError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            // A bearer-less probe should never 200 against the production
            // host (auth is required); 200 here means we somehow have an
            // anonymous host. Advance to the folder phase in that case by
            // running the unauthenticated path — but the host requires a
            // token for /v1/folders, so token phase is still the right
            // next step.
            let info = try await client.fetchHost(host: host, port: port, token: nil)
            // 200 with no token is unusual; we still need a token for
            // /v1/folders. Advance to token phase, but pass the display
            // name we learned forward for the title.
            recordHostUsage(host: host, port: port, displayName: info.displayName)
            phase = .token(host: host, port: port)
        } catch RemoteHostProbeError.unauthorized {
            // Reachable, awaiting token — exactly the path #0091 documents.
            recordHostUsage(host: host, port: port, displayName: nil)
            phase = .token(host: host, port: port)
        } catch RemoteHostProbeError.transport(let detail) {
            inlineError = "Couldn't reach this host. (\(detail))"
        } catch RemoteHostProbeError.httpStatus(let code) {
            inlineError = "Host returned status \(code)."
        } catch RemoteHostProbeError.invalidURL {
            inlineError = "That host:port is not a valid address."
        } catch RemoteHostProbeError.decoding(let detail) {
            inlineError = "Couldn't read the host response. (\(detail))"
        } catch {
            inlineError = error.localizedDescription
        }
    }

    /// Phase A→A bypass from a Recent row. Reuses the cached
    /// `(host, port)` and (when possible) a previously-stored bearer
    /// token: if the token is valid we jump straight to the folder
    /// phase, otherwise we drop into the token phase with an explanation.
    func connectToRecent(_ identity: RemoteHostIdentity) async {
        inlineError = nil
        isBusy = true
        defer { isBusy = false }
        let hostId = identity.id
        let cachedToken: String?
        do {
            cachedToken = try ViewerTokenStore.token(forHost: hostId)
        } catch {
            cachedToken = nil
            logger.warning("recent: token lookup failed for \(hostId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        hostText = identity.host
        portText = String(identity.port)
        if let token = cachedToken, !token.isEmpty {
            // Try the folder fetch directly; if 401, drop into token paste
            // with a note. Otherwise advance to folder phase.
            do {
                let info = try? await client.fetchHost(host: identity.host, port: identity.port, token: token)
                let folders = try await client.fetchFolders(host: identity.host, port: identity.port, token: token)
                recordHostUsage(host: identity.host, port: identity.port, displayName: info?.displayName ?? identity.displayName)
                phase = .folders(FoldersContext(
                    host: identity.host,
                    port: identity.port,
                    token: token,
                    hostInfo: info,
                    folders: folders
                ))
                return
            } catch RemoteHostProbeError.unauthorized {
                // Stored token no longer accepted — bounce to token paste.
                inlineError = "The saved token for this host was rejected. Paste a new one."
                phase = .token(host: identity.host, port: identity.port)
                return
            } catch {
                inlineError = "Couldn't connect: \(error.localizedDescription)"
                return
            }
        }
        // No saved token — go through the normal validate-host path.
        await validateHost()
    }

    /// Phase B → Phase C. Validates the pasted token by calling
    /// `GET /v1/host` with it, then immediately listing folders. Stores
    /// the token in the Keychain on success.
    func validateTokenAndListFolders(host: String, port: UInt16) async {
        let raw = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            inlineError = "Paste a token from the host."
            return
        }
        // Parse the combined `iat_<43>.<64-hex>` form (#0113). Bare
        // pre-#0113 tokens land in `.malformed` and the user gets a
        // clear regen prompt.
        let parsed: (plaintext: String, fingerprint: String)
        do {
            parsed = try AccessToken.parseCombined(raw)
        } catch {
            if raw.hasPrefix("iat_") && !raw.contains(".") {
                inlineError = "This token is from an older host. Ask the host to regenerate it after upgrading."
            } else {
                inlineError = "This doesn't look like a token."
            }
            return
        }
        let token = parsed.plaintext
        let fingerprint = parsed.fingerprint
        inlineError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let info = try await client.fetchHost(host: host, port: port, token: token)
            let folders = try await client.fetchFolders(host: host, port: port, token: token)
            let hostId = "\(host):\(port)"
            do {
                try ViewerTokenStore.store(token: token, fingerprint: fingerprint, forHost: hostId)
            } catch {
                logger.error("token store failed: \(error.localizedDescription, privacy: .public)")
                // Non-fatal — keep going with the in-memory token. The user
                // will be re-prompted on relaunch.
            }
            recordHostUsage(host: host, port: port, displayName: info.displayName)
            phase = .folders(FoldersContext(
                host: host,
                port: port,
                token: token,
                hostInfo: info,
                folders: folders
            ))
        } catch RemoteHostProbeError.unauthorized {
            inlineError = "Token rejected."
        } catch RemoteHostProbeError.transport(let detail) {
            inlineError = "Couldn't reach the host. (\(detail))"
        } catch RemoteHostProbeError.httpStatus(let code) {
            inlineError = "Host returned status \(code)."
        } catch RemoteHostProbeError.decoding(let detail) {
            inlineError = "Couldn't read the host response. (\(detail))"
        } catch RemoteHostProbeError.invalidURL {
            inlineError = "That host:port is not a valid address."
        } catch {
            inlineError = error.localizedDescription
        }
    }

    /// Records a host in the Recent list with the latest display name
    /// (when we learned one) and the current time as `lastUsedAt`.
    private func recordHostUsage(host: String, port: UInt16, displayName: String?) {
        RemoteHostRecents.upsert(RemoteHostIdentity(
            host: host,
            port: port,
            displayName: displayName,
            lastUsedAt: Date()
        ))
        refreshRecents()
    }
}

// MARK: - Phase A: pick host

private struct RemotePickerHostPhase: View {
    @Bindable var model: RemoteFolderPickerModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to remote host")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appText)
                .padding(.top, 16)

            // Discovered hosts placeholder. The empty state is the only
            // path today; the section is left in place so #0089 can plug
            // in once the multicast entitlement (#0093) is approved.
            section(title: "Discovered hosts") {
                if model.discovered.isEmpty {
                    Text("No hosts discovered")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.discovered) { identity in
                        RecentHostRow(identity: identity) {
                            Task { await model.connectToRecent(identity) }
                        }
                    }
                }
            }

            section(title: "Recent") {
                if model.recents.isEmpty {
                    Text("No previous hosts")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appMuted)
                        .padding(.vertical, 6)
                } else {
                    ForEach(model.recents) { identity in
                        RecentHostRow(identity: identity) {
                            Task { await model.connectToRecent(identity) }
                        }
                        .contextMenu {
                            Button("Forget this host") {
                                model.forget(identity)
                            }
                        }
                    }
                }
            }

            section(title: "Or enter manually") {
                manualEntryFields
            }

            if let error = model.inlineError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.statusWontfix)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismissWindow(id: "remotePicker")
                }
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    Task { await model.validateHost() }
                }) {
                    if model.isBusy {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Connecting\u{2026}")
                        }
                    } else {
                        Text("Continue")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || !RemoteFolderPickerModel.hostFieldsValid(
                    hostText: model.hostText, portText: model.portText
                ))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var manualEntryFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Host:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .frame(width: 48, alignment: .leading)
                TextField("100.74.12.5 or mac-mini.tail-scale.ts.net", text: $model.hostText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: model.hostText) { _, _ in model.inlineError = nil }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Port:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appText)
                    .frame(width: 48, alignment: .leading)
                TextField("51823", text: $model.portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .onChange(of: model.portText) { _, _ in model.inlineError = nil }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.appMuted)
            content()
        }
    }
}

private struct RecentHostRow: View {
    let identity: RemoteHostIdentity
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(identity.displayName ?? identity.host)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appText)
                    Text("\(identity.host):\(identity.port)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appMuted)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phase B: token paste

private struct RemotePickerTokenPhase: View {
    @Bindable var model: RemoteFolderPickerModel
    let host: String
    let port: UInt16
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to \(host):\(port)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appText)
                .padding(.top, 16)

            Text("Paste an access token from the host:")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)

            // The spec frames this as a single-line field; the task brief
            // calls for multi-line. Use `TextEditor` so very long tokens
            // wrap, with a fixed-height frame for layout stability.
            TextEditor(text: $model.tokenText)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
                .onChange(of: model.tokenText) { _, _ in model.inlineError = nil }

            Text("Generate one in Issues.app on the host: Settings \u{2192} Remote Access \u{2192} Access tokens.")
                .font(.system(size: 11))
                .foregroundStyle(Color.appMuted)

            if let error = model.inlineError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.statusWontfix)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Back") {
                    model.resetToHostPhase()
                }
                Spacer()
                Button("Cancel") {
                    dismissWindow(id: "remotePicker")
                }
                .keyboardShortcut(.cancelAction)
                Button(action: {
                    Task { await model.validateTokenAndListFolders(host: host, port: port) }
                }) {
                    if model.isBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Validating\u{2026}")
                        }
                    } else {
                        Text("Continue")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || !RemoteFolderPickerModel.tokenFieldValid(model.tokenText))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }
}

// MARK: - Phase C: pick folders

private struct RemotePickerFoldersPhase: View {
    @Bindable var model: RemoteFolderPickerModel
    let context: RemoteFolderPickerModel.FoldersContext
    let onComplete: ([FolderInfo]) -> Void

    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headerTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.appText)
                .padding(.top, 16)

            HStack(spacing: 8) {
                Button("Select all") { selectedIds = Set(context.folders.map { $0.id }) }
                    .disabled(context.folders.isEmpty)
                Button("Select none") { selectedIds.removeAll() }
                    .disabled(selectedIds.isEmpty)
                Spacer()
            }

            if context.folders.isEmpty {
                Text("This host isn't sharing any folders.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(context.folders, id: \.id) { folder in
                            RemoteFolderRow(
                                folder: folder,
                                isSelected: selectedIds.contains(folder.id),
                                onToggle: {
                                    if selectedIds.contains(folder.id) {
                                        selectedIds.remove(folder.id)
                                    } else {
                                        selectedIds.insert(folder.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
            }

            if let error = model.inlineError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.statusWontfix)
            }

            HStack {
                Button("Back") {
                    model.resetToHostPhase()
                }
                Spacer()
                Button("Cancel") { dismissWindow(id: "remotePicker") }
                    .keyboardShortcut(.cancelAction)
                Button(action: {
                    let selected = context.folders.filter { selectedIds.contains($0.id) }
                    onComplete(selected)
                }) {
                    Text(confirmTitle)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedIds.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    private var headerTitle: String {
        if let name = context.hostInfo?.displayName, !name.isEmpty {
            return "Folders on \(name)"
        }
        return "Folders on \(context.host)"
    }

    private var confirmTitle: String {
        switch selectedIds.count {
        case 0: return "Connect"
        case 1: return "Connect to 1 folder"
        default: return "Connect to \(selectedIds.count) folders"
        }
    }
}

private struct RemoteFolderRow: View {
    let folder: FolderInfo
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.appAccent : Color.appMuted)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appText)
                    if let description = folder.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.appMuted)
                            .lineLimit(2)
                    } else {
                        Text(folder.parentPath)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let repo = folder.url {
                        // Repo link: single click opens in default browser.
                        // We don't surface a popover menu — per #0097's note
                        // referencing the RemoteAccess Open Question.
                        Button(action: { NSWorkspace.shared.open(repo) }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.forward.square")
                                Text(repo.host ?? repo.absoluteString)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.appBackgroundCard)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Host phase") {
    RemoteFolderPickerView()
        .frame(width: 560, height: 540)
}
#endif

#endif // os(macOS)
