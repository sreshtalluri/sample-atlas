import Foundation

public struct LibrarySource: Identifiable, Sendable {
    public var id: Int64
    public var path: String
    public var name: String
    public var bookmark: Data?
    public init(id: Int64, path: String, name: String, bookmark: Data? = nil) {
        self.id = id; self.path = path; self.name = name; self.bookmark = bookmark
    }
}

public struct Sample: Identifiable, Sendable, Hashable {
    public var id: Int64 = 0
    public var sourceID: Int64
    public var path: String
    public var name: String
    public var folder: String
    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
    public var bpm: Double?
    public var key: String?
    public var category: String
    public var tags: String
    public var kind: String = "Unknown"
    public var rootNote: String?
    public var favorite: Bool = false
    public var available: Bool = true
    public var fingerprint: String
    public var metadataOrigin: String = "filename"
    public var url: URL { URL(fileURLWithPath: path) }
    public init(sourceID: Int64, path: String, name: String, folder: String = "", duration: Double = 0,
                sampleRate: Double = 44100, channels: Int = 2, bpm: Double? = nil, key: String? = nil,
                category: String = "Other", tags: String = "", fingerprint: String = "") {
        self.sourceID = sourceID; self.path = path; self.name = name; self.folder = folder
        self.duration = duration; self.sampleRate = sampleRate; self.channels = channels
        self.bpm = bpm; self.key = key; self.category = category; self.tags = tags; self.fingerprint = fingerprint
    }
}

public struct SearchRequest: Sendable, Equatable {
    public var text = ""
    public var sourceID: Int64?
    /// Stored folder path ("Source/sub/folder"); matches that folder and everything beneath it.
    public var folder = ""
    public var category = ""
    public var kind = ""
    public var key = ""
    public var minBPM: Double?
    public var maxBPM: Double?
    public var favoritesOnly = false
    public var unknownBPM = false
    public var includeUnavailable = false
    public var limit = 200
    public var offset = 0
    public init(text: String = "") { self.text = text }
}

public struct FolderNode: Identifiable, Hashable, Sendable {
    public var sourceID: Int64
    public var folder: String
    public var name: String
    public var count: Int
    public var children: [FolderNode]?
    public var id: String { "\(sourceID)|\(folder)" }

    /// Folders are stored as "Source name/relative/path". Folders that only hold
    /// subfolders still get a node, and every count includes everything beneath it.
    public static func tree(_ counts: [(sourceID: Int64, folder: String, count: Int)], sources: [LibrarySource]) -> [FolderNode] {
        final class Branch { var count = 0; var children: [String: Branch] = [:] }
        var roots: [Int64: Branch] = [:]
        for entry in counts {
            let root = roots[entry.sourceID] ?? Branch(); roots[entry.sourceID] = root
            var branch = root; branch.count += entry.count
            for part in entry.folder.split(separator: "/").dropFirst().map(String.init) {
                let child = branch.children[part] ?? Branch(); branch.children[part] = child
                branch = child; branch.count += entry.count
            }
        }
        func node(_ branch: Branch, sourceID: Int64, folder: String, name: String) -> FolderNode {
            let children = branch.children.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .map { node(branch.children[$0]!, sourceID: sourceID, folder: folder + "/" + $0, name: $0) }
            return FolderNode(sourceID: sourceID, folder: folder, name: name, count: branch.count, children: children.isEmpty ? nil : children)
        }
        return sources.map { node(roots[$0.id] ?? Branch(), sourceID: $0.id, folder: $0.name, name: $0.name) }
    }
}

public struct ScanProgress: Sendable {
    public var inspected = 0
    public var indexed = 0
    public var skipped = 0
    public var errors: [String] = []
    public var finished = false
    public init() {}
}
