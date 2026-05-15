import Foundation
import os.log

#if os(macOS) || os(iOS)

nonisolated private let attachmentLogger = Logger(subsystem: Logging.subsystem, category: "AttachmentLoader")

/// Async attachment byte loader (#0106). Local-source attachments are read
/// off disk; remote-source attachments stream over HTTP via the source's
/// `RemoteHostIssueSource.fetchAttachmentData(...)` indirection. Either
/// way the caller gets a `Data` (or `NSImage`) without blocking the main
/// thread.
///
/// Two correctness properties:
///   - **Cache** — keep raw bytes in memory keyed by
///     `CacheKey(folderId, issueId, name)`. Repeated loads short-circuit.
///   - **In-flight dedup** — concurrent loads of the same key collapse to
///     one underlying fetch; every awaiter sees the same result. Prevents
///     a fast scroll past a remote image from spamming N parallel
///     downloads.
///
/// The cache is in-memory only. The viewer is read-only and disk-cache-free
/// per `RemoteAccess.md`'s non-goals.
public actor AttachmentLoader {

    public struct CacheKey: Hashable, Sendable {
        let folderId: String
        let issueId: String
        let name: String
    }

    public static let shared = AttachmentLoader()

    public init() {}

    private var cache: [CacheKey: Data] = [:]
    private var inFlight: [CacheKey: Task<Data, Error>] = [:]

    /// Maximum number of bytes the cache will hold before evicting. Default
    /// 32 MB — comfortably above the realistic 4.5 MB MOV from #0072 and a
    /// half dozen PNGs.
    private let cacheBudget: Int = 32 * 1024 * 1024
    private var cacheBytes: Int = 0
    private var lru: [CacheKey] = []

    /// Loads bytes for `(folderId, issueId, name)` from the given source.
    /// Cache hit returns immediately; cache miss dispatches to disk (local)
    /// or to the wire (remote) via `loadRaw(...)`.
    public func load(folderId: String, issueId: String, name: String, from source: any IssueSource) async throws -> Data {
        let key = CacheKey(folderId: folderId, issueId: issueId, name: name)
        if let cached = cache[key] {
            touch(key)
            return cached
        }
        if let pending = inFlight[key] {
            return try await pending.value
        }
        let task = Task<Data, Error> {
            try await self.loadRaw(folderId: folderId, issueId: issueId, name: name, from: source)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let data = try await task.value
        store(key, data: data)
        return data
    }

    /// Pre-warm path used by Quick Look (#0073-style integration) — runs
    /// the same load + cache without throwing on the caller side.
    public func preload(folderId: String, issueId: String, name: String, from source: any IssueSource) async {
        _ = try? await load(folderId: folderId, issueId: issueId, name: name, from: source)
    }

    /// Drops a single entry. Used after the host signals an update for an
    /// issue — its attachments may have changed.
    public func invalidate(folderId: String, issueId: String) {
        let toDrop = cache.keys.filter { $0.folderId == folderId && $0.issueId == issueId }
        for key in toDrop {
            if let data = cache.removeValue(forKey: key) {
                cacheBytes -= data.count
            }
            lru.removeAll { $0 == key }
        }
    }

    /// Wipes everything. Intended for memory-pressure responses.
    public func reset() {
        cache.removeAll()
        lru.removeAll()
        cacheBytes = 0
    }

    // MARK: - Internals

    private func loadRaw(folderId: String, issueId: String, name: String, from source: any IssueSource) async throws -> Data {
        if let remote = source as? RemoteHostIssueSource {
            return try await remote.fetchAttachmentData(issueId: issueId, name: name)
        }
        // Local source: read off the actor's executor so the actor's
        // mailbox isn't blocked on disk I/O.
        let url = source.folderURL
            .appendingPathComponent(issueId, isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
        return try await Self.readData(at: url)
    }

    @concurrent
    nonisolated private static func readData(at url: URL) async throws -> Data {
        try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func store(_ key: CacheKey, data: Data) {
        if let prior = cache[key] {
            cacheBytes -= prior.count
            lru.removeAll { $0 == key }
        }
        cache[key] = data
        cacheBytes += data.count
        lru.append(key)
        evictIfNeeded()
    }

    private func touch(_ key: CacheKey) {
        lru.removeAll { $0 == key }
        lru.append(key)
    }

    private func evictIfNeeded() {
        while cacheBytes > cacheBudget, let oldest = lru.first {
            lru.removeFirst()
            if let data = cache.removeValue(forKey: oldest) {
                cacheBytes -= data.count
            }
        }
    }
}

#endif
