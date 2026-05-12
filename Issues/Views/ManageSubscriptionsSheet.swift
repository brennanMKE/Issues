import SwiftUI

#if os(macOS)

/// Manage Remote Subscriptions sheet (#0098). Lists every host the user
/// has open remote tabs for, plus any "Recent" hosts they've connected to
/// before. For each host the user can:
///
///   - Close an individual remote tab (per-row "Close" button).
///   - "Forget host" — closes every tab for that host, removes its bearer
///     from `ViewerTokenStore`, and removes its entry from
///     `RemoteHostRecents`.
///   - "Add folders…" — opens the regular picker; since the host is
///     already in `RemoteHostRecents` the user can pick it from the
///     "Recent" section and breeze to Phase C.
///
/// This is the streamlined v1 surface. A full per-host folder-checkbox
/// management view (spec's `RemoteSubscription` shape) is a future
/// enhancement once the picker can be re-entered against a known host.
/// Window-scene host that bridges from `AppCommandsController.shared.tabs`
/// (the singleton wiring point) into the actual sheet. The main window's
/// `RootView` owns the `TabsModel`; this lets the separate Manage
/// Subscriptions window scene see it without re-creating it.
struct ManageSubscriptionsSheetHost: View {
    @State private var commands = AppCommandsController.shared

    var body: some View {
        Group {
            if let tabs = commands.tabs {
                ManageSubscriptionsSheet(tabs: tabs)
            } else {
                Text("Open the main window to manage subscriptions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            }
        }
    }
}

struct ManageSubscriptionsSheet: View {

    @Bindable var tabs: TabsModel
    @Environment(\.dismiss) private var dismiss
    @State private var recents: [RemoteHostIdentity] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Remote Subscriptions")
                .font(.title3)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            if hostSections.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(hostSections, id: \.hostId) { section in
                        Section(header: header(for: section)) {
                            ForEach(section.tabs, id: \.id) { store in
                                row(for: store)
                            }
                            if section.tabs.isEmpty {
                                Text("No open folders.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 280)
            }

            Divider()

            HStack {
                Button("Add Host…") {
                    AppCommandsController.shared.openRemoteFolderPicker?()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 460, idealWidth: 540, minHeight: 360, idealHeight: 440)
        .onAppear { refresh() }
    }

    // MARK: - Row + section

    private struct HostSection {
        let hostId: String
        let displayName: String
        let host: String
        let port: UInt16
        let tabs: [IssueStore]
    }

    private var hostSections: [HostSection] {
        var byHost: [String: HostSection] = [:]
        // Hosts with currently-open tabs.
        for store in tabs.tabs {
            guard let endpoint = store.remoteEndpoint else { continue }
            let hostId = "\(endpoint.host):\(endpoint.port)"
            let existing = byHost[hostId]
            let prior = existing?.tabs ?? []
            byHost[hostId] = HostSection(
                hostId: hostId,
                displayName: existing?.displayName ?? store.displayName,
                host: endpoint.host,
                port: endpoint.port,
                tabs: prior + [store]
            )
        }
        // Hosts in Recents that don't currently have tabs.
        for recent in recents where byHost[recent.id] == nil {
            byHost[recent.id] = HostSection(
                hostId: recent.id,
                displayName: recent.displayName ?? recent.id,
                host: recent.host,
                port: recent.port,
                tabs: []
            )
        }
        return byHost.values.sorted { $0.displayName < $1.displayName }
    }

    @ViewBuilder
    private func header(for section: HostSection) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayName)
                    .font(.headline)
                Text(section.hostId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Forget host") {
                forgetHost(section)
            }
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func row(for store: IssueStore) -> some View {
        HStack {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayName)
                Text(store.folderId ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close tab") {
                tabs.closeTab(id: store.id)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No remote subscriptions yet.")
            Text("Use File → Connect to Remote Host… to add one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Actions

    private func forgetHost(_ section: HostSection) {
        // Close every open tab for this host.
        let toClose = tabs.tabs.filter { store in
            guard let endpoint = store.remoteEndpoint else { return false }
            return endpoint.host == section.host && endpoint.port == section.port
        }
        for store in toClose {
            tabs.closeTab(id: store.id)
        }
        // Remove the bearer from the Keychain.
        try? ViewerTokenStore.remove(forHost: section.hostId)
        // Drop the recents entry.
        RemoteHostRecents.forget(id: section.hostId)
        refresh()
    }

    private func refresh() {
        recents = RemoteHostRecents.list()
    }
}

#endif
