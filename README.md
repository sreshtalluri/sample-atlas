# Sample Atlas

Sample Atlas is a local-first macOS sample browser for Logic Pro. It brings sample packs, downloaded Splice sounds, and Apple audio loops into one fast library with preview and drag-and-drop.

## What works

- Add multiple sample folders and rescan them in the background.
- Search filenames, folder names, tags, and categories with SQLite FTS5.
- Filter by source, category, BPM range, key, favorites, and unknown metadata.
- Parse explicit BPM/key tokens without inventing values. Add your own tags.
- Preview with waveform, scrubbing, looping, and volume controls.
- Drag the original file into Logic or reveal it in Finder.
- Optional local semantic search using a pinned CLAP audio/text model.
- Incremental scanning and embedding caches preserve responsiveness and annotations.

The app never moves or copies your audio. Its catalog lives in `~/Library/Application Support/Sample Atlas/` and is excluded from this repository. This public repository contains source code, documentation, and synthetic metadata tests only; it contains no personal sample files, library paths, catalog databases, credentials, or model weights.

## Run the app

This is an Xcode-compatible Swift Package for macOS 14 or later.

```sh
swift run SampleAtlas
```

Open `Package.swift` in Xcode to run and package it as a normal Mac application. The first launch asks you to choose folders. Add your local Splice folder from its configured Splice preferences, plus any pack folders and Apple audio-loop folders you use.

## Optional sound search

Text search works without Python or a model. To enable descriptions such as `dark airy riser`:

```sh
./scripts/setup-semantic.sh
```

Enter the printed Python executable and worker path in Sound search settings, then build the sound index. The model downloads once and runs locally. Analysis uses three ten-second windows, persists one embedding per file, and refreshes only changed files. Metadata filters are always applied before semantic ranking.

The semantic worker is intentionally optional: it adds a large model download and CPU indexing cost. Evaluate it on your own queries before relying on it for production decisions. See `semantic/worker.py` and `semantic/pyproject.toml` for the pinned implementation.

## Search design

Exact metadata filters are SQL predicates with indexes. Text queries are expanded through a small visible synonym map and ranked with FTS5 BM25. Semantic retrieval computes cosine similarity only among eligible IDs. When both modes are active, reciprocal-rank fusion combines the independent rankings without treating their scores as comparable. Query embeddings are LRU-cached and model inference is serialized through one resident worker.

Unknown BPM/key values remain unknown. Estimated values will carry their origin and confidence when automatic analysis is added.

## Development

```sh
swift test
swift build
```

Tests cover tempo/key parsing, synonyms, FTS query construction, and deterministic hybrid ranking. The scan and drag workflow should also be checked with a representative library and Logic Pro on a real Mac.

## Project status

This is an early working build. The next validation step is to index a real library and manually verify preview and drag into Logic. Follow the staged plan in [PLAN.md](PLAN.md) for metadata analysis, external-drive behavior, and semantic-quality evaluation.

## Privacy and contributions

Sample Atlas is local-first. Selected folder paths, security bookmarks, favorites, custom tags, and generated embeddings stay on the user's Mac. They are not uploaded by the app. Do not commit sample files, exported catalogs, absolute local paths, credentials, model weights, or private production audio. The repository's ignore rules cover common audio and cache formats, but review `git status` before committing.

Issues and pull requests are welcome. Please use synthetic or redistributable fixtures and describe your macOS/Logic Pro environment when reporting a workflow issue.

## License

MIT; see [LICENSE](LICENSE).
