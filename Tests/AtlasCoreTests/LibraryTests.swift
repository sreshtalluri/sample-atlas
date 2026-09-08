import XCTest
import AVFoundation
import CSQLite
@testable import AtlasCore

final class LibraryTests: XCTestCase {
    func testFolderHierarchyAndMusicalLabels() {
        XCTAssertEqual(Metadata.category(name: "texture_03", folder: "KSHMR/Effects/Sweeps"), "Sweep")
        XCTAssertEqual(Metadata.category(name: "texture_03", folder: "KSHMR/Effects/Risers"), "Riser")
        XCTAssertEqual(Metadata.category(name: "Drum_01", folder: "KSHMR/Drums/Snares"), "Snare")
        XCTAssertEqual(Metadata.category(name: "Kick_01", folder: "KSHMR/Drums/Claps"), "Kick")
        XCTAssertEqual(Metadata.kind(name: "Bass_01_C", folder: "KSHMR/Bass/One Shots"), "One-shot")
        XCTAssertEqual(Metadata.kind(name: "Kick_Loop_128", folder: "Drums/One Shots"), "Loop")
        XCTAssertEqual(Metadata.kind(name: "Kick_01", folder: "Drums/Kicks"), "One-shot")
        XCTAssertEqual(Metadata.rootNote("Bass_01_Db"), "C#")
        XCTAssertNil(Metadata.key("Bass_01_C"))
        XCTAssertEqual(Metadata.bpm("KSHMR_Drum_Loop_128", kind: "Loop"), 128)
        XCTAssertEqual(Metadata.bpm("Synth_128_F#min"), 128)
        XCTAssertNil(Metadata.bpm("Kick_128"))
        XCTAssertNil(Metadata.bpm("Bass_128_C", kind: "One-shot"))
        XCTAssertNil(Metadata.bpm("Drum_Loop_100_128", kind: "Loop"))
    }

    func testEveryMatchingResultCanBePagedWithStableRankAndFilters() async throws {
        let catalog = try Catalog(path: ":memory:")
        let source = try await catalog.addSource(url: URL(fileURLWithPath: "/synthetic/KSHMR"))
        var samples: [Sample] = []
        for i in 0..<637 {
            var sample = Sample(sourceID: source.id, path: "/synthetic/KSHMR/\(i).wav", name: String(format: "Sound_%04d", i),
                                folder: "KSHMR/Effects/Sweeps", bpm: 128, category: "Sweep")
            sample.kind = "One-shot"; sample.rootNote = "C"
            samples.append(sample)
        }
        try await catalog.upsert(samples, seen: "first")
        var request = SearchRequest(text: "kshmr sweeps")
        request.kind = "One-shot"; request.key = "root:C"; request.minBPM = 127; request.maxBPM = 129
        let ids = try await catalog.matchingIDs(request)
        XCTAssertEqual(ids.count, 637)
        var collected: [Int64] = []
        for offset in stride(from: 0, to: ids.count, by: 200) {
            request.offset = offset
            let page = try await catalog.search(request, rankedIDs: ids)
            collected += page.map(\.id)
        }
        XCTAssertEqual(collected, ids)
        XCTAssertEqual(Set(collected).count, 637)
        request.offset = 0
        let reversed = Array(ids.reversed())
        let page = try await catalog.search(request, rankedIDs: reversed)
        XCTAssertEqual(page.map(\.id), Array(reversed.prefix(200)))
        request.kind = "Loop"
        let excluded = try await catalog.matchingIDs(request)
        XCTAssertTrue(excluded.isEmpty)
        XCTAssertEqual(HybridRanking.fuse(lexical: ids, semantic: reversed).count, 637)
    }

    func testFolderFilterMatchesSubtreeAndTreeAggregatesCounts() async throws {
        let catalog = try Catalog(path: ":memory:")
        let source = try await catalog.addSource(url: URL(fileURLWithPath: "/synthetic/Pack"))
        let folders = ["Pack/Drums/Kicks", "Pack/Drums/Kicks", "Pack/Drums/Snares", "Pack/Drumsticks", "Pack"]
        try await catalog.upsert(folders.enumerated().map { i, folder in
            Sample(sourceID: source.id, path: "/synthetic/Pack/\(i).wav", name: "sound\(i)", folder: folder)
        }, seen: "t")
        var request = SearchRequest(); request.folder = "Pack/Drums"
        let subtree = try await catalog.matchingIDs(request).count
        XCTAssertEqual(subtree, 3, "Whole subtree, not the sibling sharing a prefix")
        request.folder = "Pack/Drums/Kicks"
        let kicks = try await catalog.matchingIDs(request).count
        XCTAssertEqual(kicks, 2)
        request.text = "sound2"
        let kicksNamedSound2 = try await catalog.matchingIDs(request).count
        XCTAssertEqual(kicksNamedSound2, 0, "Search combines with the folder")
        request.folder = "Pack/Drums"
        let drumsNamedSound2 = try await catalog.matchingIDs(request).count
        XCTAssertEqual(drumsNamedSound2, 1)
        let counts = try await catalog.folders()
        let tree = FolderNode.tree(counts, sources: [source])
        XCTAssertEqual(tree.map(\.name), ["Pack"]); XCTAssertEqual(tree[0].count, 5)
        let drums = tree[0].children?.first { $0.name == "Drums" }
        XCTAssertEqual(drums?.count, 3, "Intermediate folder without direct files is synthesized")
        XCTAssertEqual(drums?.children?.map(\.name), ["Kicks", "Snares"])
        XCTAssertNil(tree[0].children?.first { $0.name == "Drumsticks" }?.children)
    }

