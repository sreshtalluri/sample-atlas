# Sample Atlas — working product plan

Status: proposal for discussion, before implementation. Name is provisional.

## Outcome

Find useful sounds across downloaded packs, downloaded Splice samples, and installed Apple audio loops from one place while producing in Logic Pro. Keep the original files in their existing folders.

The main workflow is: search → filter → audition → drag into Logic.

## Proposed experience

A standalone Mac app beside Logic, with a sources sidebar, a searchable results table, and a preview strip. Keyboard navigation should make auditioning successive results fast. Each result shows its name, source/pack, category, BPM, key, duration, and favorite status. The preview strip shows a waveform, play/stop, scrubbing, looping, and volume.

Examples:

- Search `riser` across every selected library.
- Filter drum loops to 120–128 BPM.
- Find bass samples in F-sharp minor, accepting equivalent G-flat labels.
- Save favorites for later sessions.
- Reveal a result in Finder or drag its original file into Logic.

Project BPM and key are entered manually initially. Automatic Logic transport synchronization and preview time stretching are separate follow-up capabilities.

## Scope and stages

### 1. Prove the complete workflow

- Choose multiple folders, persist their access, and scan recursively in the background.
- Support WAV, AIFF/AIF, and CAF audio first; validate additional formats on representative files.
- Include downloaded Splice files and installed Apple audio loops as ordinary selected sources.
- Build a persistent local catalog with filename, folder/pack, format, duration, sample rate, and channels.
- Extract explicit BPM/key tokens from filenames and supported embedded metadata; distinguish their provenance.
- Search names, folder names, and tags. Filter by source, category, BPM range, key, and duration.
- Include Unknown values explicitly; never invent a key or BPM to fill a column.
- Preview, favorite, and drag files into Logic. Offer Reveal in Finder as well.
- Persist the catalog and favorites across restarts; rescan without duplicate rows.

Initial milestone acceptance: select a real pack, search for a known sound, hear it, and successfully drag it into a Logic audio track. The drag behavior must be tested in Logic, not assumed from a successful build.

### 2. Improve metadata and library reliability

- Validate Apple Loop metadata extraction on actual installed CAF/AIFF files before claiming complete tag support.
- Estimate missing tempo/key in a cancellable background queue.
- Label estimates and confidence; permit user corrections that survive rescans.
- Distinguish tonal key from one-shot root pitch; allow non-tonal/unpitched sounds.
- Handle half/double-time BPM ambiguity and enharmonic key equivalence.
- Add category synonyms such as riser/uplifter and impact/hit, with visible editable tags.
- Add incremental updates, offline-drive status, source removal, and relinking of moved libraries.
- Detect identical content without deleting or merging source files automatically.

### 3. Search by sound

- Search descriptions such as `dark airy riser` and request similar sounds from a selected sample.
- Evaluate an audio/text embedding model against real production queries before selecting it.
- Combine semantic ranking with exact metadata filters and filename matches.
- Keep inference local where practical; measure model size, indexing time, memory, and retrieval quality on this Mac.
- Version derived features so a model change can rebuild its index independently.

Semantic search is audio understanding, not merely asking an LLM to rewrite filenames. Its inclusion in the first release depends on the user's priority.

## Proposed architecture

Recommended starting point for a Mac-only companion: SwiftUI with AppKit where native file drag and window behavior require it, AVFoundation/Core Audio for decoding and preview, and SQLite with full-text search for the catalog. This is a proposed choice, pending workflow preference.

```text
Selected folders
    ↓
Background scanner → metadata readers → local SQLite catalog
                                             ↓
                                   Search and filter UI
                                             ↓
                                Audio preview / drag to Logic

Future analysis worker → estimated metadata and semantic index
```

Keep UI, indexing, persistence, audio playback, and analysis behind separate interfaces. An optional analysis worker can be introduced later without replacing the native UI or catalog. Do not require a web server, account, or cloud hosting for ordinary local search.

