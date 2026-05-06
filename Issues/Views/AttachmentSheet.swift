import SwiftUI
import AppKit

/// Full-size image viewer presented when the user clicks an inline attachment
/// thumbnail (#0056).
///
/// - Round 1 wrapped the image in a `ScrollView` at native resolution — large
///   screenshots opened with scrollbars and no zoom controls.
/// - Round 2 added a fit-scale + manual `offset`/`DragGesture` pan, with
///   visible zoom buttons and a percent label in the toolbar.
/// - Round 3 (this revision): the manual offset model pushed zoomed content
///   into the top-left corner instead of letting the user roam around the
///   image. The toolbar zoom buttons + percent label were also visual noise.
///   The image now lives inside a `ScrollView([.horizontal, .vertical])` so
///   native macOS scrollbars + drag-pan handle navigation once the image
///   exceeds the visible area. The toolbar drops to filename, Reveal-in-Finder,
///   and close. Pinch-zoom, double-click toggle, and the Cmd-0 / Cmd-= /
///   Cmd-- keyboard shortcuts are preserved (the shortcuts now live on hidden
///   buttons so they don't add visual clutter).
struct AttachmentSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    /// Multiplier applied on top of the fit-scale baseline. 1 means
    /// "size to fit"; the magnification gesture and Cmd-=/Cmd-- both
    /// adjust this value. When `zoom > 1` the image's framed size exceeds
    /// the ScrollView's visible area and the scrollbars activate.
    @State private var zoom: CGFloat = 1
    /// Snapshot of `zoom` at the start of a magnification gesture; the
    /// gesture's `value` is multiplied against this so a slow pinch
    /// composes naturally with previous zooms.
    @State private var zoomAnchor: CGFloat = 1

    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 8
    private static let zoomStep: CGFloat = 1.25

    private var image: NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.appBorder)
            content
        }
        .frame(minWidth: 480, idealWidth: 900, maxWidth: .infinity,
               minHeight: 320, idealHeight: 700, maxHeight: .infinity)
        .background(Color.appBackground)
        .background(keyboardShortcutShim)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.space) {
            dismiss()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(url.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.appText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: revealInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(image == nil)
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Hidden buttons that exist solely to register the Cmd-0 / Cmd-= /
    /// Cmd-- keyboard shortcuts. They stay out of the layout via
    /// `.frame(width: 0, height: 0)` and `.hidden()` so the toolbar can be
    /// uncluttered while the shortcuts still fire.
    private var keyboardShortcutShim: some View {
        ZStack {
            Button("Zoom out", action: zoomOut)
                .keyboardShortcut("-", modifiers: .command)
            Button("Zoom in", action: zoomIn)
                .keyboardShortcut("=", modifiers: .command)
            Button("Fit", action: resetZoom)
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .hidden()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            zoomableImage(image)
        } else {
            missingState
        }
    }

    /// Renders the image inside a horizontal+vertical `ScrollView`. At
    /// `zoom == 1` the framed size matches the fit size, so the image
    /// fills the visible area and the scrollbars stay quiet. Once the user
    /// pinches past fit (`zoom > 1`) the framed size exceeds the visible
    /// area and native scrollbars + drag-pan let them inspect any region
    /// of the image. Manual `offset`/`DragGesture` pan was deliberately
    /// dropped because it pushed content into the top-left rather than
    /// scrolling around the zoomed image.
    @ViewBuilder
    private func zoomableImage(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let fitScale = computeFitScale(imageSize: image.size, container: geometry.size)
            let fitWidth = image.size.width * fitScale
            let fitHeight = image.size.height * fitScale
            let displayWidth = max(fitWidth * zoom, fitWidth)
            let displayHeight = max(fitHeight * zoom, fitHeight)

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayWidth, height: displayHeight)
                    .gesture(magnification)
                    .onTapGesture(count: 2) {
                        toggleFitOrTwoX()
                    }
                    .accessibilityLabel(Text(url.lastPathComponent))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackgroundCard)
        }
    }

    private var missingState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.appMuted)
            Text("Could not load image")
                .font(.system(size: 13))
                .foregroundStyle(Color.appText)
            Text(url.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appMuted)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color.appBackgroundCard)
    }

    // MARK: - Gestures

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = clampZoom(zoomAnchor * value)
            }
            .onEnded { _ in
                zoomAnchor = zoom
                if zoom <= 1 {
                    // Snapping fit-or-below back to exactly 1 cleans up any
                    // accumulated rounding so the image refits cleanly.
                    zoom = 1
                    zoomAnchor = 1
                }
            }
    }

    // MARK: - Zoom helpers

    private func zoomIn() {
        let next = clampZoom(zoom * Self.zoomStep)
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = next
            zoomAnchor = next
        }
    }

    private func zoomOut() {
        let next = clampZoom(zoom / Self.zoomStep)
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = next
            zoomAnchor = next
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = 1
            zoomAnchor = 1
        }
    }

    private func toggleFitOrTwoX() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if zoom > 1.05 {
                zoom = 1
                zoomAnchor = 1
            } else {
                zoom = 2
                zoomAnchor = 2
            }
        }
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, Self.minZoom), Self.maxZoom)
    }

    /// Returns the scale that fits `imageSize` inside `container` without
    /// upscaling — small images stay at native pixels rather than
    /// blowing up to fill the sheet.
    private func computeFitScale(imageSize: CGSize, container: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else { return 1 }
        let widthRatio = container.width / imageSize.width
        let heightRatio = container.height / imageSize.height
        return min(1, min(widthRatio, heightRatio))
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#if DEBUG
#Preview {
    AttachmentSheet(url: URL(fileURLWithPath: "/tmp/missing-preview.png"))
}
#endif
