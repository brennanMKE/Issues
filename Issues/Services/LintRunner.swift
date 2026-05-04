import Foundation
import os.log

nonisolated private let lintLogger = Logger(subsystem: Logging.subsystem, category: "LintRunner")

/// Walks an issues folder and produces a flat list of `LintFinding`s. Pure
/// (no observable state, no UI). Driven by `IssueStore.reload()` so the
/// findings stay in sync with the parsed issue list.
///
/// Read-only by design: surfaces problems for the user but never auto-fixes.
enum LintRunner {

    /// Canonical statuses recognized by IssuesSkill. Anything outside this set
    /// (after lowercase + whitespace→hyphen normalization) is flagged.
    private static let canonicalStatuses: Set<String> = Set(
        IssueStatus.allCases.map { $0.rawValue }
    )

    /// Matches markdown image references: `![alt](path)`. The first capture
    /// group is the path. Title-attribute syntax (`![alt](path "title")`) is
    /// not supported; that's a deliberate limit because IssuesSkill never
    /// generates titled images.
    private static let imageRefPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#)
    }()

    /// Folder name pattern: four digits, no extension. Matches the directory
    /// half of an `NNNN.md` + `NNNN/` issue pair.
    private static let folderNamePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"^\d{4}$"#)
    }()

    /// Run every lint over the folder. Cheap — meant to run on every reload.
    /// Findings are returned in a stable-ish order (file findings first by
    /// path, then folder findings) so the UI doesn't shuffle row order
    /// between reloads when nothing actually changed.
    static func run(folderURL: URL, parsedIssues: [Issue]) -> [LintFinding] {
        let started = Date()
        var findings: [LintFinding] = []

        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            lintLogger.error("lint listing failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        var issueFiles: [URL] = []
        var subfolders: [URL] = []
        for url in entries {
            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir, matchesFolderNamePattern(name) {
                subfolders.append(url)
            } else if !isDir, MarkdownIssueParser.filenameMatchesIssuePattern(name) {
                issueFiles.append(url)
            }
        }

        // 1. Parse-failure findings — re-run the detailed parser on each file
        //    that the filename gate accepts.
        let parsedByURL = Dictionary(uniqueKeysWithValues: parsedIssues.map { ($0.fileURL.standardizedFileURL, $0) })
        for url in issueFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let std = url.standardizedFileURL
            if parsedByURL[std] != nil { continue }
            // Wasn't parsed — figure out why.
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                findings.append(LintFinding(
                    fileURL: url,
                    kind: .parseFailure(reason: "could not read file"),
                    summary: "\(url.lastPathComponent) could not be read"
                ))
                continue
            }
            let result = MarkdownIssueParser.parseDetailed(fileURL: url, contents: contents)
            if case .failure(let error) = result {
                let (reason, summary) = describe(error: error, filename: url.lastPathComponent)
                findings.append(LintFinding(
                    fileURL: url,
                    kind: .parseFailure(reason: reason),
                    summary: summary
                ))
            }
        }

        // 2. Unknown-status findings — only meaningful for issues that did
        //    parse, since failed parses already produced a finding.
        for issue in parsedIssues {
            let normalized = issue.statusRaw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            if !normalized.isEmpty, !canonicalStatuses.contains(normalized) {
                findings.append(LintFinding(
                    fileURL: issue.fileURL,
                    kind: .unknownStatus(raw: issue.statusRaw),
                    summary: "\(issue.fileURL.lastPathComponent) has unknown status \"\(issue.statusRaw)\""
                ))
            }
        }

        // 3. Orphan-folder findings — `NNNN/` with no matching `NNNN.md`.
        let issueFilenames = Set(issueFiles.map { $0.lastPathComponent })
        for folder in subfolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let expected = "\(folder.lastPathComponent).md"
            if !issueFilenames.contains(expected) {
                findings.append(LintFinding(
                    fileURL: folder,
                    kind: .orphanFolder,
                    summary: "folder \(folder.lastPathComponent)/ has no matching \(expected)"
                ))
            }
        }

        // 4. Missing-attachment findings — scan each parsed issue's markdown
        //    for image refs and verify the path resolves on disk. Re-reading
        //    the file is acceptable because lint runs are infrequent (one per
        //    reload, ~150ms-debounced) and counts are small.
        for issue in parsedIssues {
            guard let contents = try? String(contentsOf: issue.fileURL, encoding: .utf8) else {
                continue
            }
            for path in extractImagePaths(from: contents) {
                if isLikelyExternalReference(path) { continue }
                let resolved = resolveAttachment(path: path, base: issue.fileURL.deletingLastPathComponent())
                if !fm.fileExists(atPath: resolved.path) {
                    findings.append(LintFinding(
                        fileURL: issue.fileURL,
                        kind: .missingAttachment(path: path),
                        summary: "\(issue.fileURL.lastPathComponent) references missing attachment \(path)"
                    ))
                }
            }
        }

        // 5. Duplicate-id findings — group parsed issues by id. The filename
        //    gate makes this nearly impossible in practice (the id comes from
        //    the filename), but if we ever loosen the gate this catches it.
        let grouped = Dictionary(grouping: parsedIssues, by: { $0.id })
        for (id, group) in grouped where group.count > 1 {
            let sorted = group.sorted { $0.fileURL.path < $1.fileURL.path }
            // Pair every duplicate after the first against the first so the
            // UI shows one finding per extra collision.
            let primary = sorted[0]
            for dup in sorted.dropFirst() {
                findings.append(LintFinding(
                    fileURL: dup.fileURL,
                    kind: .duplicateID(otherFileURL: primary.fileURL),
                    summary: "\(dup.fileURL.lastPathComponent) duplicates id \(id) from \(primary.fileURL.lastPathComponent)"
                ))
            }
        }

        let ms = Int(Date().timeIntervalSince(started) * 1000)
        lintLogger.debug("lint findings=\(findings.count, privacy: .public) elapsedMs=\(ms, privacy: .public)")
        return findings
    }

    // MARK: - Helpers

    private static func matchesFolderNamePattern(_ name: String) -> Bool {
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return folderNamePattern.firstMatch(in: name, range: range) != nil
    }

    private static func describe(
        error: MarkdownIssueParseError,
        filename: String
    ) -> (reason: String, summary: String) {
        switch error {
        case .filenameMismatch:
            return ("filename does not match NNNN.md", "\(filename) does not match NNNN.md")
        case .missingTitle:
            return (
                "missing or malformed title (expected `# NNNN — Title` with em-dash)",
                "\(filename) has no `# NNNN — Title` line (em-dash U+2014 required)"
            )
        case .missingStatus:
            return (
                "missing required Status field",
                "\(filename) is missing the Status field"
            )
        }
    }

    private static func extractImagePaths(from text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = imageRefPattern.matches(in: text, range: range)
        var paths: [String] = []
        paths.reserveCapacity(matches.count)
        for match in matches where match.numberOfRanges >= 2 {
            if let r = Range(match.range(at: 1), in: text) {
                let raw = String(text[r]).trimmingCharacters(in: .whitespaces)
                if !raw.isEmpty { paths.append(raw) }
            }
        }
        return paths
    }

    /// `http://`, `https://`, `data:` etc. — those aren't on-disk attachments
    /// and shouldn't be flagged as missing.
    private static func isLikelyExternalReference(_ path: String) -> Bool {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return true }
        if path.hasPrefix("data:") { return true }
        if path.hasPrefix("mailto:") { return true }
        return false
    }

    private static func resolveAttachment(path: String, base: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
    }
}