    func testRealScanKeepsOriginalAudioAndAnnotationsAcrossUpdates() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let pack = temporary.appendingPathComponent("Synthetic Pack")
        let folder = pack.appendingPathComponent("Drums/One Shots/Kicks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wav = folder.appendingPathComponent("Kick_01_C.wav")
        try writeTone(wav)
        let original = try Data(contentsOf: wav)
        let catalog = try Catalog(path: temporary.appendingPathComponent("catalog.sqlite").path)
        let source = try await catalog.addSource(url: pack)
        try await LibraryScanner.scan(source: source, catalog: catalog) { _ in }
        let initial = try await catalog.search(SearchRequest(text: "synthetic kicks"))
        let sample = try XCTUnwrap(initial.first)
        XCTAssertEqual(sample.kind, "One-shot"); XCTAssertEqual(sample.rootNote, "C")
        XCTAssertNil(sample.key); XCTAssertNil(sample.bpm)
        try await catalog.setFavorite(sample.id, true)
        try await catalog.setTags(sample.id, "round warm")
        try await LibraryScanner.scan(source: source, catalog: catalog) { _ in }
        let unchanged = try await catalog.search(SearchRequest(text: "warm"))
        XCTAssertEqual(unchanged.first?.id, sample.id); XCTAssertEqual(unchanged.first?.favorite, true)
        try writeTone(folder.appendingPathComponent("Kick_02_D.wav"))
        try await LibraryScanner.scan(source: source, catalog: catalog) { _ in }
        let count = try await catalog.count()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(try Data(contentsOf: wav), original)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(Set(files), ["Kick_01_C.wav", "Kick_02_D.wav"])
        let reopened = try Catalog(path: temporary.appendingPathComponent("catalog.sqlite").path)
        let restored = try await reopened.search(SearchRequest(text: "warm"))
        XCTAssertEqual(restored.first?.favorite, true)
        try FileManager.default.moveItem(at: pack, to: temporary.appendingPathComponent("Disconnected"))
        do {
            try await LibraryScanner.scan(source: source, catalog: catalog) { _ in }
            XCTFail("Offline sources must report an error")
        } catch { }
        let preserved = try await catalog.count()
        XCTAssertEqual(preserved, 2)
    }

    func testMigrationPreservesExistingCatalog() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE sources(id INTEGER PRIMARY KEY,path TEXT UNIQUE NOT NULL,name TEXT NOT NULL,bookmark BLOB);
        CREATE TABLE samples(id INTEGER PRIMARY KEY,source_id INTEGER NOT NULL,path TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,folder TEXT NOT NULL,duration REAL NOT NULL,sample_rate REAL NOT NULL,channels INTEGER NOT NULL,
        bpm REAL,musical_key TEXT,category TEXT NOT NULL,tags TEXT NOT NULL,favorite INTEGER NOT NULL,
        available INTEGER NOT NULL,fingerprint TEXT NOT NULL,metadata_origin TEXT NOT NULL,seen TEXT NOT NULL);
        INSERT INTO sources VALUES(1,'/synthetic/pack','pack',NULL);
        INSERT INTO samples VALUES(1,1,'/synthetic/pack/hit.wav','hit','pack',1,44100,1,NULL,NULL,'Other','warm',1,1,'old','filename','old');
        PRAGMA user_version=1;
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let catalog = try Catalog(path: path.path)
        let samples = try await catalog.search(SearchRequest())
        XCTAssertEqual(samples.first?.tags, "warm"); XCTAssertEqual(samples.first?.favorite, true)
        XCTAssertEqual(samples.first?.kind, "Unknown")
        let fingerprints = try await catalog.fingerprints(sourceID: 1)
        XCTAssertTrue(fingerprints.isEmpty, "Old metadata is refreshed once")
    }

    private func writeTone(_ url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for i in 0..<4410 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 220 / 44100)) * 0.1 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
