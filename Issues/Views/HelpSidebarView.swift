import SwiftUI

struct HelpSidebarView: View {
    @Binding var selection: HelpSection.ID

    var body: some View {
        List(HelpCatalog.sections, selection: $selection) { section in
            Text(section.title)
                .font(.system(size: 13))
                .foregroundStyle(Color.appText)
                .tag(section.id)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        HelpSidebarView(selection: .constant(HelpCatalog.sections.first!.id))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        HelpSidebarView(selection: .constant(HelpCatalog.sections.first!.id))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    HelpSidebarView(selection: .constant(HelpCatalog.sections.first!.id))
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HelpSidebarView(selection: .constant(HelpCatalog.sections.first!.id))
        .preferredColorScheme(.dark)
}
#endif
