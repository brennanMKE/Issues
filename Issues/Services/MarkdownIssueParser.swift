import Foundation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "MarkdownIssueParser")

enum MarkdownIssueParser {
    private static let filenamePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^\d{4}\.md$"#)
    }()

    private static let titlePattern: NSRegularExpression = {
        // Em-dash is U+2014.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: "^# \\d+ \u{2014} (.+)$",
            options: [.anchorsMatchLines]
        )
    }()

    private static let descriptionPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"## Description\s+(.+?)(?=\n##|\z)"#,
            options: [.dotMatchesLineSeparators]
        )
    }()

    private static func fieldPattern(for name: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: "\\|\\s*\\*\\*\(NSRegularExpression.escapedPattern(for: name))\\*\\*\\s*\\|\\s*(.+?)\\s*\\|"
        )
    }

    private static let statusFieldPattern = fieldPattern(for: "Status")
    private static let moduleFieldPattern = fieldPattern(for: "Module")
    private static let platformFieldPattern = fieldPattern(for: "Platform")
    private static let firstSeenFieldPattern = fieldPattern(for: "First seen")
    private static let closedFieldPattern = fieldPattern(for: "Closed")

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Extracts the raw markdown body — everything after the title line
    /// and the metadata table — preserving line breaks and formatting
    /// verbatim. Used by the remote `IssueDetail` endpoint (#0080) so the
    /// viewer can render the same body the local detail panel renders.
    ///
    /// Strategy: locate the metadata table (a markdown pipe table that
    /// begins right after the H1 title), skip past its trailing blank
    /// line, and return the rest. If the title or table is missing the
    /// function returns the contents trimmed of any leading H1 line — a
    /// best-effort fallback for malformed files.
    static func body(from contents: String) -> String {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var idx = 0

        // Skip the first H1 if present.
        while idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
            idx += 1
        }
        if idx < lines.count, lines[idx].hasPrefix("# ") {
            idx += 1
        }

        // Walk through the metadata table — any contiguous block of `|...|`
        // lines (with optional leading whitespace) plus blank lines that
        // separate it from the rest.
        while idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
            idx += 1
        }
        while idx < lines.count {
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                idx += 1
            } else {
                break
            }
        }
        // Eat one trailing blank line after the table.
        if idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces).isEmpty {
            idx += 1
        }

        return lines[idx...].joined(separator: "\n")
    }

    /// Returns true if the file's last path component matches `^\d{4}\.md$`.
    static func filenameMatchesIssuePattern(_ filename: String) -> Bool {
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        return filenamePattern.firstMatch(in: filename, range: range) != nil
    }

    static func parse(fileURL: URL) throws -> Issue? {
        let filename = fileURL.lastPathComponent
        guard filenameMatchesIssuePattern(filename) else { return nil }
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        let modifiedAt = resourceValues?.contentModificationDate ?? Date()
        let hasAttachments = attachmentFolderHasFiles(for: fileURL)
        return parse(
            fileURL: fileURL,
            contents: contents,
            modifiedAt: modifiedAt,
            hasAttachments: hasAttachments
        )
    }

    /// Pure parsing entry point — testable without disk access.
    static func parse(
        fileURL: URL,
        contents: String,
        modifiedAt: Date = Date(),
        hasAttachments: Bool = false
    ) -> Issue? {
        switch parseDetailed(
            fileURL: fileURL,
            contents: contents,
            modifiedAt: modifiedAt,
            hasAttachments: hasAttachments
        ) {
        case .success(let issue):
            return issue
        case .failure(let error):
            if case .missingTitle = error {
                logger.warning("skip \(fileURL.lastPathComponent, privacy: .public): title line did not match `# NNNN — Title` (em-dash U+2014 required)")
            }
            return nil
        }
    }

    /// Parsing entry point that distinguishes between the failure modes the
    /// lint pane needs to display. The success payload is identical to what
    /// `parse(...)` returns; the failure payload describes which structural
    /// element was missing or malformed.
    static func parseDetailed(
        fileURL: URL,
        contents: String,
        modifiedAt: Date = Date(),
        hasAttachments: Bool = false
    ) -> Result<Issue, MarkdownIssueParseError> {
        let filename = fileURL.lastPathComponent
        guard filenameMatchesIssuePattern(filename) else {
            return .failure(.filenameMismatch)
        }

        // ID is the leading 4-digit portion of the filename.
        let id = String(filename.prefix(4))

        guard let title = firstCapture(of: titlePattern, in: contents)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else {
            return .failure(.missingTitle)
        }

        guard let statusRawCapture = firstCapture(of: statusFieldPattern, in: contents) else {
            return .failure(.missingStatus)
        }
        let statusRaw = statusRawCapture.trimmingCharacters(in: .whitespacesAndNewlines)
        let moduleRaw = firstCapture(of: moduleFieldPattern, in: contents) ?? ""
        let platformRaw = firstCapture(of: platformFieldPattern, in: contents) ?? ""
        let firstSeenRaw = firstCapture(of: firstSeenFieldPattern, in: contents) ?? ""
        let closedRaw = firstCapture(of: closedFieldPattern, in: contents) ?? ""

        let description = firstCapture(of: descriptionPattern, in: contents)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let status = IssueStatus(raw: statusRaw)
        let module = moduleRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let platform = platformRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        let firstSeen = parseDate(firstSeenRaw)
        let closed = parseDate(closedRaw)

        return .success(
            Issue(
                id: id,
                title: title,
                status: status,
                statusRaw: statusRaw,
                module: module,
                platform: platform,
                firstSeen: firstSeen,
                firstSeenRaw: firstSeenRaw,
                closed: closed,
                closedRaw: closedRaw,
                description: description,
                fileURL: fileURL,
                modifiedAt: modifiedAt,
                hasAttachments: hasAttachments
            )
        )
    }

    /// Returns `true` when a sibling `<id>/` directory next to `<id>.md`
    /// exists and contains at least one regular file. Used by
    /// `IssueStore.reload()` to decorate parsed issues with attachment
    /// presence (#0071), so the attachment filter can run as a pure
    /// in-memory predicate.
    ///
    /// An empty `<id>/` folder counts as "no attachments". A symlink target
    /// is followed via `FileManager.default.contentsOfDirectory` semantics.
    /// Errors (folder missing, unreadable, etc.) all map to `false`.
    static func attachmentFolderHasFiles(for issueFileURL: URL) -> Bool {
        let filename = issueFileURL.lastPathComponent
        guard filenameMatchesIssuePattern(filename) else { return false }
        let id = String(filename.prefix(4))
        let folderURL = issueFileURL.deletingLastPathComponent().appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        guard let entries = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return false }
        for url in entries {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isRegular { return true }
        }
        return false
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return dateFormatter.date(from: trimmed)
    }

    private static func firstCapture(of regex: NSRegularExpression, in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captureRange])
    }
}
