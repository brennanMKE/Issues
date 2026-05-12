import Foundation
import SwiftUI
import AppKit
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "ReportGenerator")

/// Generates a self-contained markdown status report into
/// `<watched-folder>/reports/` (#0064). The directory is created on first
/// use; existing reports are never overwritten — same-day generations get a
/// numeric suffix.
///
/// **Write-scope constraint.** The app stays strictly read-only for
/// `NNNN.md` files (Claude Code subagents own those). This generator only
/// writes under `<folder>/reports/`; the runtime guard in `writeReport`
/// catches any future regression that tries to write elsewhere.
@MainActor
enum ReportGenerator {

    /// Path component the generator is allowed to write under, relative to
    /// the watched folder. Enforced at runtime so a regression can't
    /// silently start writing into the issue source tree.
    private static let reportsSubdirectory = "reports"

    enum ReportGeneratorError: Error, Equatable {
        /// Writer tried to land a file outside `<folder>/reports/`. Should
        /// be unreachable; surfaced for the assertion path.
        case writeScopeViolation
        case ioError(String)
    }

    static func generate(for store: IssueStore, now: Date = Date()) throws -> URL {
        let folder = store.folderURL
        let reportsDir = folder.appendingPathComponent(reportsSubdirectory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        } catch {
            throw ReportGeneratorError.ioError("create reports dir: \(error.localizedDescription)")
        }

        let baseName = "report-\(Self.filenameDate(now))"
        let outURL = Self.nextAvailableURL(in: reportsDir, base: baseName, ext: "md")
        // Render the status donut PNG first so the markdown can reference
        // it inline. The donut name is derived from the markdown
        // filename's stem so a same-day re-run pairs `-2` etc.
        let donutURL = outURL.deletingPathExtension().appendingPathExtension("png")
        let donutName = donutURL.lastPathComponent
        let didRenderDonut = (try? Self.writeStatusDonutPNG(
            counts: store.statusCounts,
            to: donutURL,
            expectedDirectory: reportsDir
        )) != nil && store.issues.count > 0
        let body = Self.buildBody(
            store: store,
            folder: folder,
            now: now,
            donutImage: didRenderDonut ? donutName : nil
        )
        try Self.writeReport(body, to: outURL, expectedDirectory: reportsDir)
        logger.notice("report written path=\(outURL.path, privacy: .public) issues=\(store.issues.count, privacy: .public) donut=\(didRenderDonut, privacy: .public)")
        return outURL
    }

    // MARK: - Body

    /// Pure renderer — exposed `internal` so unit tests can drive it with a
    /// fixed `Date` and reproducible store contents.
    static func buildBody(store: IssueStore, folder: URL, now: Date, donutImage: String? = nil) -> String {
        var lines: [String] = []
        let title = store.displayName.isEmpty ? store.folderURL.lastPathComponent : store.displayName
        lines.append("# \(title) — Status report")
        lines.append("")
        lines.append("_Generated: \(Self.fullTimestamp(now))_")
        lines.append("_Folder: \(folder.path)_")
        lines.append("")
        if let donutImage {
            lines.append("![Status snapshot](\(donutImage))")
            lines.append("")
        }

        let counts = store.statusCounts
        let total = store.issues.count
        lines.append("## Summary")
        lines.append("")
        lines.append("- **Total issues:** \(total)")
        let statusLine = IssueStatus.displayOrder
            .map { "**\($0.displayName):** \(counts[$0, default: 0])" }
            .joined(separator: " · ")
        lines.append("- \(statusLine)")
        lines.append("- **Lint findings:** \(store.lintFindings.count)")
        lines.append("")

        lines.append("## Open issues")
        lines.append("")
        let openish = store.issues.filter { $0.status == .open || $0.status == .inProgress }.sorted { $0.id < $1.id }
        if openish.isEmpty {
            lines.append("No issues yet." )
        } else {
            lines.append("| # | Title | Module | Platform | Filed |")
            lines.append("|---|-------|--------|----------|-------|")
            for issue in openish {
                let filed = issue.firstSeenRaw.isEmpty ? "—" : issue.firstSeenRaw
                let module = issue.module.isEmpty ? "—" : issue.module
                let platform = issue.platform.isEmpty ? "—" : issue.platform
                lines.append("| \(issue.id) | \(escapePipe(issue.title)) | \(escapePipe(module)) | \(escapePipe(platform)) | \(filed) |")
            }
        }
        lines.append("")

        // Recent activity — strategy 2 (mtime + status) per spec.
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        let recent = store.issues
            .filter { $0.modifiedAt >= cutoff }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        if !recent.isEmpty {
            lines.append("## Recent activity")
            lines.append("")
            lines.append("Last 14 days, sorted newest first:")
            lines.append("")
            for issue in recent {
                let day = Self.shortDate(issue.modifiedAt)
                let kind = Self.activityKind(for: issue)
                lines.append("- **\(day)** — #\(issue.id) \(kind)")
            }
            lines.append("")
        }

        if !store.lintFindings.isEmpty {
            lines.append("## Lint findings")
            lines.append("")
            for finding in store.lintFindings {
                lines.append("- \(finding.summary)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Renders the status donut (#0065) and writes a PNG next to the
    /// markdown. Returns nothing on success; throws if the renderer can't
    /// produce a bitmap or the file write fails. Same write-scope guard
    /// as the markdown writer.
    @discardableResult
    static func writeStatusDonutPNG(counts: [IssueStatus: Int], to url: URL, expectedDirectory: URL) throws -> URL {
        // Empty / all-zero counts → no PNG (the report already covers
        // the empty case in prose).
        let total = counts.values.reduce(0, +)
        guard total > 0 else { throw ReportGeneratorError.ioError("no issues to render") }

        let renderer = ImageRenderer(content: StatusDonutView(counts: counts))
        renderer.scale = 2
        guard let nsImage = renderer.nsImage else {
            throw ReportGeneratorError.ioError("ImageRenderer returned nil")
        }
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ReportGeneratorError.ioError("png encode failed")
        }

        let resolvedTarget = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedExpected = expectedDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedTarget == resolvedExpected else {
            assertionFailure("ReportGenerator tried to write PNG outside reports/: \(url.path)")
            throw ReportGeneratorError.writeScopeViolation
        }
        do {
            try png.write(to: url)
        } catch {
            throw ReportGeneratorError.ioError("png write: \(error.localizedDescription)")
        }
        return url
    }

    private static func writeReport(_ body: String, to url: URL, expectedDirectory: URL) throws {
        // Runtime guard — keep the write scope explicit so a regression
        // can't silently start writing outside `reports/`. (Belt-and-
        // suspenders with the convention that nothing else in the app
        // writes to the watched folder.)
        let resolvedTarget = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedExpected = expectedDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard resolvedTarget == resolvedExpected else {
            assertionFailure("ReportGenerator tried to write outside reports/: \(url.path)")
            throw ReportGeneratorError.writeScopeViolation
        }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ReportGeneratorError.ioError(error.localizedDescription)
        }
    }

    private static func nextAvailableURL(in dir: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var counter = 2
        while true {
            candidate = dir.appendingPathComponent("\(base)-\(counter).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    private static func filenameDate(_ now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = .current
        let raw = formatter.string(from: now)
        return raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func fullTimestamp(_ now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: now)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func activityKind(for issue: Issue) -> String {
        if issue.closed != nil {
            return "(\(issue.status.displayName.lowercased())) — \(issue.title)"
        }
        return "(\(issue.status.displayName.lowercased())) — \(issue.title)"
    }

    private static func escapePipe(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
