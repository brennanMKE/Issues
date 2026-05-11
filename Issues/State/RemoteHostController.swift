import Foundation
import Observation
import os.log

#if os(macOS)
import Network

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "RemoteHostController")

/// App-level glue for #0083 host settings: owns the `RemoteServer` lifecycle,
/// the `HostFolderStore`, the user-facing display name, the persisted
/// enable-state, and the live list of non-loopback IPs. Lives on the main
/// actor so SwiftUI views can bind directly.
///
/// The TabsModel ↔ HostFolderStore wiring is one-way: views call
/// `setStores(_:)` whenever the tab list changes so `MultiFolderStore`'s
/// snapshot is current. The controller does not own the tabs themselves.
@Observable
@MainActor
final class RemoteHostController {

    // MARK: - UserDefaults keys

    private static let enabledKey = "RemoteServer.enabled"
    private static let displayNameKey = "RemoteServer.displayName"

    // MARK: - State (observed by SwiftUI)

    /// `true` when the listener is running. Read-only to views; flip via
    /// `setEnabled(_:)` so the side effects (start / stop / persist) stay
    /// inside the controller.
    private(set) var isEnabled: Bool = false

    /// Currently-bound port. Nil before `start()` completes or while
    /// `isEnabled` is false.
    private(set) var listeningPort: UInt16?

    /// Peers currently holding a connection to the server (#0092). Reads
    /// through to the server's observable list so SwiftUI views update
    /// as connections open / close.
    var connectedPeers: [PeerInfo] {
        server.connectedPeers
    }

    /// Available IPs, refreshed when the network path changes.
    private(set) var interfaces: [NetworkInterfaceLister.InterfaceAddress] = []

    /// Last error from `start()`, surfaced under the toggle. Cleared on the
    /// next successful start or when the toggle flips off.
    private(set) var lastStartError: String?

    /// User-editable host display name. Defaults to the system localized
    /// computer name; persisted in UserDefaults on every change.
    var displayName: String {
        didSet {
            UserDefaults.standard.set(displayName, forKey: Self.displayNameKey)
            folderStore.displayNameOverride = displayName.isEmpty ? nil : displayName
        }
    }

    let folderStore: HostFolderStore
    private let server: RemoteServer
    private var pathMonitor: NWPathMonitor?

    init(folderStore: HostFolderStore? = nil) {
        let store = folderStore ?? HostFolderStore()
        self.folderStore = store
        self.server = RemoteServer(store: store)

        // Load persisted display name; fall back to system computer name.
        let persisted = UserDefaults.standard.string(forKey: Self.displayNameKey)
        self.displayName = (persisted?.isEmpty == false ? persisted! : store.hostDisplayName)
        store.displayNameOverride = persisted?.isEmpty == false ? persisted : nil
        self.interfaces = NetworkInterfaceLister.current()

        // Auto-start if the user left hosting on last session.
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            do {
                try start()
            } catch {
                logger.warning("auto-start failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        startPathMonitor()
    }

    // MARK: - Lifecycle

    /// Flip the user-facing toggle. Persists the new state. On a `true`
    /// transition starts the server; on a `false` transition stops it.
    /// Errors during start surface via `lastStartError` and the controller
    /// flips back to `false` so the UI stays consistent.
    func setEnabled(_ desired: Bool) {
        if desired == isEnabled { return }
        if desired {
            do {
                try start()
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
            } catch {
                lastStartError = error.localizedDescription
                logger.error("start failed: \(error.localizedDescription, privacy: .public)")
                isEnabled = false
                UserDefaults.standard.set(false, forKey: Self.enabledKey)
            }
        } else {
            stop()
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
        }
    }

    private func start() throws {
        try server.start()
        folderStore.isGlobalHostingEnabled = true
        isEnabled = true
        lastStartError = nil
        // Listener may not be bound yet; ask once after a short delay so
        // the UI has a port to render. SwiftUI will re-read `listeningPort`
        // each frame anyway.
        listeningPort = server.listeningPort
        logger.notice("RemoteHostController started")
    }

    private func stop() {
        server.stop()
        folderStore.isGlobalHostingEnabled = false
        isEnabled = false
        listeningPort = nil
        lastStartError = nil
        logger.notice("RemoteHostController stopped")
    }

    // MARK: - Tab integration

    /// Forward the current tab list into the underlying `HostFolderStore`
    /// so `/v1/folders` reflects what the user actually has open. Called
    /// by `RootView` from `.onChange(of: tabs.tabs.map(\.id))`.
    func setStores(_ stores: [IssueStore]) {
        folderStore.setStores(stores)
    }

    // MARK: - Network path monitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshInterfaces()
            }
        }
        monitor.start(queue: .global(qos: .utility))
        self.pathMonitor = monitor
    }

    func refreshInterfaces() {
        interfaces = NetworkInterfaceLister.current()
        // Re-publish the bound port — the listener doesn't restart on a
        // path change, but the SwiftUI binding may have missed the first
        // emission if the view appeared before `start()` finished.
        if isEnabled {
            listeningPort = server.listeningPort
        }
    }
}

#endif
