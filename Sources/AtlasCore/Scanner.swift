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
        let files = try listAudioFiles(under: root.path, errors: &traversalErrors)
        var batch: [Sample] = []; var unchanged: [String] = []
        for file in files {
            try Task.checkCancellation()
            let url = URL(fileURLWithPath: file.path)
            report.inspected += 1
            do {
                let fingerprint = "\(file.size):\(file.modified)"
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
                        if sample.bpm == nil, let tempo = embeddedTempo(url), (30...300).contains(tempo) {
                            sample.bpm = tempo; sample.metadataOrigin = "embedded tempo; filename pitch"
                        }
                        // Prefer filename values; use explicit labels in the closest folder as a fallback.
                        for component in relativeFolder.split(separator: "/").reversed() {
                            if sample.bpm == nil, let bpm = Metadata.bpm(String(component)) { sample.bpm = bpm; sample.metadataOrigin = "filename / folder labels" }
                            if sample.key == nil, sample.rootNote == nil, let key = Metadata.key(String(component)) { sample.key = key; sample.rootNote = String(key.split(separator: " ")[0]); sample.metadataOrigin = "filename / folder labels" }
                        }
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
    struct AudioFile { let path: String; let size: Int64; let modified: Double }
    /// opendir/readdir/lstat rather than FileManager's URL enumerator: on exFAT volumes the URL
    /// attribute path costs ~8 ms per file, which turned a 10k-file launch scan into over a minute.
    /// Hidden entries (including iCloud placeholders), symbolic links and package bundles are skipped.
    static func listAudioFiles(under directory: String, errors: inout [String]) throws -> [AudioFile] {
        guard let dir = opendir(directory) else {
            if errors.count < 20 { errors.append("\(URL(fileURLWithPath: directory).lastPathComponent): \(String(cString: strerror(errno)))") }
            return []
        }
        var files: [AudioFile] = []; var subdirectories: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
            if name.hasPrefix(".") { continue }
            let path = directory + "/" + name
            let isAudio = extensions.contains((name as NSString).pathExtension.lowercased())
            if entry.pointee.d_type == UInt8(DT_REG) && !isAudio { continue }
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: if !isPackage(path) { subdirectories.append(path) }
            case S_IFREG where isAudio:
                files.append(AudioFile(path: path, size: Int64(info.st_size), modified: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9))
            default: continue
            }
        }
        closedir(dir)
        for subdirectory in subdirectories.sorted() {
            try Task.checkCancellation()
            files += try listAudioFiles(under: subdirectory, errors: &errors)
        }
        return files
    }
    /// isPackageKey alone is cheap even on FSKit volumes; only the size/date keys were slow.
    private static func isPackage(_ path: String) -> Bool {
        (try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
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
