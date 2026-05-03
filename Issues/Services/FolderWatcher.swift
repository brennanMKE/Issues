import Foundation
import Darwin

/// Watches a single directory for changes. Coalesces bursts of events using
/// a 150ms debounce.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
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

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            Task { @MainActor in self.onInvalidated() }
            return
        }
        self.fileDescriptor = fd

        let mask: DispatchSource.FileSystemEvent = [.write, .delete, .rename, .extend, .attrib]
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: mask,
            queue: queue
        )

        src.setEventHandler { [weak self] in
            guard let self else { return }
            let event = src.data
            if event.contains(.delete) || event.contains(.rename) {
                Task { @MainActor in self.onInvalidated() }
                return
            }
            self.scheduleDebouncedReload()
        }

        src.setCancelHandler { [fd] in
            close(fd)
        }

        self.source = src
        src.resume()
    }

    func stop() {
        debounceItem?.cancel()
        debounceItem = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func scheduleDebouncedReload() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.onChange() }
        }
        debounceItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: item)
    }
}
