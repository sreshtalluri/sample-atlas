import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AtlasCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool
    private let accent = Color(red: 0.66, green: 0.86, blue: 0.42)
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
            VStack(spacing: 0) {
                header
                filters.padding(.horizontal, 24).padding(.bottom, 18)
                Divider()
                if model.count == 0 && !model.scanning { emptyState }
                else { results }
                Divider()
                preview
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accent)
        .preferredColorScheme(.dark)
        .alert("Sample Atlas", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $model.showSettings) { settings }
        .onAppear { searchFocused = true }
        .toolbar {
            ToolbarItem { Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }.keyboardShortcut("f").help("Focus search") }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 25, weight: .semibold)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SAMPLE ATLAS").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Your sounds, within reach.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.top, 14)
            VStack(spacing: 6) {
                sidebarButton("All samples", icon: "square.stack.3d.up", active: model.sourceID == nil && !model.favoritesOnly) { model.sourceID = nil; model.folder = ""; model.favoritesOnly = false }
                sidebarButton("Favorites", icon: "star", active: model.favoritesOnly) { model.sourceID = nil; model.folder = ""; model.favoritesOnly = true }
            }
            HStack { Text("LIBRARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Text("\(model.sources.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            List(model.folderTree, children: \.children) { node in
                folderRow(node).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            Button { model.addFolders() } label: { Label("Add folders", systemImage: "plus").frame(maxWidth: .infinity) }.controlSize(.large).disabled(model.scanning)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("\(model.count.formatted()) samples indexed").font(.callout.weight(.medium))
                Text(model.scanStatus).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                if model.scanning {
                    ProgressView().controlSize(.small)
                    Button("Cancel scan") { model.cancelScan() }
                } else { Button("Rescan folders") { model.scan() }.disabled(model.sources.isEmpty) }
                if !model.scanErrors.isEmpty {
                    Button("Show scan issues") { model.error = model.scanErrors.joined(separator: "\n") }.foregroundStyle(.orange)
                }
            }
            Button { model.showSettings = true } label: { Label("Sound search settings", systemImage: "slider.horizontal.3") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(18).background(Color.black.opacity(0.15))
    }
    private func sidebarButton(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: icon).frame(width: 20); Text(title).lineLimit(1); Spacer() }
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(active ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(active ? accent : .secondary)
        }.buttonStyle(.plain)
    }
    private func folderRow(_ node: FolderNode) -> some View {
        let active = model.sourceID == node.sourceID && model.folder == node.folder && !model.favoritesOnly
        let source = model.sources.first { $0.id == node.sourceID }
        let isRoot = node.folder == source?.name
        let path = source.map { $0.path + String(node.folder.dropFirst($0.name.count)) }
        return Button { model.sourceID = node.sourceID; model.folder = node.folder; model.favoritesOnly = false } label: {
            HStack(spacing: 6) {
                Image(systemName: isRoot ? "folder.fill" : "folder").frame(width: 18)
                Text(node.name).lineLimit(1)
                Spacer(minLength: 4)
                Text(node.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(active ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(active ? accent : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(path ?? node.folder)
        .contextMenu {
            if let source, let path {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
                if isRoot { Button("Remove from Catalog", role: .destructive) { model.removeSource(source) }.disabled(model.scanning) }
            }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Find your next sound.").font(.system(size: 29, weight: .semibold, design: .rounded))
                Spacer()
                Text("LOCAL LIBRARY").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(accent)
                TextField(model.semanticEnabled ? "Describe a sound, or search names and tags…" : "Search sounds, packs, and tags…", text: $model.query)
                    .textFieldStyle(.plain).font(.title3).focused($searchFocused)
                    .accessibilityLabel("Search samples")
                if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search") }
                Text("⌘ F").font(.caption).foregroundStyle(.tertiary)
            }.padding(15).background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
        }.padding(24)
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Type", selection: $model.category) {
                    Text("All types").tag("")
                    ForEach(Metadata.categories, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 132).help("Instrument or effect type")
                Picker("Kind", selection: $model.kind) {
                    Text("All sounds").tag("")
                    Text("Loops").tag("Loop"); Text("One-shots").tag("One-shot"); Text("Unknown kind").tag("Unknown")
                }.labelsHidden().frame(width: 116).help("Loops, one-shots, or unknown kind")
                Picker("Key", selection: $model.musicalKey) {
                    Text("Any key").tag(""); Text("Unknown").tag("Unknown")
                    ForEach(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"], id: \.self) { note in
                        Text(note + " major").tag(note + " major"); Text(note + " minor").tag(note + " minor")
                        Text(note + " (root note)").tag("root:" + note)
                    }
                }.labelsHidden().frame(width: 140).help("Musical key or root note")
                HStack(spacing: 6) {
                    Text("BPM").foregroundStyle(.secondary)
                    TextField("Min", text: $model.minBPM).frame(width: 44).disabled(model.unknownBPM).accessibilityLabel("Minimum BPM")
                    Text("–").foregroundStyle(.secondary)
                    TextField("Max", text: $model.maxBPM).frame(width: 44).disabled(model.unknownBPM).accessibilityLabel("Maximum BPM")
                    Toggle("Unknown", isOn: $model.unknownBPM).toggleStyle(.checkbox).help("Only sounds without BPM metadata")
                }.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Button("Reset") { model.resetFilters() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.controlSize(.small)
            HStack {
                Text(model.searchStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Search by sound", isOn: $model.semanticEnabled).toggleStyle(.switch).controlSize(.mini).disabled(!model.semanticReady)
                    .help("Enable the local audio model in Sound search settings")
            }
        }
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 52, weight: .light)).foregroundStyle(accent)
            Text("One home for all your sounds").font(.title2.weight(.semibold))
            Text("Add sample packs, your downloaded Splice folder,\nor installed Apple audio loops. Search them together.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Choose sample folders…") { model.addFolders() }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("Files stay where they are. No account required.").font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var results: some View {
        VStack(spacing: 0) {
            SampleTable(model: model)
            if model.hasMore || model.loadingMore {
                HStack {
                    Text("\(model.results.count.formatted()) of \(model.totalResults.formatted()) loaded · scroll for more").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Load more") { model.loadMore() }.disabled(model.loadingMore)
                    if model.loadingMore { ProgressView().controlSize(.small) }
                }.padding(8)
            }
            if model.results.isEmpty { Text(model.scanning ? "Your library is being indexed…" : "No matching samples. Try fewer filters or a broader search.").foregroundStyle(.secondary).padding(24) }
        }.frame(maxHeight: .infinity)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sample = model.selected {
                HStack {
                    Text(sample.name).font(.headline).lineLimit(1)
                    Spacer()
                    Text("\(Int(sample.sampleRate)) Hz · \(sample.channels) ch · \(sample.url.pathExtension.uppercased())").font(.caption).foregroundStyle(.secondary)
                    Button { model.reveal(sample) } label: { Image(systemName: "folder") }.help("Reveal in Finder")
                    Label("Drag to Logic", systemImage: "hand.draw").font(.caption).padding(7).background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6)).onDrag { NSItemProvider(object: sample.url as NSURL) }
                }
                HStack(spacing: 16) {
                    Button { model.togglePlayback() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 35, height: 35) }.buttonStyle(.borderedProminent).accessibilityLabel(model.isPlaying ? "Pause preview" : "Play preview")
                    waveform.frame(height: 48)
                    Toggle(isOn: $model.looping) { Image(systemName: "repeat") }.toggleStyle(.button).help("Loop preview")
                    autoPreviewToggle
                    Image(systemName: "speaker.wave.2").foregroundStyle(.secondary)
                    Slider(value: $model.volume, in: 0...1).frame(width: 90).accessibilityLabel("Preview volume")
                }
                Slider(value: Binding(get: { model.playhead }, set: { model.seek($0) }), in: 0...max(sample.duration, 0.001)).accessibilityLabel("Preview position")
                HStack {
                    TextField("Add tags: airy, cinematic, transition…", text: $model.tagsDraft).textFieldStyle(.plain).onSubmit { model.saveTags() }
                    Button("Save tags") { model.saveTags() }.controlSize(.small)
                    Text("Metadata: \(sample.metadataOrigin)").font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                HStack { Image(systemName: "headphones").font(.title2); Text("Select a sound to preview"); Spacer(); autoPreviewToggle; Text("↑ ↓ Navigate    Space Play / Pause").font(.caption) }.foregroundStyle(.secondary).frame(height: 130)
            }
        }.padding(20).background(Color.black.opacity(0.12))
    }
    private var autoPreviewToggle: some View {
        Toggle("Auto-preview", isOn: $model.autoPreview).toggleStyle(.checkbox).controlSize(.small)
            .fixedSize().help("Play when selecting a sound; use Space to pause")
    }
    private var waveform: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let peaks = model.peaks
                guard !peaks.isEmpty else { return }
                let width = size.width / Double(peaks.count)
                let fraction = model.playhead / max(model.selected?.duration ?? 1, 0.001)
                for (index, peak) in peaks.enumerated() {
                    let height = max(2, CGFloat(peak) * size.height)
                    let rectangle = CGRect(x: CGFloat(index) * width, y: (size.height - height) / 2, width: max(1, width - 1), height: height)
                    context.fill(Path(roundedRect: rectangle, cornerRadius: 1), with: .color(Double(index) / Double(peaks.count) <= fraction ? accent : accent.opacity(0.32)))
                }
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in model.seek(max(0, min(1, value.location.x / geometry.size.width)) * (model.selected?.duration ?? 0)) })
        }.accessibilityLabel("Audio waveform")
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Search by what you hear").font(.title2.weight(.semibold))
            Text("The optional CLAP model compares your description with the audio itself. It runs locally after a one-time model download. Text search works independently.").foregroundStyle(.secondary)
            Text("Run scripts/setup-semantic.sh from the repository, then use the paths it prints.").font(.callout)
            TextField("Python executable", text: $model.pythonPath).textFieldStyle(.roundedBorder)
            TextField("semantic/worker.py path", text: $model.workerPath).textFieldStyle(.roundedBorder)
            HStack {
                Button("Build / Update Sound Index") { model.startSemantic(index: true) }.disabled(model.semanticBusy || model.scanning || model.pythonPath.isEmpty || model.workerPath.isEmpty)
                Button("Load Existing Index") { model.startSemantic(index: false) }.disabled(model.semanticBusy || model.pythonPath.isEmpty || model.workerPath.isEmpty)
                if model.semanticBusy { ProgressView().controlSize(.small) }
            }
            Text(model.semanticStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Rebuild after rescanning folders. Missing or changed embeddings are refreshed incrementally. BPM and key filters remain exact.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { model.showSettings = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 640)
    }
}
