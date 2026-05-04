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
    var activeTabID: UUID?

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
        store.start()
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
        store.stop()
        tabs.remove(at: idx)
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

    func reorder(from source: Int, to destination: Int) {
        guard source >= 0, source < tabs.count, destination >= 0, destination <= tabs.count else { return }
        let store = tabs.remove(at: source)
        let insertIndex = destination > source ? destination - 1 : destination
        let clamped = max(0, min(tabs.count, insertIndex))
        tabs.insert(store, at: clamped)
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
                store.start()
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
