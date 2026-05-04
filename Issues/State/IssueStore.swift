import Foundation
import Observation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "IssueStore")

/// Compact, value-typed view of an issue used to detect changes between
/// reloads. Includes id, status, and file mtime so that body edits — which
/// don't change id/status — still register as "unseen changes" via `modifiedAt`.
struct IssueSnapshot: Hashable, Sendable {
    let id: String
    let status: IssueStatus
    let modifiedAt: Date
}

@Observable
final class IssueStore: Identifiable {

    enum ViewMode: String, CaseIterable, Hashable {
        case swimlane, timeline, list, recent

        var displayName: String {
            switch self {
            case .swimlane: return "Swimlanes"
            case .timeline: return "Timeline"
            case .list: return "List"
            case .recent: return "Recent"
            }
        }
    }

    enum SortColumn: String, Hashable {
        case id, status, title, module, platform, firstSeen
    }

    /// Stable per-store identity used as the tab id by `TabsModel`. Survives
    /// across reloads; not persisted (tabs are persisted by bookmark, ids are
    /// regenerated on launch).
    let id: UUID = UUID()
    let folderURL: URL
    private(set) var issues: [Issue] = []
    private(set) var loadError: String?
    private(set) var folderInvalidated: Bool = false

    var statusFilters: Set<IssueStatus> = []
    var moduleFilter: String?
    var platformFilter: String?
    // TODO #0009: persist `searchQuery` per tab so closing/reopening a tab
    // restores the query. v1 deliberately resets on tab close.
    var searchQuery: String = ""
    var viewMode: ViewMode = .swimlane
    var selectedIssueID: String?
    var sortColumn: SortColumn = .id
    var sortAscending: Bool = true

    private var watcher: FolderWatcher?
    private var didStartAccess: Bool = false

    /// Fires after every successful `reload()` (i.e. after `issues` has been
    /// reassigned). Used by `TabsModel` to drive the per-tab "unseen changes"
    /// indicator. Not fired on read failures — those leave `issues` untouched
    /// and shouldn't flip the indicator. In practice this always fires on the
    /// main actor: the initial `reload()` is called from `TabsModel`
    /// (main-isolated) and subsequent reloads come through
    /// `FolderWatcher.onChange`, which is `@MainActor` by contract.
    var onReload: ((IssueStore) -> Void)?

    /// Repo-style label for the watched folder, e.g. for a folder
    /// `/path/to/MyRepo/issues` this is `MyRepo`. Used for tab titles and log
    /// labels so multi-folder log streams stay readable.
    var repoName: String {
        folderURL.deletingLastPathComponent().lastPathComponent
    }

    init(folderURL: URL) {
        self.folderURL = folderURL
    }

