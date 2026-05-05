import SwiftUI

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
