import SwiftUI
import AppKit

/// Full-size image viewer presented when the user clicks an inline attachment
/// thumbnail (#0056). Round 1 wrapped the image in a `ScrollView` at native
/// resolution — large screenshots opened with scrollbars and no zoom controls.
/// Round 2 makes the sheet a proper viewer:
///
/// - On open the image is scaled to fit the available area (no scrollbars at
///   the default 1× zoom).
/// - `MagnificationGesture` drives a `@State zoom` clamped to `[0.5, 8]`.
/// - When zoom > fit, a `DragGesture` pans the image inside the sheet.
/// - Double-click toggles between fit and 2×.
/// - Keyboard: Esc / space dismiss; Cmd-0 reset to fit; Cmd-= / Cmd-+
///   zoom in; Cmd-- zoom out.
/// - Reveal-in-Finder is unchanged.
struct AttachmentSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    /// Multiplier applied on top of the fit-scale baseline. 1 means
    /// "size to fit"; the magnification gesture and Cmd-=/Cmd-- both
    /// adjust this value.
    @State private var zoom: CGFloat = 1
    /// Snapshot of `zoom` at the start of a magnification gesture; the
    /// gesture's `value` is multiplied against this so a slow pinch
    /// composes naturally with previous zooms.
    @State private var zoomAnchor: CGFloat = 1
    /// User-applied pan offset in points, in the unzoomed coordinate space
    /// of the image container. Reset to .zero whenever zoom returns to 1
    /// so the next double-click-to-fit recenters cleanly.
    @State private var offset: CGSize = .zero
    @State private var dragAnchor: CGSize = .zero

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
            zoomControls
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

    /// Cmd-= / Cmd-- / Cmd-0 keyboard shortcuts plus matching buttons. The
    /// hidden shortcut buttons keep the keyboard wiring colocated with the
    /// visible controls and avoid a separate `.keyboardShortcut` chain on
    /// invisible elements that's easy to lose track of.
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom out (Cmd-)")
            .keyboardShortcut("-", modifiers: .command)
            .disabled(image == nil)

            Text(zoomLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.appMuted)
                .frame(minWidth: 44)

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Zoom in (Cmd=)")
            .keyboardShortcut("=", modifiers: .command)
            .disabled(image == nil)

            Button(action: resetZoom) {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Fit to window (Cmd-0)")
            .keyboardShortcut("0", modifiers: .command)
            .disabled(image == nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            zoomableImage(image)
        } else {
            missingState
        }
    }

    /// Renders the image at fit-scale (computed from the GeometryProxy) then
    /// multiplies in the user's zoom and pan. Manual offset + scale (rather
    /// than wrapping a ScrollView) gives us pinch-to-zoom-while-panning
    /// without the focus/scroll-clipping conflicts a nested ScrollView
    /// introduces, and lets a single double-tap reset both axes.
    @ViewBuilder
    private func zoomableImage(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let fitScale = computeFitScale(imageSize: image.size, container: geometry.size)
            let displayWidth = image.size.width * fitScale * zoom
            let displayHeight = image.size.height * fitScale * zoom

            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: displayWidth, height: displayHeight)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackgroundCard)
                .contentShape(Rectangle())
                .gesture(magnification)
                .simultaneousGesture(panGesture)
                .onTapGesture(count: 2) {
                    toggleFitOrTwoX()
                }
                .accessibilityLabel(Text(url.lastPathComponent))
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
                    // accumulated rounding and recenters the image.
                    zoom = 1
                    zoomAnchor = 1
                    offset = .zero
                    dragAnchor = .zero
                }
            }
    }

    /// Panning is only meaningful when the image is larger than the
    /// container. At zoom == 1 the image already fits so a drag would just
    /// slide it off-center for no reason.
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(
                    width: dragAnchor.width + value.translation.width,
                    height: dragAnchor.height + value.translation.height
                )
            }
            .onEnded { _ in
                dragAnchor = offset
            }
    }

    // MARK: - Zoom helpers

    private var zoomLabel: String {
        let percent = Int((zoom * 100).rounded())
        return "\(percent)%"
    }

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
            if next <= 1 {
                offset = .zero
                dragAnchor = .zero
            }
        }
    }

    private func resetZoom() {
        withAnimation(.easeInOut(duration: 0.15)) {
            zoom = 1
            zoomAnchor = 1
            offset = .zero
            dragAnchor = .zero
        }
    }

    private func toggleFitOrTwoX() {
        withAnimation(.easeInOut(duration: 0.15)) {
            if zoom > 1.05 {
                zoom = 1
                zoomAnchor = 1
                offset = .zero
                dragAnchor = .zero
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
