import XCTest
@testable import AtlasCore

final class MetadataTests: XCTestCase {
    func testTempoRequiresMarker() {
        XCTAssertEqual(Metadata.bpm("Loop_128_BPM.wav"), 128)
        XCTAssertNil(Metadata.bpm("808_128.wav"))
        XCTAssertEqual(Metadata.bpm("BPM-140-kick.wav"), 140)
    }
    func testKeyAliasesAndFilenameParsing() {
        XCTAssertEqual(Metadata.key("Dark Pad F# Minor.wav"), "F# minor")
        XCTAssertEqual(Metadata.key("bass Gb min.wav"), "F# minor")
        XCTAssertNil(Metadata.key("A minorish texture.wav"))
    }
    func testCategorySynonyms() {
        XCTAssertEqual(Metadata.category("cinematic uplifter sweep"), "Riser")
        XCTAssertEqual(Metadata.category("deep 808 sub"), "Bass")
    }
    func testFTSExpansion() {
        let query = Metadata.ftsQuery("airy riser")!
        XCTAssertTrue(query.contains("uplifter")); XCTAssertTrue(query.contains("airy"))
    }
    func testHybridRankingIsDeterministic() {
        XCTAssertEqual(HybridRanking.fuse(lexical: [1,2,3], semantic: [3,2,4]), [2,3,1,4])
    }
}
