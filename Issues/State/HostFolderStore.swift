import Foundation
import Observation

#if os(macOS)

/// Concrete `MultiFolderStore` for the host (#0085). Owns a snapshot of the
/// user's open `IssueStore`s plus an `isShared: Bool` flag per `folderId`
/// (#0082). The remote server reads through this so flipping a folder off
/// removes it from `/v1/folders` immediately, and a relaunch restores the
/// previously-saved per-folder values.
///
/// The store does not own the `IssueStore` lifecycle; `TabsModel` does.
/// `setStores(_:)` reflects the latest open tabs, and a TabsModel-level
/// hook calls it whenever tabs are added, removed, or reordered.
@Observable
@MainActor
final class HostFolderStore: MultiFolderStore {

    /// Per-folder `UserDefaults` key prefix. The full key is
    /// `RemoteServer.sharedFolders.<folderId>` and the value is `Bool`.
    private static let defaultsKeyPrefix = "RemoteServer.sharedFolders."

    /// Snapshot of the open IssueStores in tab order. Set by TabsModel.
    private(set) var stores: [IssueStore] = []

    /// In-memory mirror of the persisted `isShared` flags. Loaded lazily on
    /// first access and written-through on every `setShared`.
    private var shareFlags: [String: Bool] = [:]

    /// When global hosting is off (#0083), `currentlyHostedFolders()`
    /// returns an empty list regardless of per-folder toggles. The toggles
    /// themselves stay set so flipping the global switch back on restores
    /// the user's prior selection.
    var isGlobalHostingEnabled: Bool = false

    /// User-chosen display name override (#0083). When set, takes precedence
    /// over `Host.current().localizedName` so the value the user typed in
    /// settings is what `/v1/host` returns.
    var displayNameOverride: String?

    /// Default for newly-encountered folder ids when global hosting is
    /// enabled. `false` keeps a freshly-opened folder unpublished until the
    /// user confirms in settings (matches the issue spec's "fresh folder
    /// doesn't surprise-publish" rule, even when hosting is already on).
    var defaultIsSharedForNewFolders: Bool = false

    init() {}

    // MARK: - MultiFolderStore

    var hostDisplayName: String {
        if let override = displayNameOverride, !override.isEmpty { return override }
        let host = Host.current()
        if let localized = host.localizedName, !localized.isEmpty {
            return localized
        }
        let name = ProcessInfo.processInfo.hostName
        return name.isEmpty ? "Mac" : name
    }

    func currentlyHostedFolders() -> [HostedFolder] {
        guard isGlobalHostingEnabled else { return [] }
        return stores.compactMap { hostedFolder(from: $0, applyingShareFilter: true) }
    }

    func currentlyHostedFolder(forId id: String) -> HostedFolder? {
        guard isGlobalHostingEnabled else { return nil }
        guard let store = stores.first(where: { $0.folderId == id }) else { return nil }
        return hostedFolder(from: store, applyingShareFilter: true)
    }

    // MARK: - Tab integration

    /// Replace the snapshot of open stores. Called by `TabsModel` whenever
    /// the tab list changes. Stores without a `folderId` (e.g. previews
    /// missing a bookmark) are silently dropped from the hosted list.
    func setStores(_ stores: [IssueStore]) {
        self.stores = stores
    }

    // MARK: - Per-folder share toggle

    /// `true` when the folder is currently shared (and hosting is enabled).
    /// Reads through to UserDefaults on first access for each id.
    func isShared(folderId: String) -> Bool {
        if let cached = shareFlags[folderId] { return cached }
        let key = Self.defaultsKeyPrefix + folderId
        if let raw = UserDefaults.standard.object(forKey: key) as? Bool {
            shareFlags[folderId] = raw
            return raw
        }
        // First time we've seen this folder — apply the default.
        shareFlags[folderId] = defaultIsSharedForNewFolders
        return defaultIsSharedForNewFolders
    }

    /// Toggle the share flag and persist immediately. Caller is responsible
    /// for any WebSocket fanout (#0101) that the unshare event implies; this
    /// type just owns the boolean.
    func setShared(folderId: String, _ isShared: Bool) {
        shareFlags[folderId] = isShared
        UserDefaults.standard.set(isShared, forKey: Self.defaultsKeyPrefix + folderId)
    }

    /// "Share all" / "Share none" — convenience for the settings UI.
    func setSharedForAll(_ isShared: Bool) {
        for store in stores {
            guard let id = store.folderId else { continue }
            setShared(folderId: id, isShared)
        }
    }

    // MARK: - Helpers

    private func hostedFolder(from store: IssueStore, applyingShareFilter: Bool) -> HostedFolder? {
        guard let id = store.folderId else { return nil }
        if applyingShareFilter, !isShared(folderId: id) { return nil }
        let modifiedAt = store.issues.map(\.modifiedAt).max() ?? Date(timeIntervalSince1970: 0)
        return HostedFolder(
            id: id,
            folderURL: store.folderURL,
            displayName: store.displayName,
            projectMetadata: store.projectMetadata,
            issues: store.issues,
            modifiedAt: modifiedAt
        )
    }
}

#endif
