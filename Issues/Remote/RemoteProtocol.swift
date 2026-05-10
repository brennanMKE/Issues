import Foundation

/// Wire types for the host ↔ viewer protocol (#0080).
///
/// This file is the schema authority. Both the host (`RemoteServer` and its
/// handlers) and the viewer (`RemoteHostIssueSource`, #0094) link this same
/// file so they can't drift in field names or types. JSON keys match the
/// Swift property names verbatim — `JSONEncoder` defaults are fine, no
/// `CodingKeys` overrides.
public enum RemoteProtocol {

    /// Current protocol version. A future v2 host signals via `HostInfo.version`
    /// and a viewer that doesn't recognize the value falls back to
    /// disconnect-with-message rather than guessing the new shape.
    public static let version: Int = 1

    /// Shared encoder used by every handler. ISO8601 with fractional seconds
    /// for compactness and lossless `Date` round-trip.
    public static let encoder: JSONEncoder = {
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
    public static let decoder: JSONDecoder = {
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

public struct HostInfo: Codable, Equatable {
    /// User-visible host label (e.g. "Brennan's MacBook Air"). Sourced from
    /// the system's localized computer name on the concrete host.
    public let displayName: String
    public let version: Int
    public let folderCount: Int

    public init(displayName: String, version: Int, folderCount: Int) {
        self.displayName = displayName
        self.version = version
        self.folderCount = folderCount
    }
}

public struct FolderInfo: Codable, Equatable {
    /// Stable wire identifier (#0082). 16 lowercase hex chars.
    public let id: String
    /// Human label: `project.json` `name` if present, else parent folder name.
    public let name: String
    public let repository: URL?
    public let description: String?
    /// The path of the folder containing the issues folder, e.g.
    /// `/Users/x/Code/MyRepo`. Used for picker disambiguation when two
    /// folders have the same `name` (#0097).
    public let parentPath: String
    public let issueCount: Int
    public let modifiedAt: Date

    public init(
        id: String,
        name: String,
        repository: URL?,
        description: String?,
        parentPath: String,
        issueCount: Int,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.repository = repository
        self.description = description
        self.parentPath = parentPath
        self.issueCount = issueCount
        self.modifiedAt = modifiedAt
    }
}

public struct IssueMetadata: Codable, Equatable {
    public let id: String
    public let title: String
    /// Raw status (e.g. `"in-progress"`). The viewer maps to its own
    /// `IssueStatus` enum.
    public let status: String
    public let modules: [String]
    public let platform: String
    public let firstSeen: Date?
    public let closedAt: Date?
    public let hasAttachments: Bool
    public let modifiedAt: Date

    public init(
        id: String,
        title: String,
        status: String,
        modules: [String],
        platform: String,
        firstSeen: Date?,
        closedAt: Date?,
        hasAttachments: Bool,
        modifiedAt: Date
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.modules = modules
        self.platform = platform
        self.firstSeen = firstSeen
        self.closedAt = closedAt
        self.hasAttachments = hasAttachments
        self.modifiedAt = modifiedAt
    }
}

public struct IssueDetail: Codable, Equatable {
    public let metadata: IssueMetadata
    /// Raw markdown body — everything after the title line and the metadata
    /// table, preserved verbatim. The viewer renders it the same way the
    /// local detail panel renders the on-disk file.
    public let body: String
    /// Relative filenames under `<folder>/<id>/`, e.g. `["screenshot.png"]`.
    /// Bytes are fetched separately via #0081's attachment endpoint.
    public let attachments: [String]

    public init(metadata: IssueMetadata, body: String, attachments: [String]) {
        self.metadata = metadata
        self.body = body
        self.attachments = attachments
    }
}
