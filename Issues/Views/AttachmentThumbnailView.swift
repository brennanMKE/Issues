import SwiftUI
import AppKit

/// Renders an issue body's `![alt](path)` reference as a clickable thumbnail
/// (#0056). Hoisted out of the markdown body by `InlineImageMarkdown.split` so
/// it can intercept clicks — Textual draws attachment views through `Canvas`,
/// which doesn't hit-test child gestures, so we render images as sibling
/// SwiftUI views instead of letting Textual inline them at full resolution.
///
/// Behavior:
/// - On-disk image → `NSImage` loaded synchronously (these are small local
///   files, ~hundreds of KB; no need for an async loader for v1).
/// - Width capped at `Self.maxInlineWidth` (480pt), proportional height.
/// - Click presents `AttachmentSheet` at full resolution.
/// - Missing file → "Missing attachment" placeholder. The same condition is
///   already surfaced by `LintFinding.missingAttachment` so the lint sheet
///   keeps the actionable channel; this view just avoids blank space.
struct AttachmentThumbnailView: View {
    static let maxInlineWidth: CGFloat = 480

    let alt: String
    let path: String
    /// Directory the relative `path` is resolved against — typically the
    /// issue's parent folder (matches the `baseURL` `StructuredText` uses for
    /// any other relative refs).
    let baseURL: URL
    /// Invoked on click with the resolved file URL so the host can present
    /// `AttachmentSheet`. Hoisting presentation up keeps sheet state in the
    /// description view rather than per-thumbnail, which avoids stacking
    /// sheets if the body has multiple attachments.
    let onOpen: (URL) -> Void

    private var resolvedURL: URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }

    private var image: NSImage? {
        let url = resolvedURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private var displaySize: CGSize? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let intrinsic = image.size
        let width = min(Self.maxInlineWidth, intrinsic.width)
        let height = width * (intrinsic.height / intrinsic.width)
        return CGSize(width: width, height: height)
    }

    var body: some View {
        Group {
            if let image, let size = displaySize {
                Button(action: { onOpen(resolvedURL) }) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.appBorder, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        // The `alt` text from the markdown becomes the
                        // accessibility label so VoiceOver reads the caption
                        // rather than just "image".
                        .accessibilityLabel(alt.isEmpty ? Text("attachment") : Text(alt))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(alt.isEmpty ? path : alt)
            } else {
                missingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var missingPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(Color.appMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Missing attachment")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appText)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.appMuted)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appBackgroundCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.appBorder, lineWidth: 1)
        )
        .frame(maxWidth: AttachmentThumbnailView.maxInlineWidth, alignment: .leading)
    }
}

private extension View {
    /// Switches to the pointing-hand cursor on hover, matching the existing
    /// link affordance elsewhere in the app. Wrapped because `.onHover` +
    /// `NSCursor` is the canonical AppKit-only pattern and inlining it at
    /// every call site would clutter the layout code.
    func pointingHandCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

#if DEBUG
#Preview("Missing") {
    AttachmentThumbnailView(
        alt: "screenshot",
        path: "0042/missing.png",
        baseURL: URL(fileURLWithPath: "/tmp/preview"),
        onOpen: { _ in }
    )
    .padding()
    .frame(width: 540)
    .background(Color.appBackground)
}
#endif
