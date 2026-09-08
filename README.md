# Sample Atlas

Sample Atlas is a local-first macOS sample browser for Logic Pro. It brings sample packs, downloaded Splice sounds, and Apple audio loops into one fast library with preview and drag-and-drop.

Start with the [step-by-step usage guide](docs/USAGE.md), including updating an existing library, using Logic, and optional semantic setup.

## What works

- Add multiple sample folders and rescan them in the background.
- Keep the local catalog across launches; watch registered folders and update after additions or changes.
- Search filenames, folder names, tags, and categories with SQLite FTS5.
- Search pack names and the full subfolder hierarchy; keep sweeps and risers distinct.
- Scroll through every matching result, loading row details in pages.
- Filter by source, category, BPM range, key, favorites, and unknown metadata.
- Filter Loops, One-shots, or Unknown independently of instrument/effect type.
- Parse explicit BPM/key tokens without inventing values. Add your own tags.
- Preview with waveform, scrubbing, looping, and volume controls.
- Click or keyboard-select a row to auto-preview; turn Auto-preview off when preferred.
- Drag the original file into Logic or reveal it in Finder.
- Optional local semantic search using a pinned CLAP audio/text model.
- Incremental scanning and embedding caches preserve responsiveness and annotations.

The app never moves or copies your audio. Its catalog lives in `~/Library/Application Support/Sample Atlas/` and is excluded from this repository. This public repository contains source code, documentation, and synthetic metadata tests only; it contains no personal sample files, library paths, catalog databases, credentials, or model weights.

## Run the app

This is an Xcode-compatible Swift Package for macOS 14 or later.

```sh
swift run SampleAtlas
```

Open `Package.swift` in Xcode to develop the app. On first launch, click Choose sample folders. Add your local Splice folder from its configured Splice preferences, plus any pack folders and Apple audio-loop folders you use.

## Use it privately

Each person runs the same app against their own folders. The selected roots, security bookmarks, catalog database, favorites, custom tags, and semantic embeddings are stored in that user's macOS Application Support directory. Waveforms are computed for the preview in memory. Local settings use macOS preferences. No library contents are part of the Git repository and the app has no upload service.

## Install for yourself or others

For development, clone the repository and run `swift run SampleAtlas`. To build a release executable:

```sh
swift build -c release
```

The GitHub Actions macOS workflow publishes a downloadable command-line executable artifact after a successful build. This is not yet a packaged, signed, notarized `.app` installer; use the source launch instructions above. Signing credentials are not stored in this repository.

The project is also suitable as a portfolio demonstration: the README, plan, architecture, tests, CI, and optional semantic layer are public, while all personal audio remains local.

## Optional sound search

Text search works without Python or a model. To enable descriptions such as `dark airy riser`:

```sh
./scripts/setup-semantic.sh
```

Enter the printed Python executable and worker path in Sound search settings, then build the sound index. The model downloads once and runs locally. Analysis uses three ten-second windows, persists one embedding per file, and refreshes only changed files. Metadata filters are always applied before semantic ranking.

The semantic worker is intentionally optional: it adds a large model download and CPU indexing cost. Evaluate it on your own queries before relying on it for production decisions. See `semantic/worker.py` and `semantic/pyproject.toml` for the pinned implementation.

## Search design

Exact metadata filters are SQL predicates with indexes. Text queries are expanded through a small visible synonym map and ranked with FTS5 BM25. A query snapshots all ranked IDs and loads row details in pages of 200 as you scroll; 200 is a page size, not a result cap. Semantic retrieval scores the resident vector matrix and returns the eligible IDs in cosine-similarity order. When both modes are active, reciprocal-rank fusion combines the independent rankings without treating their scores as comparable. Query embeddings are LRU-cached and model inference is serialized through one resident worker. Semantic results rank indexed sounds by similarity; they are not guaranteed exact matches to a description.

Unknown BPM/key values remain unknown. Estimated values will carry their origin and confidence when automatic analysis is added.

## Development

```sh
swift test
swift build
```

Tests cover hierarchy and tempo/key parsing, FTS filters, pagination past 200 results, schema migration, annotation persistence, unchanged audio bytes, disconnected sources, and deterministic hybrid ranking. The semantic retrieval tests run without downloading a model: `cd semantic && .venv/bin/python -m unittest test_retrieval.py`. Real model quality, folder events, and dragging into Logic still need validation on a representative production library.

## Project status

This is an early working build. The next validation step is to index a real library and manually verify preview and drag into Logic. Follow the staged plan in [PLAN.md](PLAN.md) for metadata analysis, external-drive behavior, and semantic-quality evaluation.

## Privacy and contributions

Sample Atlas is local-first. Selected folder paths, security bookmarks, favorites, custom tags, and generated embeddings stay on the user's Mac. They are not uploaded by the app. Do not commit sample files, exported catalogs, absolute local paths, credentials, model weights, or private production audio. The repository's ignore rules cover common audio and cache formats, but review `git status` before committing.

Issues and pull requests are welcome. Please use synthetic or redistributable fixtures and describe your macOS/Logic Pro environment when reporting a workflow issue.

## License

MIT; see [LICENSE](LICENSE).
