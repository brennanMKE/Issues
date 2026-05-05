import SwiftUI

/// Placeholder pane in the Settings window. Real general preferences (theme
/// override, badge toggle, …) land in follow-up issues.
struct GeneralSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "gearshape")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("More preferences coming soon")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    GeneralSettingsView()
}
