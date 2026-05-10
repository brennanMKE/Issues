import Foundation

/// Wire types for the host ↔ viewer protocol (#0080).
///
/// This file is the schema authority. Both the host (`RemoteServer` and its
/// handlers) and the viewer (`RemoteHostIssueSource`, #0094) link this same
/// file so they can't drift in field names or types. JSON keys match the
/// Swift property names verbatim — `JSONEncoder` defaults are fine, no
/// `CodingKeys` overrides.
enum RemoteProtocol {

    /// Current protocol version. A future v2 host signals via `HostInfo.version`
    /// and a viewer that doesn't recognize the value falls back to
    /// disconnect-with-message rather than guessing the new shape.
    static let version: Int = 1

    /// Shared encoder used by every handler. ISO8601 with fractional seconds
    /// for compactness and lossless `Date` round-trip.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Shared decoder mirroring `encoder`. Same formatter so round-tripping
    /// is exact.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = formatter.date(from: raw) { return date }
            // Tolerate plain ISO8601 without fractional seconds for inputs
            // produced by `RemoteAccess.md`-era prototypes or hand-edited
            // payloads.
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date: \(raw)"
            )
        }
        return decoder
    }()
}

struct HostInfo: Codable, Equatable {
    /// User-visible host label (e.g. "Brennan's MacBook Air"). Sourced from
    /// the system's localized computer name on the concrete host.
    let displayName: String
    let version: Int
    let folderCount: Int
}

struct FolderInfo: Codable, Equatable {
    /// Stable wire identifier (#0082). 16 lowercase hex chars.
    let id: String
    /// Human label: `project.json` `name` if present, else parent folder name.
    let name: String
    let repository: URL?
    let description: String?
    /// The path of the folder containing the issues folder, e.g.
    /// `/Users/x/Code/MyRepo`. Used for picker disambiguation when two
    /// folders have the same `name` (#0097).
    let parentPath: String
    let issueCount: Int
    let modifiedAt: Date
}

struct IssueMetadata: Codable, Equatable {
    let id: String
    let title: String
    /// Raw status (e.g. `"in-progress"`). The viewer maps to its own
    /// `IssueStatus` enum.
    let status: String
    let modules: [String]
    let platform: String
    let firstSeen: Date?
    let closedAt: Date?
    let hasAttachments: Bool
    let modifiedAt: Date
}

struct IssueDetail: Codable, Equatable {
    let metadata: IssueMetadata
    /// Raw markdown body — everything after the title line and the metadata
    /// table, preserved verbatim. The viewer renders it the same way the
    /// local detail panel renders the on-disk file.
    let body: String
    /// Relative filenames under `<folder>/<id>/`, e.g. `["screenshot.png"]`.
    /// Bytes are fetched separately via #0081's attachment endpoint.
    let attachments: [String]
}
