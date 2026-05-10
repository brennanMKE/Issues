import Foundation

#if os(macOS)

/// v1 REST handlers (#0080). Each function takes the parsed `HTTPRequest`
/// + captured route placeholders and returns the wire response. The
/// handlers are pure of I/O beyond reading the markdown file for the
/// `IssueDetail` body — `MultiFolderStore` already holds the parsed list
/// of issues so listing is in-memory.
enum RemoteHandlers {

    /// Builds the route table for the server's `installDefaultRoutes`. A
    /// single function so the order and shape stay in one place; the
    /// listener doesn't need to know which path goes to which handler.
    static func routes(store: MultiFolderStore) -> [Route] {
        [
            Route(
                method: "GET",
                pathPattern: "/v1/host",
                handler: { _, _ in try host(store: store) }
            ),
            Route(
                method: "GET",
                pathPattern: "/v1/folders",
                handler: { _, _ in try folders(store: store) }
            ),
            Route(
                method: "GET",
                pathPattern: "/v1/folders/{folderId}",
                handler: { _, captures in try folder(store: store, captures: captures) }
            ),
            Route(
                method: "GET",
                pathPattern: "/v1/folders/{folderId}/issues",
                handler: { _, captures in try issues(store: store, captures: captures) }
            ),
            Route(
                method: "GET",
                pathPattern: "/v1/folders/{folderId}/issues/{id}",
                handler: { _, captures in try issueDetail(store: store, captures: captures) }
            )
        ]
    }

    // MARK: - Endpoints

    static func host(store: MultiFolderStore) throws -> HTTPResponse {
        let folders = store.currentlyHostedFolders()
        let info = HostInfo(
            displayName: store.hostDisplayName,
            version: RemoteProtocol.version,
            folderCount: folders.count
        )
        return try response(200, statusText: "OK", encoding: info)
    }

    static func folders(store: MultiFolderStore) throws -> HTTPResponse {
        let infos = store.currentlyHostedFolders().map(folderInfo(from:))
        return try response(200, statusText: "OK", encoding: infos)
    }

    static func folder(store: MultiFolderStore, captures: [String: String]) throws -> HTTPResponse {
        guard let id = captures["folderId"], let folder = store.currentlyHostedFolder(forId: id) else {
            return .notFound()
        }
        return try response(200, statusText: "OK", encoding: folderInfo(from: folder))
    }

    static func issues(store: MultiFolderStore, captures: [String: String]) throws -> HTTPResponse {
        guard let id = captures["folderId"], let folder = store.currentlyHostedFolder(forId: id) else {
            return .notFound()
        }
        let metas = folder.issues.map(issueMetadata(from:))
        return try response(200, statusText: "OK", encoding: metas)
    }

    static func issueDetail(store: MultiFolderStore, captures: [String: String]) throws -> HTTPResponse {
        guard let folderId = captures["folderId"],
              let folder = store.currentlyHostedFolder(forId: folderId) else {
            return .notFound()
        }
        guard let issueId = captures["id"],
              let issue = folder.issues.first(where: { $0.id == issueId }) else {
            return .notFound()
        }

        let contents: String
        do {
            contents = try String(contentsOf: issue.fileURL, encoding: .utf8)
        } catch {
            throw RemoteHandlerError.read(error)
        }
        let body = MarkdownIssueParser.body(from: contents)
        let attachments = listAttachments(forIssue: issue)
        let detail = IssueDetail(
            metadata: issueMetadata(from: issue),
            body: body,
            attachments: attachments
        )
        return try response(200, statusText: "OK", encoding: detail)
    }

    // MARK: - Wire-shape conversions

    static func folderInfo(from folder: HostedFolder) -> FolderInfo {
        FolderInfo(
            id: folder.id,
            name: folder.displayName,
            repository: folder.projectMetadata?.url,
            description: nil,
            parentPath: folder.folderURL.deletingLastPathComponent().path,
            issueCount: folder.issues.count,
            modifiedAt: folder.modifiedAt
        )
    }

    static func issueMetadata(from issue: Issue) -> IssueMetadata {
        IssueMetadata(
            id: issue.id,
            title: issue.title,
            status: issue.statusRaw,
            modules: issue.modules,
            platform: issue.platform,
            firstSeen: issue.firstSeen,
            closedAt: issue.closed,
            hasAttachments: issue.hasAttachments,
            modifiedAt: issue.modifiedAt
        )
    }

    /// Lists files under `<folder>/<issueId>/` — the same layout the local
    /// detail panel uses (#0071). Returns an empty list on any error so a
    /// missing or unreadable directory degrades to "no attachments" rather
    /// than failing the whole request.
    static func listAttachments(forIssue issue: Issue) -> [String] {
        let folderURL = issue.fileURL.deletingLastPathComponent().appendingPathComponent(issue.id, isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            return []
        }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { $0.lastPathComponent }
            .sorted()
    }

    // MARK: - Helpers

    private static func response<T: Encodable>(_ status: Int, statusText: String, encoding value: T) throws -> HTTPResponse {
        let body: Data
        do {
            body = try RemoteProtocol.encoder.encode(value)
        } catch {
            throw RemoteHandlerError.encode(error)
        }
        return HTTPResponse(
            status: status,
            statusText: statusText,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }
}

enum RemoteHandlerError: Error {
    case read(Error)
    case encode(Error)
}

#endif
