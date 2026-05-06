import SwiftUI
import AppKit

/// Full-size image viewer presented when the user clicks an inline attachment
/// thumbnail (#0056). Shows the image at its native resolution inside a
/// scrollable frame, with a Reveal-in-Finder action for power users and an
/// Esc/space dismiss to match the issue preview sheet's existing key-handling
/// vocabulary.
///
/// Pinch-zoom is intentionally out for v1 — `ScrollView` lets the user pan
/// large captures, and most issue screenshots fit in the sheet at 1× anyway.
/// The hook is here (the image is resizable) so we can add `magnification`
/// later without restructuring the view.
struct AttachmentSheet: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

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

    @ViewBuilder
    private var content: some View {
        if let image {
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: image.size.width,
                        height: image.size.height
                    )
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackgroundCard)
        } else {
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
