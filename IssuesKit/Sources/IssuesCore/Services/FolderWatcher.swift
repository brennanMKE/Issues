import Foundation
import os.log
import Watcher

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "FolderWatcher")

/// Thin adapter around `Watcher.Session` that exposes the existing
/// callback-based API used by `IssueStore`. The package handles FSEventStream
/// plumbing, throttling, and root-invalidation; we just translate events into
/// "rescan now" or "the folder is gone."
public final class FolderWatcher {
    private var task: Task<Void, Never>?
    private let onChange: @MainActor () -> Void
    private let onInvalidated: @MainActor () -> Void

    public init(
        onChange: @escaping @MainActor () -> Void,
        onInvalidated: @escaping @MainActor () -> Void
    ) {
        self.onChange = onChange
        self.onInvalidated = onInvalidated
    }

    deinit {
        task?.cancel()
    }

    public func start(url: URL) {
        stop()
        Watcher.logSubsystem = Logging.subsystem

        var options = Watcher.Options()
        options.throttle = .milliseconds(150)
        options.scope = .all
        options.depth = .infinite

        let onChange = self.onChange
        let onInvalidated = self.onInvalidated

        task = Task {
            do {
                let session = try await Watcher.Session(path: url, options: options)
                logger.notice("watching \(url.path, privacy: .public)")
                for try await event in session.events {
                    if Task.isCancelled { break }
                    logger.debug("event \(String(describing: event), privacy: .public)")
                    onChange()
                }
                logger.notice("stream finished")
            } catch is CancellationError {
                logger.notice("cancelled")
            } catch let error as WatcherError {
                logger.notice("torn down: \(String(describing: error), privacy: .public)")
                onInvalidated()
            } catch {
                logger.error("unexpected error: \(error.localizedDescription, privacy: .public)")
                onInvalidated()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
