import SwiftUI

struct TimelineTodayMarkerView: View {
    let geometry: TimelineGeometry
    let trackWidth: CGFloat

    var body: some View {
        let today = Date()
        let x = trackWidth * geometry.fraction(for: today)
        return Rectangle()
            .fill(Color.appAccent.opacity(0.6))
            .frame(width: 1)
            .offset(x: x)
    }
}
