import Foundation
import AppKit
import CryptoKit
import Observation

@Observable
final class FolderBookmarkService {
    private static let defaultsKey = "rememberedFolders"

    /// Wire-stable folder identifier derived from a security-scoped bookmark
    /// blob (#0082). 16 lowercase hex characters = 8 bytes of SHA-256 prefix
    /// — short enough for log lines and URL paths, far past collision risk
    /// for any realistic folder count.
    ///
    /// Stable across launches as long as the persisted bookmark bytes stay
    /// the same; if the user re-locates a missing folder the bookmark is
    /// re-created and the id legitimately changes.
    nonisolated static func folderId(for bookmarkData: Data) -> String {
        let digest = SHA256.hash(data: bookmarkData)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private(set) var remembered: [RememberedFolder] = []
    var lastError: String?

    init() {
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            remembered = []
            return
        }
        do {
            let folders = try JSONDecoder().decode([RememberedFolder].self, from: data)
            remembered = folders.sorted { $0.lastUsed > $1.lastUsed }
        } catch {
            remembered = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(remembered)
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } catch {
            lastError = "Failed to save remembered folders: \(error.localizedDescription)"
        }
    }

    // MARK: - User flows

    /// Presents an `NSOpenPanel` to pick a directory; returns the resolved URL
    /// (already added to `remembered`) on success.
    func presentOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a folder containing issue markdown files."
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        do {
            try remember(url: url)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
        return url
    }

    /// Records a folder as remembered, replacing any existing entry with the
    /// same display path and bumping `lastUsed`.
    func remember(url: URL) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let entry = RememberedFolder(
            displayPath: url.path,
            bookmarkData: bookmark,
            lastUsed: Date()
        )
        remembered.removeAll { $0.displayPath == entry.displayPath }
        remembered.insert(entry, at: 0)
        remembered.sort { $0.lastUsed > $1.lastUsed }
        save()
    }

    /// Resolves a remembered bookmark to a usable URL, refreshing the
    /// bookmark if the system reports it stale. Caller is responsible for
    /// pairing `startAccessingSecurityScopedResource()` / `stop…`.
    func resolve(_ folder: RememberedFolder) throws -> URL {
        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: folder.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw FolderBookmarkError.resolutionFailed(error.localizedDescription)
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            throw FolderBookmarkError.notADirectory
        }

        if stale {
            do {
                let fresh = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                if let idx = remembered.firstIndex(where: { $0.displayPath == folder.displayPath }) {
                    remembered[idx].bookmarkData = fresh
                    remembered[idx].lastUsed = Date()
                    save()
                }
            } catch {
                // Stale-but-resolvable is acceptable; refresh failure is non-fatal.
            }
        } else {
            if let idx = remembered.firstIndex(where: { $0.displayPath == folder.displayPath }) {
                remembered[idx].lastUsed = Date()
                remembered.sort { $0.lastUsed > $1.lastUsed }
                save()
            }
        }

        return url
    }

    func forget(_ folder: RememberedFolder) {
        remembered.removeAll { $0.displayPath == folder.displayPath }
        save()
    }
}
