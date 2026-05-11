import Foundation

/// Persistence key for a remote host the user has connected to before.
/// Backs the "Recent" section in `RemoteFolderPickerView` (#0091): the
/// user shouldn't have to retype `host:port` on every reconnect.
///
/// `id` is the stable `host:port` string. Two entries with the same `id`
/// collapse on `upsert` — `displayName` and `lastUsedAt` get refreshed
/// with the newest values.
struct RemoteHostIdentity: Codable, Hashable, Identifiable {
    var id: String { "\(host):\(port)" }
    let host: String
    let port: UInt16
    /// Populated by the picker after a successful `GET /v1/host`. nil for
    /// entries that have never produced a 200 (e.g. the user typed a host,
    /// got 401, advanced to the token paste step, then cancelled).
    var displayName: String?
    var lastUsedAt: Date
}

/// UserDefaults-backed list of remembered hosts. Stored as a JSON array
/// under `RemoteHost.recents`. Read fresh on every call — the list is
/// small (single-digit entries) and the picker only touches it on open
/// / connect / context-menu-forget, so polling is fine.
enum RemoteHostRecents {

    static let defaultsKey = "RemoteHost.recents"

    /// All remembered hosts, sorted by `lastUsedAt` descending (most
    /// recent first). Decode failures (e.g. corrupted blob from a prior
    /// app version) return an empty list — the picker should still work.
    static func list(defaults: UserDefaults = .standard) -> [RemoteHostIdentity] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        guard let decoded = try? JSONDecoder().decode([RemoteHostIdentity].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    /// Add or update an entry. Dedupe key is `id` (i.e. `host:port`); the
    /// existing entry's `displayName` is replaced only when the new value
    /// is non-nil, so a probe that gets 401 doesn't blow away the name we
    /// learned on a previous successful connect.
    @discardableResult
    static func upsert(_ identity: RemoteHostIdentity, defaults: UserDefaults = .standard) -> [RemoteHostIdentity] {
        var current = list(defaults: defaults)
        if let idx = current.firstIndex(where: { $0.id == identity.id }) {
            var merged = current[idx]
            if let name = identity.displayName, !name.isEmpty {
                merged.displayName = name
            }
            merged = RemoteHostIdentity(
                host: identity.host,
                port: identity.port,
                displayName: merged.displayName,
                lastUsedAt: identity.lastUsedAt
            )
            current[idx] = merged
        } else {
            current.append(identity)
        }
        write(current, defaults: defaults)
        return current.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    /// Remove the entry with the given `id`. No-op if absent.
    @discardableResult
    static func forget(id: String, defaults: UserDefaults = .standard) -> [RemoteHostIdentity] {
        var current = list(defaults: defaults)
        current.removeAll { $0.id == id }
        write(current, defaults: defaults)
        return current
    }

    /// Wipe the whole list. Intended for test teardown.
    static func deleteAll(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    private static func write(_ items: [RemoteHostIdentity], defaults: UserDefaults) {
        if items.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
