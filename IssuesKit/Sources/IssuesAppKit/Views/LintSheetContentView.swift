import SwiftUI
import IssuesCore

struct LintSheetContentView: View {
    let findings: [LintFinding]

    var body: some View {
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
                        LintSheetRowView(finding: finding)
                        Divider().background(Color.appBorder)
                    }
                }
            }
            .background(Color.appBackground)
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        LintSheetContentView(findings: PreviewSamples.lintFindings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        LintSheetContentView(findings: PreviewSamples.lintFindings)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    LintSheetContentView(findings: PreviewSamples.lintFindings)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LintSheetContentView(findings: PreviewSamples.lintFindings)
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    LintSheetContentView(findings: [])
        .preferredColorScheme(.light)
}
#endif
