import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
/// - Click opens the system Quick Look panel via the host's
///   `.quickLookPreview` binding (#0109). Quick Look handles images, PDFs,
///   logs, etc. natively, replacing the previous custom `AttachmentSheet`
///   modal.
/// - Missing file → "Missing attachment" placeholder. The same condition is
///   already surfaced by `LintFinding.missingAttachment` so the lint sheet
///   keeps the actionable channel; this view just avoids blank space.
///
/// Video posters (#0073): when the parser detects the
/// `[![alt](poster.png)](video.mov)` shape, the host passes a non-nil
/// `videoPath`. If the link's UTI conforms to `.movie` and the file exists, a
/// centered play-button overlay is drawn on the poster and the click opens
/// the video itself in Quick Look (via `onPlay`). Non-video link targets
/// (e.g. `.pdf`) skip the overlay; clicking still opens the link target in
/// Quick Look since the panel previews those types too. A missing video file
/// falls back to the standard "Missing attachment" placeholder for the video
/// path so the user can tell which file is gone.
struct AttachmentThumbnailView: View {
    /// Hard caps for the inline thumbnail. Round 1 only constrained width
    /// (480pt) and computed height from the aspect ratio, which let tall
    /// portrait screenshots run 1000pt+ vertically. Round 2 caps both axes
    /// at recognizable-but-compact sizes so the thumbnail behaves like a
    /// thumbnail regardless of source orientation.
    static let maxInlineWidth: CGFloat = 360
    static let maxInlineHeight: CGFloat = 240

    let alt: String
    let path: String
    /// Directory the relative `path` is resolved against — typically the
    /// issue's parent folder (matches the `baseURL` `StructuredText` uses for
    /// any other relative refs).
    let baseURL: URL
    /// Optional surrounding link target from the
    /// `[![alt](image)](videoPath)` markdown shape (#0073). When the link's
    /// UTI conforms to `.movie`, the click opens Quick Look via `onPlay`;
    /// otherwise the link is opened with `NSWorkspace`. Nil for plain images.
    var videoPath: String? = nil
    /// Invoked on click with the resolved file URL so the host can drive its
    /// `.quickLookPreview` binding. Hoisting presentation up keeps the
    /// binding state in the description view rather than per-thumbnail.
    let onOpen: (URL) -> Void
    /// Invoked on click for the video case (#0073). The host binds this to
    /// the same `@State URL?` driving `.quickLookPreview()` as `onOpen`
    /// (#0109); kept as a separate callback so the play-button overlay can
    /// route to the *video* path rather than the poster image. Defaults to
    /// no-op so existing call sites that only pass `onOpen` keep compiling.
    var onPlay: (URL) -> Void = { _ in }

    private var resolvedURL: URL {
        resolve(path)
    }

    private func resolve(_ relativeOrAbsolute: String) -> URL {
        if relativeOrAbsolute.hasPrefix("/") {
            return URL(fileURLWithPath: relativeOrAbsolute)
        }
        return URL(fileURLWithPath: relativeOrAbsolute, relativeTo: baseURL).standardizedFileURL
    }

    private var image: NSImage? {
        let url = resolvedURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Resolved video URL, or nil if the markdown didn't include a wrapping
    /// link target. Used both to detect the `.movie` UTI and to drive Quick
    /// Look on click.
    private var resolvedVideoURL: URL? {
        guard let videoPath, !videoPath.isEmpty else { return nil }
        return resolve(videoPath)
    }

    /// True when the wrapping link target's extension resolves to a
    /// `.movie`-conforming UTI. Per #0073 we use the UTI rather than an
    /// extension allowlist so new container formats are picked up
    /// automatically as the system gains support.
    private var isVideoLink: Bool {
        guard let url = resolvedVideoURL else { return false }
        let ext = url.pathExtension
        guard !ext.isEmpty else { return false }
        return UTType(filenameExtension: ext)?.conforms(to: .movie) ?? false
    }

    /// True when we have a video link AND the underlying file exists. The
    /// play-button overlay is drawn only in this case; a missing video falls
    /// through to the missing-attachment placeholder rather than offering a
    /// click that would hand `.quickLookPreview()` a non-existent URL.
    private var hasPlayableVideo: Bool {
        guard isVideoLink, let url = resolvedVideoURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Returns the rendered thumbnail size, fit inside `maxInlineWidth` x
    /// `maxInlineHeight` while preserving aspect ratio. Round 1 only fit
    /// width, so a portrait capture stayed full-height; round 2 picks the
    /// limiting axis and scales the other proportionally.
    private var displaySize: CGSize? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let intrinsic = image.size
        let widthRatio = Self.maxInlineWidth / intrinsic.width
        let heightRatio = Self.maxInlineHeight / intrinsic.height
        // Never upscale tiny images — clamp ratio to 1.
        let scale = min(1, min(widthRatio, heightRatio))
        return CGSize(
            width: intrinsic.width * scale,
            height: intrinsic.height * scale
        )
    }

    var body: some View {
        Group {
            // Video link with a missing file: prefer the missing-attachment
            // placeholder for the *video* path so the user sees which file is
            // gone, not the (present) poster.
            if let videoURL = resolvedVideoURL, isVideoLink,
               !FileManager.default.fileExists(atPath: videoURL.path) {
                missingPlaceholder(for: videoURL.path)
            } else if let image, let size = displaySize {
                Button(action: handleClick) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(playOverlay)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.appBorder, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        // The `alt` text from the markdown becomes the
                        // accessibility label so VoiceOver reads the caption
                        // rather than just "image".
                        .accessibilityLabel(accessibilityLabel)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(helpText)
            } else {
                missingPlaceholder(for: path)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Routes the click through the host's Quick Look binding (#0109):
    /// - `.movie`-conforming link with file present → `onPlay(videoURL)`
    ///   so the *video* path is what Quick Look opens, not the poster.
    /// - Non-video wrapping link (e.g. `.pdf`) → `onOpen(linkURL)` to
    ///   preview the link target in Quick Look — the panel previews PDFs,
    ///   logs, etc. natively.
    /// - No wrapping link → `onOpen(resolvedURL)` previews the image itself.
    private func handleClick() {
        if hasPlayableVideo, let url = resolvedVideoURL {
            onPlay(url)
            return
        }
        if let url = resolvedVideoURL, !isVideoLink {
            onOpen(url)
            return
        }
        onOpen(resolvedURL)
    }

    /// The play-button glyph that floats over the poster for video links.
    /// Only rendered when the video file actually exists; a missing video is
    /// already short-circuited above to the missing-attachment placeholder.
    @ViewBuilder
    private var playOverlay: some View {
        if hasPlayableVideo {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white)
                // Soft drop shadow so the glyph reads against bright
                // posters too. SF Symbol with a solid white tint plus a
                // black halo is the same recipe Photos uses for video
                // markers in the grid.
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private var accessibilityLabel: Text {
        let base = alt.isEmpty ? "attachment" : alt
        if hasPlayableVideo {
            return Text("\(base), video")
        }
        return Text(base)
    }

    private var helpText: String {
        if hasPlayableVideo, let url = resolvedVideoURL {
            // Show the video filename in the tooltip so the user sees what
            // Quick Look will open — the alt text describes the poster, not
            // the playable file.
            return alt.isEmpty ? url.lastPathComponent : "\(alt) — \(url.lastPathComponent)"
        }
        return alt.isEmpty ? path : alt
    }

    private func missingPlaceholder(for displayPath: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(Color.appMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Missing attachment")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appText)
                Text(displayPath)
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
