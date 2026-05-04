import Foundation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "MarkdownIssueParser")

/// Reasons the parser may reject an otherwise well-named `NNNN.md` file.
/// Surfaced through `parseDetailed(...)` so the lint pane (#0019) can explain
/// why a file was skipped instead of silently ignoring it.
enum MarkdownIssueParseError: Error, Equatable, Hashable, Sendable {
    /// File name doesn't match `^\d{4}\.md$` — the filename gate. Strictly
    /// speaking the linter never sees this case (it filters first), but the
    /// error is exposed for symmetry with the existing `parse(...)` contract.
    case filenameMismatch
    /// No `# NNNN \u{2014} Title` line. Most often a hyphen was used instead
    /// of an em-dash (U+2014), or the heading is missing entirely.
    case missingTitle
    /// No `| **Status** | … |` row in the metadata table.
    case missingStatus
}

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
        return parse(fileURL: fileURL, contents: contents, modifiedAt: modifiedAt)
    }

    /// Pure parsing entry point — testable without disk access.
    static func parse(fileURL: URL, contents: String, modifiedAt: Date = Date()) -> Issue? {
        switch parseDetailed(fileURL: fileURL, contents: contents, modifiedAt: modifiedAt) {
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
        modifiedAt: Date = Date()
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
                modifiedAt: modifiedAt
            )
        )
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