    deinit {
        // Synchronous cleanup; SwiftUI lifetime ends here. Avoid touching
        // observable storage from deinit.
        if didStartAccess {
            folderURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Lifecycle

    func start() {
        didStartAccess = folderURL.startAccessingSecurityScopedResource()
        logger.notice("[\(self.repoName, privacy: .public)] start folder=\(self.folderURL.path, privacy: .public) scopedAccess=\(self.didStartAccess, privacy: .public)")
        reload()
        let repoName = self.repoName
        let watcher = FolderWatcher(
            onChange: { [weak self] in self?.reload() },
            onInvalidated: { [weak self] in
                logger.notice("[\(repoName, privacy: .public)] folder invalidated — clearing store")
                self?.folderInvalidated = true
            }
        )
        watcher.start(url: folderURL)
        self.watcher = watcher
    }

    func stop() {
        logger.notice("[\(self.repoName, privacy: .public)] stop")
        watcher?.stop()
        watcher = nil
        if didStartAccess {
            folderURL.stopAccessingSecurityScopedResource()
            didStartAccess = false
        }
    }

    // MARK: - Loading

    func reload() {
        let started = Date()
        do {
            let fm = FileManager.default
            let entries = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            var parsed: [Issue] = []
            var skippedNames: [String] = []
            for url in entries {
                let name = url.lastPathComponent
                guard MarkdownIssueParser.filenameMatchesIssuePattern(name) else {
                    continue
                }
                do {
                    if let issue = try MarkdownIssueParser.parse(fileURL: url) {
                        parsed.append(issue)
                    } else {
                        skippedNames.append(name)
                    }
                } catch {
                    skippedNames.append(name)
                    logger.warning("[\(self.repoName, privacy: .public)] read \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            parsed.sort { $0.id < $1.id }
            let prevCount = self.issues.count
            self.issues = parsed
            if let id = selectedIssueID, !parsed.contains(where: { $0.id == id }) {
                selectedIssueID = nil
            }
            self.loadError = nil
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            logger.notice("[\(self.repoName, privacy: .public)] reload parsed=\(parsed.count, privacy: .public) skipped=\(skippedNames.count, privacy: .public) wasCount=\(prevCount, privacy: .public) elapsedMs=\(ms, privacy: .public)")
            if !skippedNames.isEmpty {
                logger.warning("[\(self.repoName, privacy: .public)] skipped files: \(skippedNames.joined(separator: ", "), privacy: .public)")
            }
            onReload?(self)
        } catch {
            self.loadError = "Failed to read folder: \(error.localizedDescription)"
            logger.error("[\(self.repoName, privacy: .public)] reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Derived state

    var filteredIssues: [Issue] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedQuery = trimmedQuery.isEmpty ? nil : trimmedQuery.lowercased()
        return issues.filter { issue in
            if !statusFilters.isEmpty && !statusFilters.contains(issue.status) { return false }
            if let m = moduleFilter, !issue.modules.contains(m) { return false }
            if let p = platformFilter, issue.platform != p, issue.platform != "All" { return false }
            if let q = lowercasedQuery {
                guard issue.title.lowercased().contains(q) ||
                      issue.description.lowercased().contains(q) else { return false }
            }
            return true
        }
    }

    var selectedIssue: Issue? {
        guard let id = selectedIssueID else { return nil }
        return issues.first { $0.id == id }
    }

    func groupedByPrimaryModule(_ list: [Issue]) -> [(module: String, issues: [Issue])] {
        var order: [String] = []
        var buckets: [String: [Issue]] = [:]
        for issue in list {
            let key = issue.primaryModule
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(issue)
        }
        return order.map { (module: $0, issues: buckets[$0] ?? []) }
    }

    var uniqueModules: [String] {
        var set = Set<String>()
        for issue in issues {
            for module in issue.modules where !module.isEmpty {
                set.insert(module)
            }
        }
        return set.sorted()
    }

    var uniquePlatforms: [String] {
        var set = Set<String>()
        for issue in issues where !issue.platform.isEmpty {
            set.insert(issue.platform)
        }
        return set.sorted()
    }

    /// A change-detection view of the current issue list keyed by id. Used by
    /// `TabsModel` to compare the post-reload state against what the user last
    /// saw on this tab.
    var snapshot: [String: IssueSnapshot] {
        var result: [String: IssueSnapshot] = [:]
        result.reserveCapacity(issues.count)
        for issue in issues {
            result[issue.id] = IssueSnapshot(
                id: issue.id,
                status: issue.status,
                modifiedAt: issue.modifiedAt
            )
        }
        return result
    }

    var statusCounts: [IssueStatus: Int] {
        var counts: [IssueStatus: Int] = [:]
        for issue in issues {
            counts[issue.status, default: 0] += 1
        }
        return counts
    }

    func toggleSelection(_ id: String) {
        if selectedIssueID == id {
            selectedIssueID = nil
        } else {
            selectedIssueID = id
        }
    }

    func deselect() {
        selectedIssueID = nil
    }

    // MARK: - Keyboard navigation

    /// Issues in the order the active view displays them. The flat order across
    /// view modes:
    /// - List: filtered set sorted by `id` ascending. The view itself can
    ///   override sort via column headers, but for ↑/↓ navigation we use the
    ///   stable id order so the keyboard walk is deterministic regardless of
    ///   column sort. (`Table` already handles its own focused navigation; this
    ///   helper is the fallback.)
    /// - Recent: filtered set by `modifiedAt` descending.
    /// - Swimlanes: grouped by primary module, flattened.
    /// - Timeline: same grouping as Swimlanes (display order matches).
    var visibleIssueOrder: [Issue] {
        let filtered = filteredIssues
        switch viewMode {
        case .list:
            return filtered.sorted { $0.id < $1.id }
        case .recent:
            return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
        case .swimlane, .timeline:
            return groupedByPrimaryModule(filtered).flatMap { $0.issues }
        }
    }

    /// Moves selection to the next issue in `visibleIssueOrder`. Wraps around
    /// at the end. If nothing is selected, picks the first.
    func selectNext() {
        let order = visibleIssueOrder
        guard !order.isEmpty else { return }
        if let id = selectedIssueID, let idx = order.firstIndex(where: { $0.id == id }) {
            selectedIssueID = order[(idx + 1) % order.count].id
        } else {
            selectedIssueID = order.first?.id
        }
    }

    /// Moves selection to the previous issue in `visibleIssueOrder`. Wraps
    /// around at the start. If nothing is selected, picks the last.
    func selectPrevious() {
        let order = visibleIssueOrder
        guard !order.isEmpty else { return }
        if let id = selectedIssueID, let idx = order.firstIndex(where: { $0.id == id }) {
            selectedIssueID = order[(idx - 1 + order.count) % order.count].id
        } else {
            selectedIssueID = order.last?.id
        }
    }
}
