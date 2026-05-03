import Foundation
import Observation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "IssueStore")

@Observable
final class IssueStore {

    enum ViewMode: String, CaseIterable, Hashable {
        case swimlane, timeline, list

        var displayName: String {
            switch self {
            case .swimlane: return "Swimlanes"
            case .timeline: return "Timeline"
            case .list: return "List"
            }
        }
    }

    enum SortColumn: String, Hashable {
        case id, status, title, module, platform, firstSeen
    }

    let folderURL: URL
    private(set) var issues: [Issue] = []
    private(set) var loadError: String?
    private(set) var folderInvalidated: Bool = false

    var statusFilters: Set<IssueStatus> = []
    var moduleFilter: String?
    var platformFilter: String?
    var viewMode: ViewMode = .swimlane
    var selectedIssueID: String?
    var sortColumn: SortColumn = .id
    var sortAscending: Bool = true

    private var watcher: FolderWatcher?
    private var didStartAccess: Bool = false

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
        logger.notice("start folder=\(self.folderURL.path, privacy: .public) scopedAccess=\(self.didStartAccess, privacy: .public)")
        reload()
        let watcher = FolderWatcher(
            onChange: { [weak self] in self?.reload() },
            onInvalidated: { [weak self] in
                logger.notice("folder invalidated — clearing store")
                self?.folderInvalidated = true
            }
        )
        watcher.start(url: folderURL)
        self.watcher = watcher
    }

    func stop() {
        logger.notice("stop")
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
                    logger.warning("read \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
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
            logger.notice("reload parsed=\(parsed.count, privacy: .public) skipped=\(skippedNames.count, privacy: .public) wasCount=\(prevCount, privacy: .public) elapsedMs=\(ms, privacy: .public)")
            if !skippedNames.isEmpty {
                logger.warning("skipped files: \(skippedNames.joined(separator: ", "), privacy: .public)")
            }
        } catch {
            self.loadError = "Failed to read folder: \(error.localizedDescription)"
            logger.error("reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Derived state

    var filteredIssues: [Issue] {
        issues.filter { issue in
            if !statusFilters.isEmpty && !statusFilters.contains(issue.status) { return false }
            if let m = moduleFilter, !issue.modules.contains(m) { return false }
            if let p = platformFilter, issue.platform != p, issue.platform != "All" { return false }
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
}
