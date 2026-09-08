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
    func testParenthesizedPackRootNotes() {
        for (name, note) in [("KSHMR RISER 03 (A)", "A"), ("KSHMR Instrument Reverse 03 (E)", "E")] {
            XCTAssertEqual(Metadata.rootNote(name), note)
            XCTAssertEqual(Metadata.rootNote(name + ".wav"), note)
            XCTAssertNil(Metadata.key(name), "A root note must not imply major/minor")
            XCTAssertNil(Metadata.bpm(name))
        }
        XCTAssertEqual(Metadata.rootNote("KSHMR_Bass_C#_Sustained_03.wav"), "C#")
        XCTAssertEqual(Metadata.rootNote("Bass_[Eb]_Soft.wav"), "D#")
        XCTAssertNil(Metadata.rootNote("A warm pad"))
        XCTAssertNil(Metadata.rootNote("Bass_(C)_(D)"), "Conflicting roots are ambiguous")
    }
    func testKeyAndTempoNamingConventions() {
        XCTAssertEqual(Metadata.key("Synth_C_M_128.wav"), "C major")
        XCTAssertEqual(Metadata.key("Synth_Cm_128.wav"), "C minor")
        XCTAssertEqual(Metadata.key("Synth_F_sharp__minor_128.wav"), "F# minor")
        XCTAssertEqual(Metadata.key("Synth_DflatMaj_128.wav"), "C# major")
        XCTAssertEqual(Metadata.key("Pad (G♭ minor).aiff"), "F# minor")
        XCTAssertEqual(Metadata.bpm("Drum_Loop_127.5.wav"), 127.5)
        XCTAssertEqual(Metadata.bpm("Synth_(F#min)_128.wav"), 128)
        XCTAssertEqual(Metadata.bpm("Perc [BPM=128].wav"), 128)
        XCTAssertEqual(Metadata.bpm("Perc 127,5 BPM.wav"), 127.5)
        XCTAssertNil(Metadata.bpm("Perc 100BPM 128BPM.wav"))
        XCTAssertNil(Metadata.bpm("Kick_128_(C).wav", kind: "One-shot"))
    }
}
