import Foundation

enum FolderBookmarkError: LocalizedError {
    case resolutionFailed(String)
    case notADirectory

    var errorDescription: String? {
        switch self {
        case .resolutionFailed(let msg): return "Could not open folder: \(msg)"
        case .notADirectory: return "Selected item is not a folder."
        }
    }
}
