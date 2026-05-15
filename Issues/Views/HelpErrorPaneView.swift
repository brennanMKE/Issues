import SwiftUI
import IssuesCore

struct HelpErrorPaneView: View {
    let error: Error
    let sectionTitle: String

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load \(sectionTitle)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text(error.localizedDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appMuted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.appBackground)
    }
}

#if DEBUG
private let previewError = NSError(domain: "preview", code: 0, userInfo: [NSLocalizedDescriptionKey: "Sample error"])

#Preview("Light & Dark") {
    VStack(spacing: 0) {
        HelpErrorPaneView(error: previewError, sectionTitle: "Overview")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        HelpErrorPaneView(error: previewError, sectionTitle: "Overview")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    HelpErrorPaneView(error: previewError, sectionTitle: "Overview")
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HelpErrorPaneView(error: previewError, sectionTitle: "Overview")
        .preferredColorScheme(.dark)
}
#endif
