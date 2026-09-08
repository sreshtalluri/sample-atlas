import SwiftUI
import AppKit
import AVFoundation
import AtlasCore

@MainActor
final class AppModel: ObservableObject {
    @Published var sources: [LibrarySource] = []
    @Published var results: [Sample] = []
    @Published var query = "" { didSet { scheduleSearch() } }
    @Published var sourceID: Int64? { didSet { scheduleSearch() } }
    @Published var folder = "" { didSet { scheduleSearch() } }
    @Published var folderTree: [FolderNode] = []
    @Published var category = "" { didSet { scheduleSearch() } }
    @Published var kind = "" { didSet { scheduleSearch() } }
    @Published var musicalKey = "" { didSet { scheduleSearch() } }
    @Published var minBPM = "" { didSet { scheduleSearch() } }
    @Published var maxBPM = "" { didSet { scheduleSearch() } }
    @Published var favoritesOnly = false { didSet { scheduleSearch() } }
    @Published var unknownBPM = false { didSet { scheduleSearch() } }
    @Published var semanticEnabled = UserDefaults.standard.bool(forKey: "semanticEnabled") {
        didSet { UserDefaults.standard.set(semanticEnabled, forKey: "semanticEnabled"); scheduleSearch() }
    }
    @Published var selectedID: Int64? { didSet { if selectedID != oldValue { loadSelection() } } }
    @Published var selected: Sample?
    @Published var peaks: [Float] = []
    @Published var isPlaying = false
    @Published var playhead: Double = 0
    @Published var volume: Double = 0.65 { didSet { player?.volume = Float(volume) } }
    @Published var looping = false { didSet { player?.numberOfLoops = looping ? -1 : 0 } }
    @Published var scanning = false
    @Published var scanStatus = "Add your sample folders to get started"
    @Published var scanErrors: [String] = []
    @Published var error: String?
    @Published var count = 0
    @Published var searchStatus = ""
    @Published var totalResults = 0
    @Published var loadingMore = false
    @Published var autoPreview = true
    @Published var rowsRevision = 0
    @Published var semanticStatus = "Optional local sound search"
    @Published var semanticBusy = false
    @Published var semanticReady = false
    @Published var tagsDraft = ""
    @Published var showSettings = false
    @Published var pythonPath = UserDefaults.standard.string(forKey: "semanticPython") ?? ""
    @Published var workerPath = UserDefaults.standard.string(forKey: "semanticWorker") ?? ""
    let catalog: Catalog
    let support: URL
    private let worker = SemanticWorker()
    private var player: AVAudioPlayer?
    private var searchTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var timer: Timer?
    private var scopedURLs: [URL] = []
    private var searchGeneration = 0
    private var rankedIDs: [Int64] = []
    private var resultRequest = SearchRequest()
    private var pageOffset = 0
    private var resultRevision = 0
    private var folderMonitor: FolderMonitor?
    private var watchedPaths: [String] = []
    private var pendingScan = false
    private var changeTask: Task<Void, Never>?

