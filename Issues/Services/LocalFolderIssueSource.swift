import Foundation
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "IssueStore")

/// `IssueSource` backed by a local folder of `NNNN.md` files. Owns the
/// security-scoped resource access, the FSEvents watcher, and the per-reload
/// directory walk + parser + lint pass.
///
/// The logging category stays `IssueStore` so existing log-stream filters
/// continue to work after the refactor (#0077). Behavior is bit-for-bit
/// equivalent to the pre-refactor `IssueStore.start/stop/reload`.
final class LocalFolderIssueSource: IssueSource {
    nonisolated let folderURL: URL
    /// Security-scoped bookmark bytes captured at construction time. Held
    /// here (rather than re-derived from `folderURL`) so `IssueStore.folderId`
    /// stays stable across the lifetime of this source even if a fresh
    /// `bookmarkData(...)` call would produce different bytes for the same
    /// URL (#0082).
    let bookmarkData: Data?
    private(set) var issues: [Issue] = []
    private(set) var lintFindings: [LintFinding] = []
    private(set) var loadError: String?
    private(set) var folderInvalidated: Bool = false
    var onUpdate: ((any IssueSource) -> Void)?

    private var watcher: FolderWatcher?
    private var didStartAccess: Bool = false

    /// Decoded `<folderURL>/project.json`. Refreshed on every `reload()`.
    /// Missing/empty/malformed → nil; the FSEvents pass that runs on `.json`
    /// edits already coalesces into the same reload that re-reads the issues.
    private(set) var projectMetadata: ProjectMetadata?

    var displayName: String {
        // `project.json` with an empty `name` should fall back to the parent
        // folder name, same as if the field were missing (#0075 spec).
        if let name = projectMetadata?.name, !name.isEmpty { return name }
        return repoName
    }

    /// Repo-style label for log lines, e.g. `MyRepo` for `/path/to/MyRepo/issues`.
    var repoName: String {
        folderURL.deletingLastPathComponent().lastPathComponent
    }

    init(folderURL: URL, bookmarkData: Data? = nil) {
        self.folderURL = folderURL
        self.bookmarkData = bookmarkData
    }

    deinit {
        // Synchronous cleanup; SwiftUI lifetime ends here. Avoid touching
        // observable storage from deinit.
        if didStartAccess {
            folderURL.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Lifecycle

    func start() {
        didStartAccess = folderURL.startAccessingSecurityScopedResource()
        logger.notice("[\(self.repoName, privacy: .public)] start folder=\(self.folderURL.path, privacy: .public) scopedAccess=\(self.didStartAccess, privacy: .public)")
        reload()
        let repoName = self.repoName
        let watcher = FolderWatcher(
            onChange: { [weak self] in self?.reload() },
            onInvalidated: { [weak self] in
                logger.notice("[\(repoName, privacy: .public)] folder invalidated — clearing store")
                self?.handleInvalidated()
            }
        )
        watcher.start(url: folderURL)
        self.watcher = watcher
    }

    func stop() {
        logger.notice("[\(self.repoName, privacy: .public)] stop")
        watcher?.stop()
        watcher = nil
        if didStartAccess {
            folderURL.stopAccessingSecurityScopedResource()
            didStartAccess = false
        }
    }

    // MARK: - Loading

    func reload() {
        let started = Date()
        do {
            let fm = FileManager.default
            let entries = try fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            var parsed: [Issue] = []
            var skippedNames: [String] = []
            for url in entries {
                let name = url.lastPathComponent
                guard MarkdownIssueParser.filenameMatchesIssuePattern(name) else {
                    continue
                }
                do {
                    if let issue = try MarkdownIssueParser.parse(fileURL: url) {
                        parsed.append(issue)
                    } else {
                        skippedNames.append(name)
                    }
                } catch {
                    skippedNames.append(name)
                    logger.warning("[\(self.repoName, privacy: .public)] read \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            parsed.sort { $0.id < $1.id }
            let prevCount = self.issues.count
            self.issues = parsed
            self.lintFindings = LintRunner.run(folderURL: folderURL, parsedIssues: parsed)
            self.projectMetadata = Self.readProjectMetadata(folderURL: folderURL, repoName: self.repoName)
            self.loadError = nil
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            logger.notice("[\(self.repoName, privacy: .public)] reload parsed=\(parsed.count, privacy: .public) skipped=\(skippedNames.count, privacy: .public) lint=\(self.lintFindings.count, privacy: .public) wasCount=\(prevCount, privacy: .public) elapsedMs=\(ms, privacy: .public)")
            if !skippedNames.isEmpty {
                logger.warning("[\(self.repoName, privacy: .public)] skipped files: \(skippedNames.joined(separator: ", "), privacy: .public)")
            }
            onUpdate?(self)
        } catch {
            self.loadError = "Failed to read folder: \(error.localizedDescription)"
            logger.error("[\(self.repoName, privacy: .public)] reload failed: \(error.localizedDescription, privacy: .public)")
            // Preserve `issues` and `lintFindings` from the prior successful
            // reload so the host's snapshot baseline doesn't shift on failure.
            // We still notify so the host can mirror `loadError`.
            onUpdate?(self)
        }
    }

    private func handleInvalidated() {
        folderInvalidated = true
        onUpdate?(self)
    }

    /// Reads `<folderURL>/project.json`. Returns nil for missing files; logs
    /// a warning and returns nil for malformed JSON or unreadable files.
    /// Schema is owned by the IssuesSkill (see `RemoteAccess.md`); unknown
    /// fields decode as nil via `ProjectMetadata`.
    static func readProjectMetadata(folderURL: URL, repoName: String) -> ProjectMetadata? {
        let url = folderURL.appendingPathComponent("project.json")
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            logger.warning("[\(repoName, privacy: .public)] project.json read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(ProjectMetadata.self, from: data)
        } catch {
            logger.warning("[\(repoName, privacy: .public)] project.json malformed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
