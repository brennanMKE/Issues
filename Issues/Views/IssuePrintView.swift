import SwiftUI

#if os(macOS)

/// Print-only rendering of an `Issue` (#0063). Used as the root view of an
/// `NSPrintOperation`. Forced light color scheme, larger body fonts sized
/// for paper, generous margins. No interactive chrome — no close buttons,
/// no Quick Look hooks. The body wraps and paginates naturally inside
/// `NSPrintOperation`.
struct IssuePrintView: View {

    let issue: Issue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("#\(issue.id) — \(issue.title)")
                .font(.system(size: 24, weight: .semibold))

            metadataGrid

            if !issue.description.isEmpty {
                Text(issue.description)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Status", issue.status.displayName)
            if !issue.module.isEmpty {
                row("Module", issue.module)
            }
            if !issue.platform.isEmpty {
                row("Platform", issue.platform)
            }
            if !issue.firstSeenRaw.isEmpty {
                row("First seen", issue.firstSeenRaw)
            }
            if !issue.closedRaw.isEmpty {
                row("Closed", issue.closedRaw)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.black)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .fontWeight(.semibold)
                .gridColumnAlignment(.leading)
            Text(value)
        }
    }
}

#endif