    init() throws {
        support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sample Atlas")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        catalog = try Catalog(path: support.appendingPathComponent("catalog.sqlite").path)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.playhead = player.currentTime; self.isPlaying = player.isPlaying
            }
        }
        Task { await reload(); restoreAccess(); scheduleSearch(); scan(); autoLoadSemantic() }
    }
    private func autoLoadSemantic() {
        let index = support.appendingPathComponent("semantic/embeddings.sqlite").path
        guard !pythonPath.isEmpty, !workerPath.isEmpty, FileManager.default.fileExists(atPath: index) else { return }
        startSemantic(index: false)
    }
    private func restoreAccess() {
        for source in sources {
            guard let bookmark = source.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        }
    }
    func reload() async {
        do {
            sources = try await catalog.sources(); count = try await catalog.count()
            folderTree = FolderNode.tree(try await catalog.folders(), sources: sources)
            let paths = sources.map(\.path)
            if paths != watchedPaths {
                watchedPaths = paths
                folderMonitor = FolderMonitor(paths: paths) { [weak self] in self?.foldersChanged() }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func foldersChanged() {
        changeTask?.cancel()
        changeTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if scanning { pendingScan = true } else { scan() }
        }
    }
    func addFolders() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true; panel.prompt = "Add to Library"
        panel.message = "Choose sample folders. Audio stays in its original location."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            var added: [LibrarySource] = []
            for url in urls {
                do {
                    if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
                    let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    added.append(try await catalog.addSource(url: url, bookmark: bookmark))
                } catch { self.error = error.localizedDescription }
            }
            await reload(); scan(added)
        }
    }
    func removeSource(_ source: LibrarySource) {
        Task {
            do { try await catalog.removeSource(source.id); if sourceID == source.id { sourceID = nil; folder = "" }; await reload(); scheduleSearch() }
            catch { self.error = error.localizedDescription }
        }
    }
    func scan(_ targets: [LibrarySource]? = nil) {
        guard !scanning else { return }
        let selectedSources = targets ?? sources
        guard !selectedSources.isEmpty else { return }
        scanning = true; scanErrors = []
        scanTask = Task {
            for source in selectedSources {
                if Task.isCancelled { break }
                scanStatus = "Scanning \(source.name)…"
                let catalog = self.catalog
                let task = Task.detached(priority: .utility) {
                    try await LibraryScanner.scan(source: source, catalog: catalog) { report in
                        await MainActor.run {
                            self.scanStatus = "\(source.name): \(report.inspected) files · \(report.indexed) updated · \(report.skipped) unchanged/skipped"
                            if report.finished { self.scanErrors.append(contentsOf: report.errors) }
                        }
                    }
                }
                do { try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() } }
                catch is CancellationError { scanStatus = "Scan cancelled; catalog preserved" }
                catch { scanErrors.append(error.localizedDescription) }
                await reload(); scheduleSearch()
            }
            scanning = false
            if !scanErrors.isEmpty { scanStatus = "Scan finished with \(scanErrors.count) reported issues" }
            if pendingScan && !Task.isCancelled { pendingScan = false; scan() }
        }
    }
    func cancelScan() { pendingScan = false; scanTask?.cancel() }
    var request: SearchRequest {
        var r = SearchRequest(text: query); r.sourceID = sourceID; r.folder = folder; r.category = category; r.kind = kind; r.key = musicalKey
        r.minBPM = Double(minBPM); r.maxBPM = Double(maxBPM); r.unknownBPM = unknownBPM; r.favoritesOnly = favoritesOnly
        return r
    }
    func scheduleSearch() {
        searchGeneration += 1
        resultRevision += 1
        rankedIDs = []; totalResults = 0; loadingMore = false
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(140))
                let r = request
                if (!minBPM.isEmpty && r.minBPM == nil) || (!maxBPM.isEmpty && r.maxBPM == nil) || ((r.minBPM ?? 0) > (r.maxBPM ?? .infinity)) {
                    searchStatus = "Enter a valid BPM range"; results = []; rowsRevision += 1; return
                }
                let start = ContinuousClock.now
                let lexical = try await catalog.matchingIDs(r)
                try Task.checkCancellation()
                try await present(lexical, request: r, generation: generation)
                searchStatus = "\(lexical.count.formatted()) matches · \(Int(start.duration(to: .now).milliseconds)) ms"
                if semanticEnabled && semanticReady && !semanticBusy && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    semanticBusy = true
                    defer {
                        semanticBusy = false
                        if generation != searchGeneration { scheduleSearch() }
                    }
                    let ids = try await catalog.eligibleIDs(r)
                    let semantic = try await worker.request("search", text: r.text, ids: ids)
                    guard generation == searchGeneration else { return }
                    let fused = HybridRanking.fuse(lexical: lexical, semantic: semantic)
                    try await present(fused, request: r, generation: generation)
                    searchStatus = "\(fused.count.formatted()) ranked sounds · \(Int(start.duration(to: .now).milliseconds)) ms"
                }
            } catch is CancellationError { }
            catch { if generation == searchGeneration { self.error = error.localizedDescription } }
        }
    }
    private func present(_ ids: [Int64], request: SearchRequest, generation: Int) async throws {
        let page = try await catalog.search(request, rankedIDs: ids)
        guard generation == searchGeneration else { return }
        resultRevision += 1; rankedIDs = ids; resultRequest = request; pageOffset = min(request.limit, ids.count)
        totalResults = ids.count; results = page; rowsRevision += 1; loadingMore = false
    }
    var hasMore: Bool { pageOffset < rankedIDs.count }
    func loadMore() {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        let revision = resultRevision
        var r = resultRequest; r.offset = pageOffset
        let ids = rankedIDs
        Task {
            do {
                let page = try await catalog.search(r, rankedIDs: ids)
                guard revision == resultRevision else { return }
                pageOffset = min(ids.count, r.offset + r.limit)
                results.append(contentsOf: page); rowsRevision += 1; loadingMore = false
            } catch { if revision == resultRevision { loadingMore = false; self.error = error.localizedDescription } }
        }
    }
    func toggleFavorite(_ sample: Sample) {
        Task { do { try await catalog.setFavorite(sample.id, !sample.favorite); scheduleSearch() } catch { self.error = error.localizedDescription } }
    }
    func saveTags() {
        guard let selected else { return }
        Task { do { try await catalog.setTags(selected.id, tagsDraft); scheduleSearch() } catch { self.error = error.localizedDescription } }
    }
    func resetFilters() { category = ""; kind = ""; musicalKey = ""; minBPM = ""; maxBPM = ""; unknownBPM = false; favoritesOnly = false }
    func reveal(_ sample: Sample) { NSWorkspace.shared.activateFileViewerSelecting([sample.url]) }
    private func loadSelection() {
        previewTask?.cancel(); player?.stop(); player = nil; isPlaying = false; playhead = 0; peaks = []
        selected = results.first { $0.id == selectedID }; tagsDraft = selected?.tags ?? ""
        guard let selected else { return }
        let url = selected.url
        previewTask = Task {
            do {
                let loaded = try await Task.detached(priority: .userInitiated) { try Waveform.read(url: url) }.value
                try Task.checkCancellation()
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.volume = Float(volume); audio.numberOfLoops = looping ? -1 : 0; audio.prepareToPlay()
                peaks = loaded; player = audio
                if autoPreview { audio.play(); isPlaying = audio.isPlaying }
            } catch is CancellationError { }
            catch { self.error = "Could not preview \(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }
    func clicked(_ id: Int64) {
        if selectedID == id {
            if autoPreview { player?.currentTime = 0; player?.play(); isPlaying = player?.isPlaying ?? false }
        } else { selectedID = id }
    }
    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying { player.pause() } else { if player.currentTime >= player.duration { player.currentTime = 0 }; player.play() }
        isPlaying = player.isPlaying
    }
    func seek(_ seconds: Double) { player?.currentTime = seconds; playhead = seconds }
    func startSemantic(index: Bool) {
        guard !semanticBusy else { return }
        UserDefaults.standard.set(pythonPath, forKey: "semanticPython"); UserDefaults.standard.set(workerPath, forKey: "semanticWorker")
        semanticBusy = true
        semanticStatus = index ? "Loading model and indexing audio…" : "Loading semantic index…"
        Task {
            do {
                try await worker.start(python: pythonPath, script: workerPath, catalog: catalog.path, cache: support.appendingPathComponent("semantic").path)
                _ = try await worker.request(index ? "index" : "load") { status in await MainActor.run { self.semanticStatus = status } }
                semanticReady = true; semanticStatus = "Ready · local audio embeddings"
            } catch { semanticReady = false; semanticStatus = error.localizedDescription; await worker.stop() }
            semanticBusy = false; scheduleSearch()
        }
    }
}

extension Duration {
    var milliseconds: Double { Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15 }
}
