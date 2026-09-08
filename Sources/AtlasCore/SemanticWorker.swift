import Foundation

/// Owns one persistent Python process. Blocking pipe I/O stays on this actor's executor.
/// Only one request is in flight; the Python worker caches its model and query embeddings.
public actor SemanticWorker {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var busy = false
    public init() {}
    public func start(python: String, script: String, catalog: String, cache: String) throws {
        guard process?.isRunning != true else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: python)
        p.arguments = [script, "--catalog", catalog, "--cache", cache]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = FileHandle.standardError
        var env = ProcessInfo.processInfo.environment
        env["TOKENIZERS_PARALLELISM"] = "false"; env["OMP_NUM_THREADS"] = "2"
        p.environment = env
        try p.run(); process = p; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        buffer.removeAll()
    }
    public func stop() {
        try? input?.close(); process?.terminate(); process = nil
        try? output?.close(); input = nil; output = nil; buffer.removeAll()
    }
    deinit { process?.terminate() }
    public func request(_ command: String, text: String = "", ids: [Int64] = [],
                        progress: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> [Int64] {
        guard !busy else { throw CatalogError(message: "Semantic engine is processing another request.") }
        busy = true
        defer { busy = false }
        guard process?.isRunning == true, let input, let output else { throw CatalogError(message: "Start the semantic engine first.") }
        let requestID = UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["id": requestID, "command": command, "text": text, "ids": ids])
        try input.write(contentsOf: data + Data([10]))
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any], message["id"] as? String == requestID else { continue }
                if let error = message["error"] as? String { throw CatalogError(message: error) }
                if let status = message["progress"] as? String { await progress(status); continue }
                return (message["ids"] as? [NSNumber] ?? []).map(\.int64Value)
            }
            // read(upToCount:) keeps reading a pipe until the count is filled, so a short
            // final reply would never surface. availableData returns whatever has arrived.
            let chunk = output.availableData
            guard !chunk.isEmpty else { throw CatalogError(message: "Semantic worker exited. Check its Python environment and model files.") }
            buffer.append(chunk)
            if buffer.count > 4_000_000 { throw CatalogError(message: "Invalid semantic worker response.") }
        }
    }
}
