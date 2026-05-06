import SwiftUI
import Textual

struct HelpSuccessPaneView: View {
    let text: String

    var body: some View {
        ScrollView(.vertical) {
            StructuredText(
                markdown: text,
                baseURL: bundleHelpDirectory()
            )
            .textual.textSelection(.enabled)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.appBackground)
    }

    /// Best-effort base URL for relative image references inside the help
    /// markdown. Returns the bundled `Help/` directory if it resolves, else
    /// the app bundle's resource URL, else nil. Images are out of scope
    /// for v1 but the `baseURL` keeps the door open.
    private func bundleHelpDirectory() -> URL? {
        if let url = Bundle.main.url(forResource: "Help", withExtension: nil) {
            return url
        }
        return Bundle.main.resourceURL
    }
}

#if DEBUG
private let previewHelpText = "## Sample\n\nMarkdown content for the preview."

#Preview("Light & Dark") {
    VStack(spacing: 0) {
        HelpSuccessPaneView(text: previewHelpText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        HelpSuccessPaneView(text: previewHelpText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    HelpSuccessPaneView(text: previewHelpText)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HelpSuccessPaneView(text: previewHelpText)
        .preferredColorScheme(.dark)
}
#endif
