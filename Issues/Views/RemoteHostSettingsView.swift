import SwiftUI

#if os(macOS)
import AppKit

/// Host settings sheet (#0083): enable hosting toggle, reachable-at IP/port
/// list, display name. Token list (#0084), per-folder toggles (#0085), and
/// connected-viewers list (#0092) get their own sections in follow-up
/// issues; the layout below leaves the obvious slots open.
struct RemoteHostSettingsView: View {

    @Bindable var controller: RemoteHostController

    var body: some View {
        Form {
            if controller.isPaused {
                Section {
                    pausedBanner
                }
            }

            Section("Remote Access") {
                Toggle("Enable hosting", isOn: Binding(
                    get: { controller.isUserEnabled },
                    set: { controller.setEnabled($0) }
                ))
                if controller.isPaused {
                    Text("Paused — current network isn't allowlisted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if controller.isEnabled {
                    Text("Running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = controller.lastStartError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if controller.isEnabled {
                Section("Reachable on this Mac at") {
                    if let port = controller.listeningPort {
                        ForEach(controller.interfaces) { iface in
                            HStack {
                                Text("\(iface.address) : \(String(port))")
                                    .font(.system(.body, design: .monospaced))
                                Text(iface.name)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Spacer()
                                Button("Copy") {
                                    copyToPasteboard("\(iface.address):\(port)")
                                }
                                .controlSize(.small)
                            }
                        }
                        if controller.interfaces.isEmpty {
                            Text("No non-loopback interfaces detected.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Binding…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Display name (shown to viewers)") {
                TextField("Display name", text: $controller.displayName, prompt: Text(controller.folderStore.hostDisplayName))
                    .textFieldStyle(.roundedBorder)
            }

            ServerCertificateSection(controller: controller)

            Section("Access tokens") {
                AccessTokenListView()
            }

            if controller.isEnabled {
                Section("Connected viewers") {
                    ConnectedViewersListView(controller: controller)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 360, idealHeight: 440)
        .onAppear {
            controller.refreshInterfaces()
        }
    }

    private func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private var pausedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.orange)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hosting paused — your network changed")
                    .font(.callout.bold())
                Text("Joined a new network. Re-enable to publish issues here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-enable") {
                controller.reEnableOnCurrentNetwork()
            }
        }
    }
}

#endif
