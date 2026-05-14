// IssueStore.swift
//
// Polls the folder once per second, parses every NNNN.md, and publishes a
// DashboardSnapshot. On error, the previous band contents are preserved and
// only `loadError` flips so the UI doesn't blank out on a transient miss.

import Combine
import Foundation

@MainActor
final class IssueStore: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot = .empty

    let folderURL: URL
    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    init(folderURL: URL, interval: TimeInterval = 1.0) {
        self.folderURL = folderURL
        self.interval = interval
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.reload()
                let nanos = UInt64(self.interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func reload() async {
        let url = folderURL
        // Off-main directory listing + parse, then publish on the main actor.
        let result = await Task.detached(priority: .utility) { () -> Result<[Issue], Error> in
            do {
                let fm = FileManager.default
                let entries = try fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
                )
                var issues: [Issue] = []
                issues.reserveCapacity(entries.count)
                for entry in entries {
                    let name = entry.lastPathComponent
                    guard MarkdownIssueParser.filenameMatchesIssuePattern(name) else { continue }
                    if let issue = try MarkdownIssueParser.parse(fileURL: entry) {
                        issues.append(issue)
                    }
                }
                return .success(issues)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let issues):
            snapshot = DashboardModel.snapshot(
                issues: issues,
                lastUpdated: Date(),
                loadError: nil
            )
        case .failure(let error):
            // Preserve prior band contents — only flip loadError so the
            // screen doesn't blank out on a transient filesystem miss.
            snapshot = DashboardSnapshot(
                inProgress: snapshot.inProgress,
                recent: snapshot.recent,
                nextUp: snapshot.nextUp,
                lastUpdated: snapshot.lastUpdated,
                loadError: error.localizedDescription
            )
        }
    }
}
