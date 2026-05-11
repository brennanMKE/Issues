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
    /// Optional repository URL — comes straight from `project.json`'s
    /// `url` field. JSON key matches the source so a viewer that already
    /// understands `project.json` doesn't need a rename.
    public let url: URL?
    /// Optional description — reserved for a planned `project.json`
    /// extension; today's host always sends `null`.
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
        url: URL?,
        description: String?,
        parentPath: String,
        issueCount: Int,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.url = url
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

// MARK: - WebSocket events (#0100, #0101)

/// Server → Client event sent over `/v1/events`. The `type` field is the
/// discriminator; other fields are populated conditionally. Encoded as a flat
/// JSON object so the viewer can decode without a wrapper. `JSONEncoder` skips
/// `nil` optionals when the field is `Optional`, so a `hello` event won't
/// include `folderId` / `id`.
public struct RemoteEvent: Codable, Equatable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case hello
        case reload
        case update
        case delete
        case unsubscribed
        case pong
    }

    public let type: Kind
    public let displayName: String?
    public let version: Int?
    public let folderId: String?
    public let id: String?
    public let reason: String?

    public init(
        type: Kind,
        displayName: String? = nil,
        version: Int? = nil,
        folderId: String? = nil,
        id: String? = nil,
        reason: String? = nil
    ) {
        self.type = type
        self.displayName = displayName
        self.version = version
        self.folderId = folderId
        self.id = id
        self.reason = reason
    }

    public static func hello(displayName: String) -> RemoteEvent {
        RemoteEvent(type: .hello, displayName: displayName, version: RemoteProtocol.version)
    }

    public static func reload(folderId: String) -> RemoteEvent {
        RemoteEvent(type: .reload, folderId: folderId)
    }

    public static func update(folderId: String, id: String) -> RemoteEvent {
        RemoteEvent(type: .update, folderId: folderId, id: id)
    }

    public static func delete(folderId: String, id: String) -> RemoteEvent {
        RemoteEvent(type: .delete, folderId: folderId, id: id)
    }

    public static func unsubscribed(folderId: String, reason: String) -> RemoteEvent {
        RemoteEvent(type: .unsubscribed, folderId: folderId, reason: reason)
    }

    public static let pong = RemoteEvent(type: .pong)

    private enum CodingKeys: String, CodingKey {
        case type, displayName, version, folderId, id, reason
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        // Skip nil fields on encode so e.g. `hello` doesn't write `folderId:null`.
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(folderId, forKey: .folderId)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(reason, forKey: .reason)
    }
}

/// Client → Server message decoded from inbound text frames on `/v1/events`.
/// Same flat-object shape as `RemoteEvent` for symmetry; only the fields a
/// command actually carries are populated.
public struct RemoteCommand: Codable, Equatable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case subscribe
        case unsubscribe
        case ping
    }

    public let type: Kind
    public let folderIds: [String]?

    public init(type: Kind, folderIds: [String]? = nil) {
        self.type = type
        self.folderIds = folderIds
    }
}
