import Foundation
import AVFoundation
import AudioToolbox

public enum LibraryScanner {
    public static let extensions: Set<String> = ["wav", "wave", "aif", "aiff", "caf", "mp3", "m4a", "flac"]
    public static func scan(source: LibrarySource, catalog: Catalog,
                            progress: @escaping @Sendable (ScanProgress) async -> Void) async throws {
        var report = ScanProgress()
        let root = URL(fileURLWithPath: source.path)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue,
              FileManager.default.isReadableFile(atPath: root.path) else {
            throw CatalogError(message: "\(source.name) is offline or unreadable. Reconnect it and rescan; its catalog is preserved.")
        }
        let existing = try await catalog.fingerprints(sourceID: source.id)
        let token = UUID().uuidString
        var traversalErrors: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
                if traversalErrors.count < 20 { traversalErrors.append("\(url.lastPathComponent): \(error.localizedDescription)") }; return true
            }) else { throw CatalogError(message: "Cannot enumerate \(source.name)") }
        var batch: [Sample] = []; var unchanged: [String] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            report.inspected += 1
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current {
                    report.skipped += 1; continue
                }
                let fingerprint = "\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                if existing[url.path] == fingerprint { unchanged.append(url.path); report.skipped += 1 }
                else {
                    let sample: Sample = try autoreleasepool {
                        let audio = try AVAudioFile(forReading: url)
                        let name = url.deletingPathExtension().lastPathComponent
                        let relativeFolder = String(url.deletingLastPathComponent().path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let folder = relativeFolder.isEmpty ? source.name : source.name + "/" + relativeFolder
                        let kind = Metadata.kind(name: name, folder: folder)
                        var sample = Sample(sourceID: source.id, path: url.path, name: name, folder: folder,
                            duration: Double(audio.length) / audio.processingFormat.sampleRate, sampleRate: audio.processingFormat.sampleRate,
                            channels: Int(audio.processingFormat.channelCount), bpm: Metadata.bpm(name, kind: kind), key: Metadata.key(name),
                            category: Metadata.category(name: name, folder: folder), fingerprint: fingerprint)
                        sample.kind = kind; sample.rootNote = Metadata.rootNote(name)
                        // Prefer filename values; use explicit labels in the closest folder as a fallback.
                        for component in relativeFolder.split(separator: "/").reversed() {
                            if sample.bpm == nil, let bpm = Metadata.bpm(String(component)) { sample.bpm = bpm; sample.metadataOrigin = "filename / folder labels" }
                            if sample.key == nil, let key = Metadata.key(String(component)) { sample.key = key; sample.rootNote = sample.rootNote ?? String(key.split(separator: " ")[0]); sample.metadataOrigin = "filename / folder labels" }
                        }
                        if let tempo = embeddedTempo(url), (30...300).contains(tempo) { sample.bpm = tempo; sample.metadataOrigin = "embedded tempo; filename key" }
                        return sample
                    }
                    batch.append(sample); report.indexed += 1
                }
            } catch {
                if report.errors.count < 20 { report.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            if batch.count + unchanged.count >= 64 {
                try await catalog.upsert(batch, seen: token); try await catalog.markSeen(paths: unchanged, token: token)
                batch.removeAll(keepingCapacity: true); unchanged.removeAll(keepingCapacity: true)
                await progress(report); await Task.yield()
            }
        }
        try Task.checkCancellation()
        try await catalog.upsert(batch, seen: token); try await catalog.markSeen(paths: unchanged, token: token)
        // Reconcile only after a clean traversal. Never erase annotations or delete audio.
        if traversalErrors.isEmpty && report.errors.isEmpty && FileManager.default.isReadableFile(atPath: root.path) {
            try await catalog.finishScan(sourceID: source.id, token: token)
        }
        report.errors.append(contentsOf: traversalErrors)
        report.finished = true; await progress(report)
    }
    private static func embeddedTempo(_ url: URL) -> Double? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return nil }
        defer { AudioFileClose(file) }
        var info: Unmanaged<CFDictionary>?; var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, &info) == noErr,
              let dictionary = info?.takeRetainedValue() as? [String: Any] else { return nil }
        if let number = dictionary[kAFInfoDictionary_Tempo as String] as? NSNumber { return number.doubleValue }
        return (dictionary[kAFInfoDictionary_Tempo as String] as? String).flatMap(Double.init)
    }
}

public enum Waveform {
    public static func read(url: URL, bins: Int = 180) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return [] }
        let count = max(1, bins)
        let frames = AVAudioFrameCount(min(1024, max(1, file.length / Int64(count))))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return [] }
        var peaks: [Float] = []
        for index in 0..<count {
            try Task.checkCancellation()
            file.framePosition = min(file.length - 1, Int64(Double(index) / Double(count) * Double(file.length)))
            try file.read(into: buffer, frameCount: frames)
            var peak: Float = 0
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channels[channel][frame])) }
                }
            }
            peaks.append(peak)
        }
        let maximum = peaks.max() ?? 1
        return peaks.map { $0 / max(maximum, 0.001) }
    }
}
