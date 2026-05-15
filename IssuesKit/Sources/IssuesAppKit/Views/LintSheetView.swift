import SwiftUI
import IssuesCore

/// Sheet listing every `LintFinding` for the active folder. Read-only — each
/// row gets a "Reveal in Finder" action so the user can investigate; the app
/// itself never auto-fixes.
///
/// Lifetime is owned by `MainView` (via `@State var showingLintSheet`),
/// matching the pattern used for `IssueMarkdownSheet`.
struct LintSheetView: View {
    let findings: [LintFinding]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            LintSheetHeaderView(count: findings.count, onDismiss: { dismiss() })
            Divider().background(Color.appBorder)
            LintSheetContentView(findings: findings)
        }
        .frame(minWidth: 560, idealWidth: 720, maxWidth: .infinity,
               minHeight: 320, idealHeight: 520, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        LintSheetView(findings: PreviewSamples.lintFindings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        LintSheetView(findings: PreviewSamples.lintFindings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    LintSheetView(findings: PreviewSamples.lintFindings)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LintSheetView(findings: PreviewSamples.lintFindings)
        .preferredColorScheme(.dark)
}
#endif
