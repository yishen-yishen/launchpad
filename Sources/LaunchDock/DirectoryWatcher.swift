import Foundation
import CoreServices

@MainActor final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private var debounce: Task<Void, Never>?
    var changed: (() -> Void)?
    func start(paths: [String]) {
        stop()
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated { Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().schedule() }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.8, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        if let stream { FSEventStreamSetDispatchQueue(stream, DispatchQueue.main); FSEventStreamStart(stream) }
    }
    private func schedule() {
        debounce?.cancel()
        debounce = Task { do { try await Task.sleep(for: .milliseconds(800)); changed?() } catch {} }
    }
    func stop() { debounce?.cancel(); if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }; stream = nil }
}
