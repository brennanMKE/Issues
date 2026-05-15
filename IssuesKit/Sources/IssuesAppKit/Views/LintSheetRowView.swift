import SwiftUI
import IssuesCore
#if canImport(AppKit)
import AppKit
#endif

struct LintSheetRowView: View {
    let finding: LintFinding

    var body: some View {
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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        LintSheetRowView(finding: PreviewSamples.lintFinding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        LintSheetRowView(finding: PreviewSamples.lintFinding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    LintSheetRowView(finding: PreviewSamples.lintFinding)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LintSheetRowView(finding: PreviewSamples.lintFinding)
        .preferredColorScheme(.dark)
}
#endif
