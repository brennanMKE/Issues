// DashboardModel.swift
//
// Produces a DashboardSnapshot for the flat/hybrid (Option B) dashboard layout.

import Foundation
import IssuesCore

struct DashboardSnapshot: Sendable {
    /// All issues sorted by modifiedAt descending — the recency band.
    let recency: [Issue]
    /// Open issues sorted by id ascending — the queue band (dedup against
    /// visible recency rows happens in the view layer).
    let openQueue: [Issue]
    let totalCount: Int
    let lastUpdated: Date
    let loadError: String?

    static let empty = DashboardSnapshot(
        recency: [],
        openQueue: [],
        totalCount: 0,
        lastUpdated: Date(),
        loadError: nil
    )
}

enum DashboardModel {
    static func snapshot(
        issues: [Issue],
        lastUpdated: Date,
        loadError: String?
    ) -> DashboardSnapshot {
        let recency = issues.sorted { $0.modifiedAt > $1.modifiedAt }
        let openQueue = issues
            .filter { $0.status == .open }
            .sorted { $0.id < $1.id }

        return DashboardSnapshot(
            recency: recency,
            openQueue: openQueue,
            totalCount: issues.count,
            lastUpdated: lastUpdated,
            loadError: loadError
        )
    }
}
