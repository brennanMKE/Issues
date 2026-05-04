import AppKit
import Foundation
import Observation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "TabsModel")

/// Owns the ordered list of open `IssueStore` tabs and the active selection.
/// Each tab has its own watcher and security-scoped resource; background tabs
/// keep watching their folders so file edits stay live when switched back.
///
/// Persistence: the open tab list is serialized as an array of security-scoped
/// bookmark `Data` blobs in `UserDefaults` under `openTabs` (separate from
/// `FolderBookmarkService.rememberedFolders`). On launch each bookmark is
/// resolved and a fresh `IssueStore` is created; tabs whose bookmarks fail to
/// resolve are dropped silently (v1 — no error-state UI).
@Observable
@MainActor
final class TabsModel {

    private static let defaultsKey = "openTabs"

    private(set) var tabs: [IssueStore] = []
    var activeTabID: UUID? {
        didSet {
            guard oldValue != activeTabID, let id = activeTabID else { return }
            markActiveSeen(id: id)
        }
    }

    /// Snapshot of the issues each tab had the last time the user viewed it.
    /// `nil` means "no baseline yet" — the next reload establishes the baseline
    /// without flipping the indicator. Keyed by `IssueStore.id`.
    private var lastSeenSnapshot: [UUID: [String: IssueSnapshot]] = [:]

    /// Per-tab "has unseen changes" bit. Drives the dot indicator in the tab
    /// chip. Cleared when a tab becomes active.
    private(set) var hasUnseenChanges: [UUID: Bool] = [:]

    init() {
        restore()
    }

    // MARK: - Lookup

    var activeTab: IssueStore? {
        guard let id = activeTabID else { return tabs.first }
        return tabs.first { $0.id == id } ?? tabs.first
    }

    // MARK: - Mutations

    /// Creates a new store for `url`, starts it, appends to the tab list, and
    /// makes it active. If a tab for the same folder path already exists, just
    /// activates the existing tab.
    @discardableResult
    func openTab(url: URL) -> IssueStore {
        if let existing = tabs.first(where: { $0.folderURL.path == url.path }) {
            activeTabID = existing.id
            persist()
            return existing
        }
        let store = IssueStore(folderURL: url)
        attachReloadHook(to: store)
        store.start()
        // After the initial `start()` reload, take the resulting snapshot as
        // this tab's baseline so the indicator doesn't fire on the very first
        // populate. The user just opened it; they're caught up.
        lastSeenSnapshot[store.id] = store.snapshot
        hasUnseenChanges[store.id] = false
        tabs.append(store)
        activeTabID = store.id
        logger.notice("opened tab repo=\(store.repoName, privacy: .public) count=\(self.tabs.count, privacy: .public)")
        persist()
        return store
    }

