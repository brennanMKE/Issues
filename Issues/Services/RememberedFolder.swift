import Foundation

struct RememberedFolder: Codable, Identifiable, Hashable {
    /// Stable identity is the bookmark data — folders with identical paths
    /// resolved to identical bookmarks should not appear twice.
    var id: String { displayPath }

    var displayPath: String
    var bookmarkData: Data
    var lastUsed: Date

    var displayName: String {
        URL(fileURLWithPath: displayPath).lastPathComponent
    }

    var displayParent: String {
        URL(fileURLWithPath: displayPath)
            .deletingLastPathComponent()
            .path
    }
}
