import SwiftUI

struct StatusDotView: View {
    let status: IssueStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.foreground)
            .frame(width: size, height: size)
    }
}
