// ContentView.swift
//
// Tri-band (ACTIVE / RECENT / NEXT UP) dashboard rendered in the terminal
// via SwiftTUI. Truncates rather than scrolls — the band budget is
// recomputed every layout pass so the table re-flows on resize.

import Foundation
import SwiftTUI

struct ContentView: View {
    @ObservedObject var store: IssueStore

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

            // De-dup NEXT UP against the *visible* RECENT slice (see
            // allocation below), not the full recent array.
            let plan = layoutPlan(
                snapshot: snapshot,
                terminalHeight: height
            )

            let titleWidth = max(
                10,
                width - numberCol - statusCol - modifiedCol - gutters
            )

            VStack(alignment: .leading, spacing: 0) {
                titleBar(width: width, snapshot: snapshot)

                if plan.showActive {
                    sectionHeader("ACTIVE", width: width)
                    ForEach(Array(snapshot.inProgress.prefix(plan.ipShow))) { issue in
                        row(issue, titleWidth: titleWidth)
                    }
                }

                if plan.showRecent {
                    sectionHeader("RECENT", width: width)
                    ForEach(Array(snapshot.recent.prefix(plan.recentShow))) { issue in
                        row(issue, titleWidth: titleWidth)
                    }
                }

                if plan.showNext {
                    sectionHeader("NEXT UP", width: width)
                    ForEach(plan.nextUpVisible) { issue in
                        row(issue, titleWidth: titleWidth)
                    }
                }

                Spacer()
                footer
            }
        }
    }

    // MARK: - Layout plan

    private struct LayoutPlan {
        let ipShow: Int
        let recentShow: Int
        let nextShow: Int
        let nextUpVisible: [Issue]
        let showActive: Bool
        let showRecent: Bool
        let showNext: Bool
    }

    private func layoutPlan(snapshot: DashboardSnapshot, terminalHeight: Int) -> LayoutPlan {
        // chrome = title (1) + footer (1) + headers for non-empty bands.
        let activeNonEmpty = !snapshot.inProgress.isEmpty
        let recentNonEmpty = !snapshot.recent.isEmpty

        // For NEXT UP emptiness we need to know which IDs the visible
        // RECENT slice will hide. Iterate twice if needed: start with a
        // conservative estimate, then refine. In practice a single pass
        // with three potential headers is good enough — assume all three
        // bands could appear, allocate, then drop any band that ends up
        // with zero rows and recompute once.
        var headers = 0
        if activeNonEmpty { headers += 1 }
        if recentNonEmpty { headers += 1 }
        // assume NEXT UP header in first pass if there are any open issues
        let nextNonEmptyFirstPass = !snapshot.nextUp.isEmpty
        if nextNonEmptyFirstPass { headers += 1 }

        let chrome = 2 + headers
        let visibleRows = max(0, terminalHeight - chrome)

        let ipShow = min(snapshot.inProgress.count, visibleRows)
        let remaining = max(0, visibleRows - ipShow)

        var recentShow = min(snapshot.recent.count, remaining * 6 / 10)

        // Build the visible RECENT slice now so we can dedup NEXT UP.
        let visibleRecentIDs = Set(snapshot.recent.prefix(recentShow).map(\.id))
        let nextUpFiltered = snapshot.nextUp.filter { !visibleRecentIDs.contains($0.id) }

        var nextShow = min(nextUpFiltered.count, remaining - recentShow)

        // Donate slack greedily.
        var slack = remaining - recentShow - nextShow
        if slack > 0 && recentShow < snapshot.recent.count {
            let bonus = min(slack, snapshot.recent.count - recentShow)
            recentShow += bonus
            slack -= bonus
        }
        if slack > 0 && nextShow < nextUpFiltered.count {
            let bonus = min(slack, nextUpFiltered.count - nextShow)
            nextShow += bonus
            slack -= bonus
        }

        // After growing recentShow, the dedup set may now hide more open
        // issues — recompute once to keep the dedup honest.
        let visibleRecentIDs2 = Set(snapshot.recent.prefix(recentShow).map(\.id))
        let nextUpFiltered2 = snapshot.nextUp.filter { !visibleRecentIDs2.contains($0.id) }
        nextShow = min(nextShow, nextUpFiltered2.count)

        let nextUpVisible = Array(nextUpFiltered2.prefix(nextShow))

        let showActive = activeNonEmpty && ipShow > 0
        let showRecent = recentNonEmpty && recentShow > 0
        let showNext = !nextUpVisible.isEmpty

        // If a band turned out empty we leak its header — fine, the
        // bottom is padded with Spacer().
        _ = remaining

        return LayoutPlan(
            ipShow: ipShow,
            recentShow: recentShow,
            nextShow: nextShow,
            nextUpVisible: nextUpVisible,
            showActive: showActive,
            showRecent: showRecent,
            showNext: showNext
        )
    }

    // MARK: - Sub-views

    private func titleBar(width: Int, snapshot: DashboardSnapshot) -> some View {
        let count = snapshot.inProgress.count + snapshot.recent.count
        let stamp = Self.timeFormatter.string(from: snapshot.lastUpdated)
        let folderDisplay = truncate(store.folderURL.path, to: max(10, width - 50))
        let line = "Issues Dashboard — \(count) items — \(stamp) — \(folderDisplay)"
        return Text(String(line.prefix(width))).bold()
    }

    private func sectionHeader(_ name: String, width: Int) -> some View {
        // Bold single-line band header: "─ NAME ──────"
        let prefix = "─ \(name) "
        let fillerCount = max(1, width - displayWidth(prefix))
        let filler = String(repeating: "─", count: fillerCount)
        return Text(prefix + filler).bold()
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

    private func displayWidth(_ s: String) -> Int {
        // Approximation: count grapheme clusters. Box-drawing chars are
        // single-width in monospaced terminals so this is accurate enough.
        return s.count
    }

    /// Truncate from the left if too long, prefixing with `…`.
    private func truncate(_ s: String, to width: Int) -> String {
        if s.count <= width { return s }
        if width <= 1 { return String(s.suffix(width)) }
        let keep = width - 1
        return "…" + String(s.suffix(keep))
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