Data entities:

- Source: selected root, persistent access reference, display name, availability, scan status.
- Sample: stable ID, source-relative location, file identity/stat fingerprint, audio properties, availability.
- Metadata value: field, value, origin (embedded/filename/estimated/manual), confidence where meaningful.
- User annotations: favorite, custom tags, manual overrides.
- Derived artifacts: waveform and optional analysis/embedding, with file fingerprint and algorithm version.

Overlapping source roots must not duplicate physical files. Distinct copies can retain distinct locations while sharing content-derived analysis after hashing.

## Behavior under real library conditions

- Index in place; do not reorganize packs or copy audio into the repository.
- Read bounded audio chunks; do not load the whole library or every waveform into memory.
- Search remains responsive during scanning. Report progress and unreadable files.
- Do not treat an unplugged drive or interrupted scan as proof that files were deleted.
- Avoid following symlink loops or triggering large cloud-placeholder downloads automatically.
- Index metadata before expensive analysis so the library becomes useful early.
- Store the catalog and caches outside the code repository.
- Preserve annotations during rescans and failed scans.

## Boundaries requiring validation

- Splice integration initially covers locally downloaded samples. Account-only/cloud samples need downloading through Splice first.
- Apple's audio loops fit the core workflow. MIDI, pattern, and Session Player loops and sampler instrument/preset formats need separate handling; standalone playback must not imply reproduction of Logic instruments.
- File dragging should preserve the original file. Preview tempo/key changes, when added, must clearly distinguish original-file dragging from exporting rendered audio.
- Tempo estimates are ambiguous for some loops and meaningless for some one-shots. Tonality estimates should remain unknown on noise/percussion when appropriate.

## Validation and project structure

Suggested repository: `sample-atlas`, private initially. Create the GitHub remote when implementation scope is settled. Commit code and synthetic/redistributable fixtures only; exclude sample libraries, local absolute-path catalogs, caches, and model downloads.

Suggested directories: `Sources/App`, `Sources/Catalog`, `Sources/Audio`, `Tests`, `docs`, and `scripts`, adjusted to the chosen build system.

Meaningful checks:

- Metadata parser cases for ambiguous filenames, BPM tokens, key aliases, and overrides.
- Database/filter checks for punctuation, empty queries, combined filters, and unknown metadata.
- Scanner checks for rescans, overlapping roots, unreadable files, disconnected sources, and cancellation.
- Audio decode/preview checks using generated fixtures and a user-selected representative set.
- Manual Mac/Logic checks for keyboard auditioning, drag/drop, folder access after relaunch, and an external drive reconnect.
- Benchmark search latency and scan behavior at the actual library size. Initial target: warm searches under 100 ms at 100,000 indexed records; this is an unverified target, not a measured result.

## Open product choices

1. Standalone Mac app, local browser UI, or Logic plug-in?
2. Is metadata search sufficient for the first usable milestone, or is semantic sound search required immediately?
3. Approximate sample count/size and source locations, especially external drives and cloud storage.

## Research references

- [Logic's Untagged Loops workflow](https://support.apple.com/en-ie/guide/logicpro/lgcpc1fd5da0/10.7/mac/11.0): existing folder-based browsing, useful as a baseline.
- [Apple Loop types](https://support.apple.com/en-ie/guide/logicpro/lgcp734a05f6/mac): audio, MIDI, pattern, and Session Player distinctions.
- [Splice downloaded file locations](https://support.splice.com/en/articles/8652631-where-do-my-downloaded-samples-presets-midi-files-go): downloaded sounds are local files.
- [AVAudioFile](https://developer.apple.com/documentation/avfaudio/avaudiofile): native audio file reading.
- [SQLite FTS5](https://sqlite.org/fts5.html): proposed text search engine; availability must be verified in the selected build.
- [LAION CLAP](https://github.com/LAION-AI/CLAP): candidate audio/text embeddings for an evaluation, not a committed dependency.
