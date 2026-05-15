import Foundation

public struct RememberedFolder: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity is the bookmark data — folders with identical paths
    /// resolved to identical bookmarks should not appear twice.
    public var id: String { displayPath }

    public var displayPath: String
    public var bookmarkData: Data
    public var lastUsed: Date

    public init(displayPath: String, bookmarkData: Data, lastUsed: Date) {
        self.displayPath = displayPath
        self.bookmarkData = bookmarkData
        self.lastUsed = lastUsed
    }

    public var displayName: String {
        URL(fileURLWithPath: displayPath).lastPathComponent
    }

    public var displayParent: String {
        URL(fileURLWithPath: displayPath)
            .deletingLastPathComponent()
            .path
    }
}
