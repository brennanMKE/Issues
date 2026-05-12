import Foundation
import Observation
import CryptoKit
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
    private static let allowedNetworksKey = "RemoteServer.allowedNetworks"

    // MARK: - State (observed by SwiftUI)

    /// `true` when the listener is running and accepting connections. This
    /// reflects the *running* state — the user's *intent* lives in
    /// `isUserEnabled`. The two diverge while we're paused on a network
    /// change (#0105).
    private(set) var isEnabled: Bool = false

    /// The user's last on/off intent (persisted). Stays true while the
    /// host is paused on a network change so re-enabling preserves the
    /// previous choice without the user having to remember it.
    private(set) var isUserEnabled: Bool = false

    /// `true` when the user wants hosting on but the current network isn't
    /// allowlisted, so the listener is stopped pending a one-click
    /// re-enable (#0105).
    var isPaused: Bool {
        isUserEnabled && !isEnabled
    }

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
    /// TLS identity backing `RemoteServer`'s listener. Loaded from Keychain
    /// on first launch after #0112, generated if absent. Surfaced for the
    /// host settings UI via `currentFingerprint` (#0113 / #0115 bind).
    private let identity: RemoteServerIdentity?
    /// Lowercase 64-char SHA-256 hex of the host's TLS leaf cert, or empty
    /// if identity setup failed (the latter is non-fatal here — the user
    /// sees the surfaced `lastStartError` when they try to enable hosting).
    var currentFingerprint: String {
        identity?.fingerprintHex ?? ""
    }

    /// Mints a new bearer token bound to the current host cert
    /// fingerprint (#0113). The settings sheet (#0084) calls this so
    /// the generated token is automatically paired with the identity
    /// the listener is serving. Throws if no identity is loaded
    /// (shouldn't happen post-#0112 unless the keychain failed at init).
    func generateToken(name: String, expiresAt: Date?) throws -> AccessToken.Generated {
        guard let identity else { throw RemoteHostControllerError.noIdentity }
        return try AccessToken.generate(name: name, expiresAt: expiresAt, identity: identity)
    }

    enum RemoteHostControllerError: Error, Equatable {
        case noIdentity
    }

    private var pathMonitor: NWPathMonitor?
    /// Hash of the most recently observed network path (#0105). nil until
    /// the first NWPathMonitor update lands.
    private var currentNetworkHash: String?
    /// Allowlisted network hashes (persisted). Joining a hash here exempts
    /// it from the pause-on-network-change behavior; joining a new hash
    /// the first time the user toggles on adds the current network.
    private var allowedNetworks: Set<String> = []

    init(folderStore: HostFolderStore? = nil) {
        let store = folderStore ?? HostFolderStore()
        self.folderStore = store
        // Load or generate the TLS identity (#0112). Failure to mint here
        // is logged but doesn't crash — the user-visible failure path is
        // `setEnabled(true)`, which surfaces `lastStartError`.
        let loaded: RemoteServerIdentity?
        do {
            if let existing = try RemoteServerIdentity.load() {
                loaded = existing
            } else {
                loaded = try RemoteServerIdentity.generate()
            }
        } catch {
            logger.error("identity load/generate failed: \(error.localizedDescription, privacy: .public)")
            loaded = nil
        }
        self.identity = loaded
        self.server = RemoteServer(store: store, identity: loaded)

        // Load persisted display name; fall back to system computer name.
        let persisted = UserDefaults.standard.string(forKey: Self.displayNameKey)
        self.displayName = (persisted?.isEmpty == false ? persisted! : store.hostDisplayName)
        store.displayNameOverride = persisted?.isEmpty == false ? persisted : nil
        self.interfaces = NetworkInterfaceLister.current()
        self.allowedNetworks = Set(UserDefaults.standard.stringArray(forKey: Self.allowedNetworksKey) ?? [])

        // Restore the user's persisted intent.
        self.isUserEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)

        // Auto-start if the user left hosting on last session. The network
        // allowlist gate kicks in once `NWPathMonitor` produces its first
        // path update — for the brief window before that we honor the
        // user's intent unconditionally.
        if isUserEnabled {
            do {
                try start()
            } catch {
                logger.warning("auto-start failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        startPathMonitor()
    }

    // MARK: - Lifecycle

    /// Flip the user-facing toggle. Persists the user's intent. On a `true`
    /// transition starts the server and allowlists the current network so
    /// future joins to the same path don't pause. On a `false` transition
    /// stops the server and forgets the intent (but keeps the allowlist).
    func setEnabled(_ desired: Bool) {
        if desired == isUserEnabled && desired == isEnabled { return }
        if desired {
            isUserEnabled = true
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
            allowlistCurrentNetwork()
            do {
                try start()
            } catch {
                lastStartError = error.localizedDescription
                logger.error("start failed: \(error.localizedDescription, privacy: .public)")
                isEnabled = false
            }
        } else {
            isUserEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            stop()
        }
    }

    /// "Re-enable" action from the paused banner: allowlist the current
    /// network and start the server. Different from `setEnabled(true)`
    /// only in that it never toggles the intent (which was already true).
    func reEnableOnCurrentNetwork() {
        allowlistCurrentNetwork()
        do {
            try start()
        } catch {
            lastStartError = error.localizedDescription
            logger.error("re-enable failed: \(error.localizedDescription, privacy: .public)")
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

    /// Pause behavior: stop the listener but keep `isUserEnabled` so the
    /// banner appears and "re-enable" can land in one click. Called when
    /// `NWPathMonitor` reports a new network that isn't in the allowlist.
    private func pauseForNetworkChange() {
        guard isEnabled else { return }
        server.stop()
        folderStore.isGlobalHostingEnabled = false
        isEnabled = false
        listeningPort = nil
        logger.notice("RemoteHostController paused on network change")
    }

    // MARK: - Tab integration

    /// Tracks which stores we've attached the broadcast hook to so we can
    /// detach cleanly when a tab closes. Keyed by `IssueStore.id`.
    private var hookedStores: Set<UUID> = []

    /// Forward the current tab list into the underlying `HostFolderStore`
    /// so `/v1/folders` reflects what the user actually has open. Called
    /// by `RootView` from `.onChange(of: tabs.tabs.map(\.id))`.
    func setStores(_ stores: [IssueStore]) {
        folderStore.setStores(stores)
        // Attach the broadcast hook to any newly-tracked stores. We use a
        // dedicated `onReloadBroadcast` (separate from `onReload`) so we
        // don't fight TabsModel for the primary callback.
        let presentIDs = Set(stores.map(\.id))
        for store in stores where !hookedStores.contains(store.id) {
            store.onReloadBroadcast = { [weak self] store in
                MainActor.assumeIsolated {
                    self?.broadcastReload(from: store)
                }
            }
            hookedStores.insert(store.id)
        }
        // Drop tracking entries for stores that left the tab list. The
        // closures held by those stores are released when the store itself
        // is deallocated, so we don't need to nil them out here.
        hookedStores.formIntersection(presentIDs)
    }

    /// Broadcast a `reload` event for `store`'s folder. No-op if hosting
    /// is off or the folder isn't currently shared — viewers should never
    /// receive events for a folder they couldn't have subscribed to.
    private func broadcastReload(from store: IssueStore) {
        guard isEnabled, folderStore.isGlobalHostingEnabled else { return }
        guard let folderId = store.folderId else { return }
        guard folderStore.isShared(folderId: folderId) else { return }
        server.broadcast(.reload(folderId: folderId), toFolderId: folderId)
    }

    /// Persisted per-folder share flip with WS fanout (#0101). The view
    /// layer calls this instead of `folderStore.setShared` directly so
    /// the unshare-side `unsubscribed` event lands on every subscriber.
    func setFolderShared(folderId: String, _ isShared: Bool) {
        let was = folderStore.isShared(folderId: folderId)
        folderStore.setShared(folderId: folderId, isShared)
        if was && !isShared {
            server.unshareFolder(folderId: folderId, reason: "host_unshared")
        }
    }

    // MARK: - Network path monitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let hash = Self.hash(path: path)
            Task { @MainActor in
                self.refreshInterfaces()
                self.handlePath(hash: hash)
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

    private func handlePath(hash: String) {
        let previous = currentNetworkHash
        currentNetworkHash = hash
        // First path update of the session: if we auto-started, ensure
        // the network we just joined is on the allowlist so it stays
        // allowed across launches.
        if previous == nil {
            if isEnabled {
                allowlistCurrentNetwork()
            }
            return
        }
        guard previous != hash else { return }
        // Network changed. Pause if the user wants hosting but the new
        // network isn't allowlisted.
        if isUserEnabled, !allowedNetworks.contains(hash) {
            pauseForNetworkChange()
        }
    }

    private func allowlistCurrentNetwork() {
        guard let hash = currentNetworkHash else { return }
        guard !allowedNetworks.contains(hash) else { return }
        allowedNetworks.insert(hash)
        UserDefaults.standard.set(Array(allowedNetworks), forKey: Self.allowedNetworksKey)
        logger.debug("allowlisted network hash=\(hash, privacy: .public)")
    }

    /// Hash a `NWPath`'s identifying surface (gateway endpoints + interface
    /// types) so two visits to the same network produce the same string.
    /// We can't read SSIDs without `CoreLocation` permission, and the
    /// gateway-set hash is "good enough" for the pause-on-move behavior.
    nonisolated private static func hash(path: NWPath) -> String {
        let gateways = path.gateways.map { "\($0)" }.sorted().joined(separator: ",")
        let types = path.availableInterfaces.map { "\($0.type)" }.sorted().joined(separator: ",")
        let raw = "\(types)|\(gateways)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

#endif
