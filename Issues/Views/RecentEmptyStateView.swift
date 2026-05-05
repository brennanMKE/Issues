import SwiftUI

struct RecentEmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            Text("No issues match the current filters.")
                .font(.system(size: 12))
                .foregroundStyle(Color.appMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
