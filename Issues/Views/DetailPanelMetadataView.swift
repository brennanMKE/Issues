import SwiftUI

struct DetailPanelMetadataView: View {
    let issue: Issue

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                label("Status")
                StatusBadgeView(status: issue.status)
            }
            GridRow {
                label("Module")
                Text(issue.module.isEmpty ? "\u{2014}" : issue.module)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
            }
            GridRow {
                label("Platform")
                Text(issue.platform.isEmpty ? "\u{2014}" : issue.platform)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
            }
            GridRow {
                label("Filed")
                Text(formatted(issue.firstSeen, raw: issue.firstSeenRaw))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appText)
            }
            if !issue.closedRaw.isEmpty {
                GridRow {
                    label("Closed")
                    Text(formatted(issue.closed, raw: issue.closedRaw))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appText)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.appMuted)
            .gridColumnAlignment(.leading)
    }

    private func formatted(_ date: Date?, raw: String) -> String {
        if let date {
            return Self.displayDateFormatter.string(from: date)
        }
        return raw.isEmpty ? "\u{2014}" : raw
    }
}

#if DEBUG
#Preview("Light & Dark") {
    VStack(spacing: 0) {
        DetailPanelMetadataView(issue: PreviewSamples.issue)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .light)

        DetailPanelMetadataView(issue: PreviewSamples.issue)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
            .environment(\.colorScheme, .dark)
    }
    .ignoresSafeArea()
}

#Preview("Light") {
    DetailPanelMetadataView(issue: PreviewSamples.issue)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    DetailPanelMetadataView(issue: PreviewSamples.issue)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
