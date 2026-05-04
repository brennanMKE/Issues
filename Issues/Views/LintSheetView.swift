import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

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
            header
            Divider().background(Color.appBorder)
            content
        }
        .frame(minWidth: 560, idealWidth: 720, maxWidth: .infinity,
               minHeight: 320, idealHeight: 520, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lint findings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text(findings.count == 1 ? "1 issue" : "\(findings.count) issues")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appMuted)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appBackgroundCard)
    }

    @ViewBuilder
    private var content: some View {
        if findings.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Color.appMuted)
                Text("No lint findings")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(findings) { finding in
                        row(for: finding)
                        Divider().background(Color.appBorder)
                    }
                }
            }
            .background(Color.appBackground)
        }
    }

    private func row(for finding: LintFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.statusOpen)
                .frame(width: 16, height: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(finding.fileURL.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            Spacer(minLength: 8)
            Button {
                revealInFinder(finding.fileURL)
            } label: {
                Text("Reveal in Finder")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.appText)
                    .background(Color.appBackgroundCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.appBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Reveal \(finding.fileURL.lastPathComponent) in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealInFinder(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }
}
