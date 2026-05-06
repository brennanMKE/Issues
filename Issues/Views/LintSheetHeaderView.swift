import SwiftUI

struct LintSheetHeaderView: View {
    let count: Int
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lint findings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appText)
                Text(count == 1 ? "1 issue" : "\(count) issues")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted)
            }
            Spacer(minLength: 8)
            Button {
                onDismiss()
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
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        LintSheetHeaderView(count: 3, onDismiss: {})
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        LintSheetHeaderView(count: 3, onDismiss: {})
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    LintSheetHeaderView(count: 3, onDismiss: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LintSheetHeaderView(count: 3, onDismiss: {})
        .preferredColorScheme(.dark)
}
#endif
