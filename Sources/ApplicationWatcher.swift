import Foundation
import CoreServices

/// Main-queue FSEvents; one debounced rescan after an install burst, not one scan per file.
@MainActor final class ApplicationWatcher {
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private let changed: () -> Void
    private let watchedPaths: [String]
    init(paths: [String], changed: @escaping () -> Void) {
        self.changed = changed
        self.watchedPaths = paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        // Watch an existing parent if ~/Applications has not been created yet.
        let roots = Set(watchedPaths.map { path in
            var url = URL(fileURLWithPath: path)
            while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
            return url.path
        })
        stream = FSEventStreamCreate(nil, { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            MainActor.assumeIsolated {
                let watcher = Unmanaged<ApplicationWatcher>.fromOpaque(info).takeUnretainedValue()
                if paths.contains(where: { event in watcher.watchedPaths.contains { event == $0 || event.hasPrefix($0 + "/") } }) {
                    watcher.schedule()
                }
            }
        }, &context, Array(roots) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.6,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) { stop() }
        }
    }
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.changed() } }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    func stop() {
        pending?.cancel(); pending = nil
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }
}
