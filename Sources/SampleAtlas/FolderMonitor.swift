import Foundation
import CoreServices

/// Recursive filesystem events only signal that a scan is needed. The scanner's
/// fingerprints decide which audio metadata needs refreshing.
@MainActor
final class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let changed: () -> Void

    init(paths: [String], changed: @escaping () -> Void) {
        self.changed = changed
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            MainActor.assumeIsolated {
                Unmanaged<FolderMonitor>.fromOpaque(info).takeUnretainedValue().changed()
            }
        }, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot))
        if let stream { FSEventStreamSetDispatchQueue(stream, .main); FSEventStreamStart(stream) }
    }
    deinit {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
    }
}
