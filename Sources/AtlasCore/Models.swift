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
    public var category = ""
    public var key = ""
    public var minBPM: Double?
    public var maxBPM: Double?
    public var favoritesOnly = false
    public var unknownBPM = false
    public var includeUnavailable = false
    public var limit = 200
    public init(text: String = "") { self.text = text }
}

public struct ScanProgress: Sendable {
    public var inspected = 0
    public var indexed = 0
    public var skipped = 0
    public var errors: [String] = []
    public var finished = false
    public init() {}
}
