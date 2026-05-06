import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import os.log

nonisolated private let folderDropLogger = Logger(subsystem: Logging.subsystem, category: "FolderDropTarget")

/// Reusable drop target (#0050) that accepts folder URLs from Finder and
/// invokes `onFolder` once per dropped directory.
///
/// Edge cases handled here so callers don't have to:
/// - Non-folder drops (regular files) are filtered out via
///   `URLResourceValues.isDirectory` before `onFolder` fires.
/// - Multiple folders dropped at once each invoke `onFolder` separately.
/// - Drag-hover renders an accent border so the user gets standard macOS
///   drop-target feedback.
///
/// Callers do the actual app-level work (bookmarking, tab opening, picker
/// dismiss, etc.) in `onFolder`. Keeps this modifier reusable across the
/// picker scene and the main window.
struct FolderDropTargetModifier: ViewModifier {
    let onFolder: (URL) -> Void

    @State private var isTargeted: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.appAccent, lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let urlProviders = providers.filter { $0.canLoadObject(ofClass: URL.self) }
        guard !urlProviders.isEmpty else { return false }

        for provider in urlProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url else {
                    if let error {
                        folderDropLogger.warning("drop: load failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                guard isDirectory(url) else {
                    folderDropLogger.notice("drop: ignoring non-folder \(url.path, privacy: .public)")
                    return
                }
                Task { @MainActor in
                    onFolder(url)
                }
            }
        }
        return true
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return false
        }
        return isDir.boolValue
    }
}

extension View {
    /// Adds a Finder folder drop zone (#0050). `onFolder` is invoked on the
    /// main actor once per dropped directory; non-folder items are silently
    /// rejected. The drop target shows an accent border while a drag is
    /// hovering.
    func folderDropTarget(onFolder: @escaping (URL) -> Void) -> some View {
        modifier(FolderDropTargetModifier(onFolder: onFolder))
    }
}
