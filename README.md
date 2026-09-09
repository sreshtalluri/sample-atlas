# Sample Atlas

A Mac app for finding sounds across your sample packs, downloaded Splice library, and installed Apple audio loops. Search in one place, click to listen, then drag a sound into Logic Pro.

Your audio stays in its original folders. Each user has a private local catalog; the public repository contains the app's code, not anyone's sound library.

## What it does

- Searches filenames, pack names, subfolders, and your own tags.
- Browses each library as a folder tree in the sidebar; click any folder to limit results to it and everything beneath it.
- Filters by instrument/effect type, loop or one-shot, BPM, key/root note, and favorites; all filters, the folder, and search combine.
- Previews on selection, with waveform, volume, looping, and scrubbing.
- Lets you drag directly from a result row into Logic, or reveal the original in Finder.
- Scrolls through all matching results, loading rows as needed.
- Saves your catalog between sessions and watches added folders for changes.
- Offers experimental local audio-based search for descriptions such as `airy noise riser`.

## Get started

You need **macOS 14 or later** and **Xcode 15.3 or later with Swift 5.10+**. Open Xcode once to finish its setup. Ordinary library search does not require Python or an account. Logic Pro is only needed for the Logic workflow.

In Terminal, from a directory where you keep projects:

```sh
git clone https://github.com/sreshtalluri/sample-atlas.git
cd sample-atlas
swift run SampleAtlas
```

Keep Terminal open while using the app. It currently launches from source; a signed, double-click `.app` installer is still planned. GitHub Actions artifacts contain a development executable, not an installer.

### Add your sounds

1. Extract downloaded ZIP packs in Finder.
2. Click **Add folders**, select a sample-pack root, then **Add to Library**.
3. Wait for the scan to finish. Add other pack locations as needed.

Subfolders are included automatically. Adding `Sample Pack` also includes `Sample Pack/Drums/One Shots/Kicks`. Those folder names help search and classification. Add the parent once rather than each nested folder.

For Splice, use **Preferences → Go to folder** in Splice to locate its downloads, then add that folder. For Apple loops, select the installed audio-loop folder, including its relocated location if applicable. Only local, readable audio is indexed; keep external drives connected. See the [usage guide](docs/USAGE.md) for details.

### Find a sound and use it in Logic

1. Search a term such as `kick` or `riser`; narrow with **Type**, **Kind**, BPM, or Key.
2. Click a result to listen. Arrow keys change selection, and **Space** plays/pauses while the list is focused. Turn **Auto-preview** off for manual playback.
3. Keep Logic beside Sample Atlas and drag the result row onto an audio track or the empty Tracks area below existing tracks.
4. Star useful sounds or enter custom tags below the preview and click **Save tags**.

If direct dragging fails in your setup, right-click → **Reveal in Finder**, then drag from Finder. Preview plays at the original tempo and pitch, independently of Logic's transport.

### BPM and key labels

The app reads filename labels and available metadata; it does not yet estimate missing BPM/key from the audio. A pitch without a mode is displayed as a root note:

| Example filename | Interpretation |
| --- | --- |
| `Drum_Loop_128.wav` | 128 BPM |
| `Synth_127.5_BPM_F#min.wav` | 127.5 BPM, F-sharp minor |
| `Riser_03_(A).wav` | A root note; BPM unknown |
| `Bass_C_M.wav` / `Bass_Cm.wav` | C major / C minor |
| `Sax Loop 65 (120, Gm).wav` | 120 BPM, G minor; `65` is a take number |

Every sound is a loop or a one-shot. Explicit `loop`/`one shot` labels in the name or folder win; otherwise named drum hits are one-shots, anything tagged with a tempo is a loop, and untimed sounds (FX, foley, vocal phrases) are one-shots. A one-shot can have a root note without a meaningful tempo. Ambiguous or absent values remain `—`. BPM/key filters can therefore hide untagged sounds; reset filters if expected results are missing.

## Updates and private data

Quit the app, then run from your existing checkout:

```sh
git pull --ff-only
swift run SampleAtlas
```

Your catalog, folders, favorites, and tags persist. New files trigger incremental scans while the app is open, and launch checks for changes made while it was closed. **Rescan folders** is a fallback after reconnecting a drive. Parser upgrades may refresh existing metadata once; you do not need to remove/re-add packs.

Catalogs and semantic embeddings stay in `~/Library/Application Support/Sample Atlas/`; app preferences use macOS settings storage. Original audio is never moved or overwritten. There is no audio upload service. Keep sample files, catalogs, credentials, and model downloads out of commits.

## Optional: search by sound

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then run in another terminal from this repository:

```sh
./scripts/setup-semantic.sh
```

Open **Sound search settings**, paste the Python and worker paths printed by the script, then click **Build / Update Sound Index**. Initial setup downloads dependencies and a model; audio analysis and later searches run locally. When ready, enable **Search by sound**.

On later launches the saved index loads automatically and the **Search by sound** switch remembers its state; **Load Existing Index** remains for manual retries. Once sound search is loaded, any scan that adds or changes files embeds just those files afterwards; **Build / Update Sound Index** remains for a manual run. This feature is experimental: real-library relevance and speed still need evaluation. It does not supply missing BPM/key values.

## Development and roadmap

The app uses SwiftUI/AppKit, AVFoundation/Core Audio, and SQLite FTS5. The optional Python worker uses a pinned CLAP model. Metadata filtering and ranked text search are combined with audio similarity when enabled. Rows load in pages of 200, with no total result cap.

```sh
swift test
swift build -c release
# After optional semantic setup:
cd semantic
.venv/bin/python -m unittest test_retrieval.py
```

Tests cover filename parsing, catalog migration, search pagination, annotation persistence, unchanged audio files, and retrieval ranking. Manual validation in Logic and semantic evaluation are ongoing. Next priorities include a proper installer, missing-metadata analysis, similar-sound search, and library relinking. See the [roadmap](PLAN.md).

Issues and pull requests are welcome. Include your macOS version, reproduction steps, and a non-sensitive filename example when relevant. Use synthetic or redistributable fixtures; do not attach private production audio or library databases.

[Detailed usage and troubleshooting](docs/USAGE.md) · [Roadmap](PLAN.md) · [MIT license](LICENSE)
