import Testing
import Foundation
@testable import IssuesCore

/// Tests for `LintRunner.run(folderURL:parsedIssues:)`. Each test builds a
/// temp folder with a small fixture set, invokes the runner, asserts on the
/// returned `[LintFinding]`, and tears the folder down. Mirrors the layout
/// the IssuesSkill / Issues.app produces in the wild.
@MainActor
struct LintRunnerTests {

    // MARK: - Fixture helpers

    /// Creates a fresh, unique scratch folder for one test. Caller is
    /// responsible for cleanup; tests use `defer { try? FileManager...remove }`.
    private static func makeScratchFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LintRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func write(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func makeIssue(
        id: String,
        fileURL: URL,
        statusRaw: String = "open",
        status: IssueStatus = .open,
        modifiedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> IssuesCore.Issue {
        IssuesCore.Issue(
            id: id,
            title: "Issue \(id)",
            status: status,
            statusRaw: statusRaw,
            module: "State",
            platform: "macOS",
            firstSeen: nil,
            firstSeenRaw: "",
            closed: nil,
            closedRaw: "",
            description: "",
            fileURL: fileURL,
            modifiedAt: modifiedAt,
            hasAttachments: false
        )
    }

    /// A minimal valid issue file body for the given id/title.
    private static func validIssueBody(id: String, status: String = "open") -> String {
        """
        # \(id) \u{2014} Title \(id)

        | | |
        |---|---|
        | **Status** | \(status) |
        | **Module** | State |
        | **Platform** | macOS |
        | **First seen** | 2026-05-05 |

        ## Description

        x
        """
    }

    // MARK: - Parse-failure findings

    @Test func parseFailureForMissingTitle() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("0001.md")
        // Body has no `# NNNN — Title` heading.
        try Self.write("""
        Just some text, no title heading.

        | | |
        |---|---|
        | **Status** | open |
        """, to: file)

        let findings = LintRunner.run(folderURL: folder, parsedIssues: [])

        let parseFailures = findings.filter {
            if case .parseFailure = $0.kind { return true }
            return false
        }
        #expect(parseFailures.count == 1)
        if case .parseFailure(let reason) = parseFailures.first?.kind {
            #expect(reason.contains("title") || reason.contains("em-dash"))
        } else {
            #expect(Bool(false), "Expected a parseFailure finding")
        }
    }

    @Test func parseFailureForMissingStatus() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("0002.md")
        // Has title but no Status row.
        try Self.write("""
        # 0002 \u{2014} Title without status row

        | | |
        |---|---|
        | **Module** | State |

        ## Description

        x
        """, to: file)

        let findings = LintRunner.run(folderURL: folder, parsedIssues: [])

        let parseFailures = findings.filter {
            if case .parseFailure = $0.kind { return true }
            return false
        }
        #expect(parseFailures.count == 1)
        if case .parseFailure(let reason) = parseFailures.first?.kind {
            #expect(reason.lowercased().contains("status"))
        } else {
            #expect(Bool(false), "Expected a parseFailure finding")
        }
    }

    /// `.filenameMismatch` is unreachable in the runner's current flow because
    /// the filename gate strips non-matching files before the parser ever sees
    /// them. The runner explicitly comments this — we exercise the surrounding
    /// gate here instead: a non-matching filename produces no finding.
    @Test func filenameMismatchIsFilteredBeforeParser() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Doesn't match `^\d{4}\.md$`.
        try Self.write("anything", to: folder.appendingPathComponent("not-an-issue.md"))

