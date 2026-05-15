import SwiftUI
import IssuesCore

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

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        TimelineTodayMarkerView(
            geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
            trackWidth: 600
        )
        .frame(width: 600, height: 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        TimelineTodayMarkerView(
            geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
            trackWidth: 600
        )
        .frame(width: 600, height: 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    TimelineTodayMarkerView(
        geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
        trackWidth: 600
    )
    .frame(width: 600, height: 60)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    TimelineTodayMarkerView(
        geometry: TimelineGeometry.compute(issues: PreviewSamples.issues),
        trackWidth: 600
    )
    .frame(width: 600, height: 60)
    .preferredColorScheme(.dark)
}
#endif