    /// Removes the tab with `id`, stopping its watcher and releasing the
    /// security-scoped resource. If it was the active tab, falls back to the
    /// next remaining tab (or `nil` if none).
    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let store = tabs[idx]
        let wasActive = activeTabID == id
        store.onReload = nil
        store.stop()
        tabs.remove(at: idx)
        lastSeenSnapshot.removeValue(forKey: id)
        hasUnseenChanges.removeValue(forKey: id)
        logger.notice("closed tab repo=\(store.repoName, privacy: .public) remaining=\(self.tabs.count, privacy: .public)")
        if wasActive {
            // Prefer the tab that took the slot, otherwise the previous one,
            // otherwise nothing.
            if idx < tabs.count {
                activeTabID = tabs[idx].id
            } else if idx > 0, idx - 1 < tabs.count {
                activeTabID = tabs[idx - 1].id
            } else {
                activeTabID = nil
            }
        }
        persist()
    }

    func setActive(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
    }

    // MARK: - Unseen-change tracking

    /// Wires `IssueStore.onReload` so each post-reload tick funnels into
    /// `handleReload(_:)`. Called from `openTab` and `restore`.
    private func attachReloadHook(to store: IssueStore) {
        store.onReload = { [weak self] store in
            // `IssueStore` is `@MainActor`, so this fires on main and we can
            // touch `TabsModel` state directly.
            MainActor.assumeIsolated {
                self?.handleReload(store)
            }
        }
    }

    private func handleReload(_ store: IssueStore) {
        let id = store.id
        let newSnapshot = store.snapshot
        if activeTabID == id {
            // Active tab — user is looking at this; treat the new state as
            // seen and don't flag the indicator.
            lastSeenSnapshot[id] = newSnapshot
            hasUnseenChanges[id] = false
            return
        }
        guard let baseline = lastSeenSnapshot[id] else {
            // No baseline established yet (e.g. first reload after restore).
            // Take this snapshot as the baseline; don't flip the indicator
            // and don't fire notifications — there's nothing to diff against.
            lastSeenSnapshot[id] = newSnapshot
            return
        }
        if newSnapshot != baseline {
            hasUnseenChanges[id] = true
            // Only emit notifications when the app is in the background. The
            // dot indicator we just set above is enough when the user has
            // focus. We do the check inside `NotificationService.notifyChanges`
            // too; checking here avoids the diff work when it can't fire.
            if !NSApplication.shared.isActive {
                let (additions, removals, statusChanges) = diff(
                    baseline: baseline,
                    new: newSnapshot,
                    issues: store.issues
                )
                if !additions.isEmpty || !removals.isEmpty || !statusChanges.isEmpty {
                    NotificationService.shared.notifyChanges(
                        repoName: store.repoName,
                        tabID: id,
                        additions: additions,
                        removals: removals,
                        statusChanges: statusChanges
                    )
                }
            }
        }
    }

    /// Computes the addition / removal / status-change sets between `baseline`
    /// and `new`. Body-only edits (same id, same status, different mtime) are
    /// intentionally not surfaced — the dot indicator already tracks them and
    /// banner-spamming on every keystroke would be noise. Removed issues are
    /// reconstructed from the baseline-only snapshot data; we don't have the
    /// original `Issue` row anymore, so we synthesize a placeholder with the
    /// id we know about. Issues only appear in `additions` if we can find the
    /// matching row in `issues` (we always can — `new` is derived from it).
    private func diff(
        baseline: [String: IssueSnapshot],
        new: [String: IssueSnapshot],
        issues: [Issue]
    ) -> (additions: [Issue], removals: [Issue], statusChanges: [(issue: Issue, oldStatus: IssueStatus, newStatus: IssueStatus)]) {
        var additions: [Issue] = []
        var removals: [Issue] = []
        var statusChanges: [(issue: Issue, oldStatus: IssueStatus, newStatus: IssueStatus)] = []
        let issuesByID: [String: Issue] = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })

        for (id, snap) in new {
            if let prev = baseline[id] {
                if prev.status != snap.status, let issue = issuesByID[id] {
                    statusChanges.append((issue: issue, oldStatus: prev.status, newStatus: snap.status))
                }
            } else if let issue = issuesByID[id] {
                additions.append(issue)
            }
        }
        for (id, prev) in baseline where new[id] == nil {
            // The removed issue is gone from `issues`, so synthesize a minimal
            // placeholder carrying the id and last-known status. Title is left
            // blank because we never persisted it; the notification format
            // tolerates this — the repo line in the body still tells the user
            // which folder lost the issue.
            removals.append(Issue(
                id: id,
                title: "",
                status: prev.status,
                module: "",
                platform: "",
                firstSeen: nil,
                firstSeenRaw: "",
                closed: nil,
                closedRaw: "",
                description: "",
                fileURL: URL(fileURLWithPath: "/"),
                modifiedAt: prev.modifiedAt
            ))
        }
        return (additions, removals, statusChanges)
    }

    /// Marks `id`'s tab as "seen": stamps the current snapshot as the new
    /// baseline and clears the indicator. Called from the `activeTabID`
    /// `didSet`.
    private func markActiveSeen(id: UUID) {
        guard let store = tabs.first(where: { $0.id == id }) else { return }
        lastSeenSnapshot[id] = store.snapshot
        hasUnseenChanges[id] = false
    }

    func reorder(from source: Int, to destination: Int) {
        reorderWithoutPersisting(from: source, to: destination)
        persist()
    }

    /// Mutates `tabs` in place without writing to UserDefaults. Used by the
    /// Safari-style live-rearrange drag (#0021) where many reorder events
    /// can fire during a single gesture; the caller is expected to invoke
    /// `persistTabs()` once on drag end so we don't thrash UserDefaults.
    func reorderWithoutPersisting(from source: Int, to destination: Int) {
        guard source >= 0, source < tabs.count, destination >= 0, destination <= tabs.count else { return }
        let store = tabs.remove(at: source)
        let insertIndex = destination > source ? destination - 1 : destination
        let clamped = max(0, min(tabs.count, insertIndex))
        tabs.insert(store, at: clamped)
    }

    /// Public bridge to the private persistence step so views can flush
    /// after a batch of `reorderWithoutPersisting` calls (e.g. drag end).
    func persistTabs() {
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        var blobs: [Data] = []
        for store in tabs {
            do {
                let data = try store.folderURL.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                blobs.append(data)
            } catch {
                logger.warning("persist: bookmark failed for \(store.repoName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            let encoded = try JSONEncoder().encode(blobs)
            UserDefaults.standard.set(encoded, forKey: Self.defaultsKey)
        } catch {
            logger.error("persist: encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return }
        let blobs: [Data]
        do {
            blobs = try JSONDecoder().decode([Data].self, from: data)
        } catch {
            logger.warning("restore: decode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        var restored: [IssueStore] = []
        for blob in blobs {
            var stale = false
            do {
                let url = try URL(
                    resolvingBookmarkData: blob,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else {
                    logger.warning("restore: skipping missing folder \(url.path, privacy: .public)")
                    continue
                }
                let store = IssueStore(folderURL: url)
                attachReloadHook(to: store)
                store.start()
                // Seed each restored tab's baseline from the first reload so
                // the indicator stays clean on launch. (Persistence of the
                // baseline across launches is intentionally out of scope.)
                lastSeenSnapshot[store.id] = store.snapshot
                hasUnseenChanges[store.id] = false
                restored.append(store)
            } catch {
                logger.warning("restore: resolve failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }
        tabs = restored
        activeTabID = restored.first?.id
        if !restored.isEmpty {
            logger.notice("restored \(restored.count, privacy: .public) tabs")
        }
        // Re-persist so a partial restore (some bookmarks dropped) prunes the
        // saved list rather than carrying broken entries forward.
        if restored.count != blobs.count {
            persist()
        }
    }
}
