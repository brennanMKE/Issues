// DashboardModel.swift
//
// Pure ranking for the tri-band (ACTIVE / RECENT / NEXT UP) layout.

import Foundation

struct DashboardSnapshot: Sendable {
    let inProgress: [Issue]
    let recent: [Issue]
    let nextUp: [Issue]
    let lastUpdated: Date
    let loadError: String?

    static let empty = DashboardSnapshot(
        inProgress: [],
        recent: [],
        nextUp: [],
        lastUpdated: Date(),
        loadError: nil
    )
}

enum DashboardModel {
    /// Build a snapshot from a flat list of parsed issues.
    ///
    /// - ACTIVE: all `in-progress`, sorted by `modifiedAt` desc.
    /// - RECENT: everything not in ACTIVE, sorted by `modifiedAt` desc.
    /// - NEXT UP: all `open` issues sorted by id asc. The view layer is
    ///   responsible for filtering out IDs that already appear in the
    ///   *visible* RECENT slice (see ContentView).
    static func snapshot(
        issues: [Issue],
        lastUpdated: Date,
        loadError: String?
    ) -> DashboardSnapshot {
        let inProgress = issues
            .filter { $0.status == .inProgress }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        let inProgressIDs = Set(inProgress.map(\.id))

        let recent = issues
            .filter { !inProgressIDs.contains($0.id) }
            .sorted { $0.modifiedAt > $1.modifiedAt }

        let nextUp = issues
            .filter { $0.status == .open }
            .sorted { $0.id < $1.id }

        return DashboardSnapshot(
            inProgress: inProgress,
            recent: recent,
            nextUp: nextUp,
            lastUpdated: lastUpdated,
            loadError: loadError
        )
    }
}
