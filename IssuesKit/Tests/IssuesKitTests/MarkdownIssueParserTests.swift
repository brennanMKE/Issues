import Testing
import Foundation
@testable import IssuesCore

struct MarkdownIssueParserTests {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    @Test func parsesEmDashTitle() throws {
        let body = """
        # 0001 \u{2014} Account session not persisted across app launches

        | | |
        |---|---|
        | **Status** | closed |
        | **Module** | BlueskyDataStore |
        | **Platform** | macOS |
        | **First seen** | 2026-04-29 |
        | **Closed** | 2026-04-29 |

        ## Description

        Some description text.
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0001.md"), contents: body)
        try #require(issue != nil)
        let resolved = issue!
        #expect(resolved.id == "0001")
        #expect(resolved.title == "Account session not persisted across app launches")
        #expect(resolved.status == .closed)
        #expect(resolved.module == "BlueskyDataStore")
        #expect(resolved.platform == "macOS")
        #expect(resolved.firstSeenRaw == "2026-04-29")
        #expect(resolved.firstSeen != nil)
        #expect(resolved.closedRaw == "2026-04-29")
        #expect(resolved.closed != nil)
        #expect(resolved.description == "Some description text.")
    }

    @Test func handlesMissingClosed() throws {
        let body = """
        # 0011 \u{2014} Module 1 gate: session restore not validated

        | | |
        |---|---|
        | **Status** | resolved |
        | **Module** | BlueskyAuth / BlueskyDataStore |
        | **Platform** | All |
        | **First seen** | 2026-04-29 |

        ## Description

        Text here.
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0011.md"), contents: body)
        try #require(issue != nil)
        let resolved = issue!
        #expect(resolved.closedRaw == "")
        #expect(resolved.closed == nil)
        #expect(resolved.firstSeen != nil)
    }

    @Test func handlesMissingDescription() throws {
        let body = """
        # 0050 \u{2014} Title without description

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | Core |
        | **Platform** | iOS |
        | **First seen** | 2026-04-30 |

        ## Steps to reproduce

        1. Do thing.
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0050.md"), contents: body)
        try #require(issue != nil)
        #expect(issue!.description == "")
    }

    @Test func splitsMultiModule() throws {
        let body = """
        # 0011 \u{2014} Multi-module issue

        | | |
        |---|---|
        | **Status** | resolved |
        | **Module** | BlueskyAuth / BlueskyDataStore |
        | **Platform** | All |
        | **First seen** | 2026-04-29 |

        ## Description

        x
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0011.md"), contents: body)!
        #expect(issue.modules == ["BlueskyAuth", "BlueskyDataStore"])
        #expect(issue.primaryModule == "BlueskyAuth")
    }

    @Test func statusCaseFolding() throws {
        let body = """
        # 0007 \u{2014} Mixed case status

        | | |
        |---|---|
        | **Status** | In Progress |
        | **Module** | Foo |
        | **Platform** | iOS |
        | **First seen** | 2026-04-30 |

        ## Description

        x
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0007.md"), contents: body)!
        #expect(issue.status == .inProgress)
    }

    @Test func malformedDatesYieldNil() throws {
        let body = """
        # 0008 \u{2014} Malformed date

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | Foo |
        | **Platform** | iOS |
        | **First seen** | not-a-date |
        | **Closed** | also-bad |

        ## Description

        x
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0008.md"), contents: body)!
        #expect(issue.firstSeenRaw == "not-a-date")
        #expect(issue.firstSeen == nil)
        #expect(issue.closedRaw == "also-bad")
        #expect(issue.closed == nil)
    }

    @Test func descriptionPreservesInternalNewlines() throws {
        let body = """
        # 0034 \u{2014} Numbered list issue

        | | |
        |---|---|
        | **Status** | open |
        | **Module** | Foo |
        | **Platform** | iOS |
        | **First seen** | 2026-04-30 |

        ## Description

        Line one.
        Line two.

        ## Steps

        x
        """
        let issue = MarkdownIssueParser.parse(fileURL: url("0034.md"), contents: body)!
        #expect(issue.description.contains("Line one."))
        #expect(issue.description.contains("Line two."))
        #expect(issue.description.contains("\n"))
    }

    @Test func rejectsNonMatchingFilename() {
        let body = "# 0001 \u{2014} Title"
        #expect(MarkdownIssueParser.parse(fileURL: url("Issues.md"), contents: body) == nil)
        #expect(MarkdownIssueParser.parse(fileURL: url("generate.py"), contents: body) == nil)
        #expect(MarkdownIssueParser.parse(fileURL: url("123.md"), contents: body) == nil)
    }

    @Test func issueStatusInitFromRaw() {
        #expect(IssueStatus(raw: "Open") == .open)
        #expect(IssueStatus(raw: "in-progress") == .inProgress)
        #expect(IssueStatus(raw: "In Progress") == .inProgress)
        #expect(IssueStatus(raw: "RESOLVED") == .resolved)
        #expect(IssueStatus(raw: "garbage") == .open)
    }
}
