import SwiftUI

struct MainErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusOpen)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Color.appText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.appBackgroundCard)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.appBorder).frame(height: 1)
        }
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        MainErrorBannerView(message: "Failed to read folder: missing permission")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        MainErrorBannerView(message: "Failed to read folder: missing permission")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    MainErrorBannerView(message: "Failed to read folder: missing permission")
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    MainErrorBannerView(message: "Failed to read folder: missing permission")
        .preferredColorScheme(.dark)
}
#endif
