import Foundation
import CoreServices
import os.log

nonisolated private let logger = Logger(subsystem: Logging.subsystem, category: "FolderWatcher")

/// Watches a directory for changes — including in-place modifications to
/// existing files within it — using FSEventStream. A 150ms debounce coalesces
/// bursts of events.
///
/// Why FSEventStream instead of DispatchSource on a directory FD:
/// `DispatchSource.makeFileSystemObjectSource` watching a directory FD only
/// reports events on the directory's own inode — entries added, removed,
/// renamed, attribs changed. An in-place save to an existing file inside the
/// directory mutates only that file's inode, so the directory FD never fires.
/// FSEventStream with `kFSEventStreamCreateFlagFileEvents` reports per-file
/// events for the watched tree, which is what we need.
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var debounceItem: DispatchWorkItem?
    private let queue: DispatchQueue
    private let onChange: @MainActor () -> Void
    private let onInvalidated: @MainActor () -> Void

    init(
        onChange: @escaping @MainActor () -> Void,
        onInvalidated: @escaping @MainActor () -> Void
    ) {
        self.queue = DispatchQueue(label: "co.sstools.Issues.FolderWatcher", qos: .utility)
        self.onChange = onChange
        self.onInvalidated = onInvalidated
    }

    deinit {
        stop()
    }

    func start(url: URL) {
        stop()

        let path = url.path(percentEncoded: false)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
            | kFSEventStreamCreateFlagUseCFTypes
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            // We requested UseCFTypes, so eventPaths is a CFArrayRef of CFStringRef.
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let paths = (cfArray as NSArray).compactMap { $0 as? String }
            watcher.handleEvents(count: numEvents, paths: paths, flags: eventFlags)
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            flags
        ) else {
            logger.error("FSEventStreamCreate returned nil for \(path, privacy: .public)")
            Task { @MainActor in self.onInvalidated() }
            return
        }

        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            logger.error("FSEventStreamStart returned false for \(path, privacy: .public)")
            Task { @MainActor in self.onInvalidated() }
            return
        }
        self.stream = s
        logger.notice("watching \(path, privacy: .public)")
    }

    func stop() {
        debounceItem?.cancel()
        debounceItem = nil
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        logger.notice("stopped")
    }

    private func handleEvents(
        count: Int,
        paths: [String],
        flags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        var rootChanged = false
        var summaries: [String] = []
        for i in 0..<count {
            let flag = flags[i]
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                rootChanged = true
            }
            let name = paths.indices.contains(i)
                ? (paths[i] as NSString).lastPathComponent
                : "?"
            summaries.append("\(name)[\(Self.describe(flag))]")
        }
        logger.debug("events count=\(count, privacy: .public) \(summaries.joined(separator: " "), privacy: .public)")
        if rootChanged {
            logger.notice("folder invalidated (root changed)")
            Task { @MainActor in self.onInvalidated() }
            return
        }
        scheduleDebouncedReload()
    }

    private func scheduleDebouncedReload() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            logger.notice("debounce fired — invoking onChange")
            Task { @MainActor in self.onChange() }
        }
        debounceItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }

    private static func describe(_ flag: FSEventStreamEventFlags) -> String {
        var parts: [String] = []
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 { parts.append("created") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 { parts.append("removed") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 { parts.append("renamed") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 { parts.append("modified") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod) != 0 { parts.append("inodeMeta") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod) != 0 { parts.append("finderInfo") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner) != 0 { parts.append("owner") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod) != 0 { parts.append("xattr") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 { parts.append("file") }
        if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 { parts.append("dir") }
        return parts.isEmpty ? "(none)" : parts.joined(separator: ",")
    }
}
