import Foundation
import IssuesCore

enum HelpLoadError: LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name):
            return "The bundled file \(name).md is missing from the app's Help resources."
        }
    }
}
