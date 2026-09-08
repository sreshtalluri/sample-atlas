import XCTest
@testable import AtlasCore

final class SemanticWorkerTests: XCTestCase {
    /// A short reply must be delivered as soon as it is written. A reader that waits
    /// to fill a fixed-size buffer hangs forever on a worker that stays alive.
    func testShortRepliesArriveWithoutFillingTheReadBuffer() async throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sh")
        defer { try? FileManager.default.removeItem(at: script) }
        try """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed 's/.*"id":"\\([^"]*\\)".*/\\1/')
          printf '{"id":"%s","progress":"half"}\\n{"id":"%s","ids":[7,3]}\\n' "$id" "$id"
        done
        """.write(to: script, atomically: true, encoding: .utf8)
        let worker = SemanticWorker()
        try await worker.start(python: "/bin/sh", script: script.path, catalog: "", cache: "")
        let request = Task { try await worker.request("search", text: "x") }
        // Terminating the fake worker closes the pipe, which is the only way to unblock a stuck read.
        let watchdog = Task { try await Task.sleep(for: .seconds(5)); await worker.stop() }
        do {
            let ids = try await request.value
            XCTAssertEqual(ids, [7, 3])
        } catch {
            XCTFail("Reply never arrived within 5s; the reader is waiting to fill its buffer: \(error)")
        }
        watchdog.cancel(); await worker.stop()
    }
}
