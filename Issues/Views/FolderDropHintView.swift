import SwiftUI

/// Passive visual affordance (#0067) advertising that a surface accepts a
/// folder drop from Finder. Renders a dashed `RoundedRectangle` with an
/// optional icon and caption.
///
/// This view is purely decorative — the actual drop handling lives on the
/// parent view via the `folderDropTarget` modifier (#0050). When a drag is
/// hovering, the modifier overlays an accent border on top of the entire
/// drop region, which visually supersedes the dashed hint without any
/// extra coordination needed here.
struct FolderDropHintView: View {
    /// SF Symbol name shown above the caption. `nil` for the compact
    /// single-line variant.
    var systemImage: String? = "tray.and.arrow.down"

    /// Primary caption text. Single line for the compact variant; can wrap
    /// across two lines in the tall variant.
    var caption: String

    /// Optional secondary line beneath the caption (tall variant only).
    var detail: String? = nil

    /// Corner radius of the dashed rectangle. Matches the 8 pt corner used
    /// by the drag-hover accent overlay so the two visuals align.
    var cornerRadius: CGFloat = 8

    var body: some View {
        VStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.appMuted)
            }
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.appMuted)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appMuted.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    Color.appBorder,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(caption))
        .accessibilityHint(Text("Drop a folder here to open it."))
    }
}

#if DEBUG
#Preview("Tall — Light & Dark") {
    VStack(spacing: 16) {
        FolderDropHintView(
            caption: "Drag an issues folder here to open it",
            detail: "or use the button above"
        )
        .padding()
        .frame(maxWidth: 360)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        FolderDropHintView(
            caption: "Drag an issues folder here to open it",
            detail: "or use the button above"
        )
        .padding()
        .frame(maxWidth: 360)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .padding()
}

#Preview("Compact — Light & Dark") {
    VStack(spacing: 16) {
        FolderDropHintView(
            systemImage: nil,
            caption: "\u{2026}or drop a folder here"
        )
        .padding()
        .frame(maxWidth: 360)
        .background(Color.appBackground)
        .environment(\.colorScheme, .light)

        FolderDropHintView(
            systemImage: nil,
            caption: "\u{2026}or drop a folder here"
        )
        .padding()
        .frame(maxWidth: 360)
        .background(Color.appBackground)
        .environment(\.colorScheme, .dark)
    }
    .padding()
}
#endif