        let findings = LintRunner.run(folderURL: folder, parsedIssues: [])
        #expect(findings.isEmpty)
    }

    // MARK: - Orphan-folder findings

    @Test func orphanFolderFiresWhenSiblingMdMissing() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // `0042/` exists but `0042.md` does not.
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("0042"),
            withIntermediateDirectories: true
        )

        let findings = LintRunner.run(folderURL: folder, parsedIssues: [])
        let orphans = findings.filter { $0.kind == .orphanFolder }
        #expect(orphans.count == 1)
        #expect(orphans.first?.fileURL.lastPathComponent == "0042")
    }

    @Test func orphanFolderDoesNotFireWhenSiblingMdExists() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("0042"),
            withIntermediateDirectories: true
        )
        let mdURL = folder.appendingPathComponent("0042.md")
        try Self.write(Self.validIssueBody(id: "0042"), to: mdURL)

        let parsed = [Self.makeIssue(id: "0042", fileURL: mdURL)]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)
        let orphans = findings.filter { $0.kind == .orphanFolder }
        #expect(orphans.isEmpty)
    }

    // MARK: - Missing-attachment findings

    @Test func missingAttachmentFiresForLocalReference() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdURL = folder.appendingPathComponent("0010.md")
        let body = """
        # 0010 \u{2014} Has missing image

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | State |
        | **Platform** | macOS |
        | **First seen** | 2026-05-05 |

        ## Description

        ![missing screenshot](0010/missing.png)
        """
        try Self.write(body, to: mdURL)

        let parsed = [Self.makeIssue(id: "0010", fileURL: mdURL)]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)

        let missing = findings.filter {
            if case .missingAttachment = $0.kind { return true }
            return false
        }
        #expect(missing.count == 1)
        if case .missingAttachment(let path) = missing.first?.kind {
            #expect(path == "0010/missing.png")
        }
    }

    @Test func missingAttachmentDoesNotFireForExternalURLs() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdURL = folder.appendingPathComponent("0011.md")
        let body = """
        # 0011 \u{2014} External image

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | State |
        | **Platform** | macOS |
        | **First seen** | 2026-05-05 |

        ## Description

        ![remote](https://example.com/foo.png)
        ![data](data:image/png;base64,abc)
        """
        try Self.write(body, to: mdURL)

        let parsed = [Self.makeIssue(id: "0011", fileURL: mdURL)]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)

        let missing = findings.filter {
            if case .missingAttachment = $0.kind { return true }
            return false
        }
        #expect(missing.isEmpty)
    }

    @Test func missingAttachmentSkipsImagesInsideCodeBlocks() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdURL = folder.appendingPathComponent("0012.md")
        let body = """
        # 0012 \u{2014} Documents the syntax

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | State |
        | **Platform** | macOS |
        | **First seen** | 2026-05-05 |

        ## Description

        Use the syntax `![cap](NNNN/foo.png)` to attach images.

        ```markdown
        ![cap](0012/example.png)
        ```
        """
        try Self.write(body, to: mdURL)

        let parsed = [Self.makeIssue(id: "0012", fileURL: mdURL)]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)

        let missing = findings.filter {
            if case .missingAttachment = $0.kind { return true }
            return false
        }
        #expect(missing.isEmpty)
    }

    @Test func missingAttachmentDoesNotFireWhenFileExists() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdURL = folder.appendingPathComponent("0013.md")
        let attachmentDir = folder.appendingPathComponent("0013", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        let imageURL = attachmentDir.appendingPathComponent("present.png")
        // Empty file is sufficient — runner only checks existence.
        try Data().write(to: imageURL)

        let body = """
        # 0013 \u{2014} Has present image

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | State |
        | **Platform** | macOS |
        | **First seen** | 2026-05-05 |

        ## Description

        ![present](0013/present.png)
        """
        try Self.write(body, to: mdURL)

        let parsed = [Self.makeIssue(id: "0013", fileURL: mdURL)]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)
        let missing = findings.filter {
            if case .missingAttachment = $0.kind { return true }
            return false
        }
        #expect(missing.isEmpty)
    }

    // MARK: - Unknown-status findings

    @Test func unknownStatusFiresForNonCanonicalRaw() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdURL = folder.appendingPathComponent("0020.md")
        let body = """
        # 0020 \u{2014} Underscore status

        | | |
        |---|---|
        | **Status** | in_progress |
        | **Module** | State |
        | **Platform** | macOS |
        | **First seen** | 2026-05-05 |

        ## Description

        x
        """
        try Self.write(body, to: mdURL)

        let parsed = [Self.makeIssue(
            id: "0020",
            fileURL: mdURL,
            statusRaw: "in_progress",
            status: .open // folds to .open since not canonical
        )]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)
        let unknown = findings.filter {
            if case .unknownStatus = $0.kind { return true }
            return false
        }
        #expect(unknown.count == 1)
        if case .unknownStatus(let raw) = unknown.first?.kind {
            #expect(raw == "in_progress")
        }
    }

    @Test func unknownStatusDoesNotFireForCanonicalInProgress() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdURL = folder.appendingPathComponent("0021.md")
        try Self.write(Self.validIssueBody(id: "0021", status: "in-progress"), to: mdURL)

        let parsed = [Self.makeIssue(
            id: "0021",
            fileURL: mdURL,
            statusRaw: "in-progress",
            status: .inProgress
        )]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)
        let unknown = findings.filter {
            if case .unknownStatus = $0.kind { return true }
            return false
        }
        #expect(unknown.isEmpty)
    }

    // MARK: - Duplicate-id findings

    @Test func duplicateIDFiresOncePerExtraDuplicate() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // The on-disk filename gate prevents same-id collisions in practice,
        // so we synthesize the duplicates directly in `parsedIssues` to
        // exercise the runner's grouping logic. The folder need not contain
        // real fixture files for this branch — `parsedIssues` is the only
        // input.
        let primaryURL = folder.appendingPathComponent("a/0030.md")
        let dupURL1 = folder.appendingPathComponent("b/0030.md")
        let dupURL2 = folder.appendingPathComponent("c/0030.md")
        let parsed = [
            Self.makeIssue(id: "0030", fileURL: primaryURL),
            Self.makeIssue(id: "0030", fileURL: dupURL1),
            Self.makeIssue(id: "0030", fileURL: dupURL2),
        ]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)
        let dupes = findings.filter {
            if case .duplicateID = $0.kind { return true }
            return false
        }
        // 3 issues sharing an id → 2 findings (one per *extra* duplicate).
        #expect(dupes.count == 2)
        // Primary (alphabetically smallest path) is never the subject; it's
        // the `otherFileURL`.
        for finding in dupes {
            #expect(finding.fileURL != primaryURL)
            if case .duplicateID(let other) = finding.kind {
                #expect(other == primaryURL)
            }
        }
    }

    @Test func duplicateIDDoesNotFireForUniqueIDs() throws {
        let folder = try Self.makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let mdA = folder.appendingPathComponent("0031.md")
        let mdB = folder.appendingPathComponent("0032.md")
        try Self.write(Self.validIssueBody(id: "0031"), to: mdA)
        try Self.write(Self.validIssueBody(id: "0032"), to: mdB)

        let parsed = [
            Self.makeIssue(id: "0031", fileURL: mdA),
            Self.makeIssue(id: "0032", fileURL: mdB),
        ]
        let findings = LintRunner.run(folderURL: folder, parsedIssues: parsed)
        let dupes = findings.filter {
            if case .duplicateID = $0.kind { return true }
            return false
        }
        #expect(dupes.isEmpty)
    }
}
