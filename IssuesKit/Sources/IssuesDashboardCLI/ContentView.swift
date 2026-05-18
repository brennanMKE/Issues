// ContentView.swift
//
// Flat/hybrid dashboard rendered in the terminal via SwiftTUI.
// Layout: recency-sorted top (~70% of rows) + open-queue tail (~30%),
// no section headers — status colour conveys state per row.

import Foundation
import IssuesCore
import SwiftTUI

struct ContentView: View {
    @ObservedObject var store: DashboardIssueStore

    // Column widths
    private let numberCol: Int = 4
    private let statusCol: Int = 11   // "in-progress" is 11 chars
    private let modifiedCol: Int = 8  // "999d" etc., right-aligned
    private let gutters: Int = 3      // three single-space gutters between four columns

    var body: some View {
        GeometryReader { size in
            let width  = max(1, size.width.intValue)
            let height = max(0, size.height.intValue)

            let snapshot = store.snapshot

            // chrome = title(1) + column header(1) + hairline(1) + footer(1)
            let chrome = 4
            let dataRows = max(0, height - chrome)

            let titleWidth = max(
                10,
                width - numberCol - statusCol - modifiedCol - gutters
            )

            let (topIssues, queueIssues) = hybridLayout(snapshot: snapshot, dataRows: dataRows)

            VStack(alignment: .leading, spacing: 0) {
                titleBar(width: width, snapshot: snapshot)
                columnHeader(titleWidth: titleWidth)
                hairline(width: width)

                ForEach(topIssues) { issue in
                    row(issue, titleWidth: titleWidth)
                }
                ForEach(queueIssues) { issue in
                    row(issue, titleWidth: titleWidth)
                }

                Spacer()
                footer
            }
        }
    }

    // MARK: - Layout

    /// Option B hybrid: top ~70% is all issues by recency; bottom ~30% is
    /// the open queue by id, deduped against whatever is visible in the top.
    /// Unused queue slots are donated back to the top band.
    private func hybridLayout(snapshot: DashboardSnapshot, dataRows: Int) -> (top: [Issue], queue: [Issue]) {
        guard dataRows > 0 else { return ([], []) }

        let topBudget = max(1, dataRows * 7 / 10)
        let queueBudget = dataRows - topBudget

        var topIssues = Array(snapshot.recency.prefix(topBudget))
        let topIDs = Set(topIssues.map(\.id))
        var queueIssues = Array(snapshot.openQueue.filter { !topIDs.contains($0.id) }.prefix(queueBudget))

        // Donate unused queue budget back to the top band.
        let slack = queueBudget - queueIssues.count
        if slack > 0 {
            topIssues = Array(snapshot.recency.prefix(topBudget + slack))
            // Re-dedup after expanding top.
            let expandedTopIDs = Set(topIssues.map(\.id))
            queueIssues = Array(snapshot.openQueue.filter { !expandedTopIDs.contains($0.id) }.prefix(queueBudget))
        }

        return (topIssues, queueIssues)
    }

    // MARK: - Sub-views

    private func titleBar(width: Int, snapshot: DashboardSnapshot) -> some View {
        let stamp = Self.timeFormatter.string(from: snapshot.lastUpdated)
        let folderDisplay = truncate(store.folderURL.path, to: max(10, width - 50))
        let line = "Issues Dashboard — \(snapshot.totalCount) items — \(stamp) — \(folderDisplay)"
        return Text(String(line.prefix(width))).bold()
    }

    private func columnHeader(titleWidth: Int) -> some View {
        HStack(spacing: 1) {
            Text("#")
                .frame(width: Extended(numberCol), alignment: .trailing)
                .bold()
            Text("STATUS")
                .frame(width: Extended(statusCol), alignment: .leading)
                .bold()
            Text("TITLE")
                .frame(width: Extended(titleWidth), alignment: .leading)
                .bold()
            Text("MODIFIED")
                .frame(width: Extended(modifiedCol), alignment: .trailing)
                .bold()
        }
    }

    private func hairline(width: Int) -> some View {
        Text(String(repeating: "─", count: width))
    }

    private func row(_ issue: Issue, titleWidth: Int) -> some View {
        HStack(spacing: 1) {
            Text(issue.id)
                .frame(width: Extended(numberCol), alignment: .trailing)
            Text(issue.status.rawValue)
                .frame(width: Extended(statusCol), alignment: .leading)
                .foregroundColor(color(for: issue.status))
            Text(String(issue.title.prefix(titleWidth)))
                .frame(width: Extended(titleWidth), alignment: .leading)
            Text(TimeAgo.format(issue.modifiedAt))
                .frame(width: Extended(modifiedCol), alignment: .trailing)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let err = store.snapshot.loadError {
            Text("error: \(err)").foregroundColor(.red)
        } else {
            Text("press Ctrl-C to quit")
        }
    }

    // MARK: - Helpers

    private func color(for status: IssueStatus) -> Color {
        switch status {
        case .open:        return .blue
        case .inProgress:  return .yellow
        case .resolved:    return .green
        case .closed:      return .gray
        case .wontfix:     return .gray
        }
    }

    private func truncate(_ s: String, to width: Int) -> String {
        if s.count <= width { return s }
        if width <= 1 { return String(s.suffix(width)) }
        return "…" + String(s.suffix(width - 1))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
