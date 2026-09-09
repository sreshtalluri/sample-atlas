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

You need **macOS 14 or later**. Ordinary library search does not require Python or an account. Logic Pro is only needed for the Logic workflow.

### Download the app

1. Download `Sample-Atlas-macos.zip` from the [Releases page](https://github.com/sreshtalluri/sample-atlas/releases), or from the latest **Build macOS app** run under Actions.
2. Unzip it and drag **Sample Atlas.app** into Applications.
3. The first time, right-click the app and choose **Open**. The build is not yet notarized, so a plain double-click is blocked once; afterwards it opens normally.

### Or run from source

You need **Xcode 15.3 or later with Swift 5.10+**; open Xcode once to finish its setup. In Terminal, from a directory where you keep projects:

```sh
git clone https://github.com/sreshtalluri/sample-atlas.git
cd sample-atlas
swift run SampleAtlas
```

Keep Terminal open while using the app. `scripts/make-app.sh` builds the same `Sample Atlas.app` locally into `dist/`.

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

To update the downloaded app, quit it, download the newest `Sample-Atlas-macos.zip`, and replace the copy in Applications. From a source checkout:

```sh
git pull --ff-only
swift run SampleAtlas          # or scripts/make-app.sh to rebuild dist/Sample Atlas.app
```

Your catalog, folders, favorites, and tags persist. New files trigger incremental scans while the app is open, and launch checks for changes made while it was closed. **Rescan folders** is a fallback after reconnecting a drive. Parser upgrades may refresh existing metadata once; you do not need to remove/re-add packs.

Catalogs and semantic embeddings stay in `~/Library/Application Support/Sample Atlas/`; app preferences use macOS settings storage. Original audio is never moved or overwritten. There is no audio upload service. Keep sample files, catalogs, credentials, and model downloads out of commits.

## Optional: search by sound

In the downloaded app: open **Sound search settings** and click **Set up sound search**. It installs a private Python runtime and the model dependencies (roughly 1 GB, one time) into `~/Library/Application Support/Sample Atlas/` using the bundled `uv`, then builds the sound index. Nothing is installed system-wide.

When running from source instead, install [uv](https://docs.astral.sh/uv/getting-started/installation/), then run in another terminal from this repository:

```sh
./scripts/setup-semantic.sh
```

Then open **Sound search settings**, paste the Python and worker paths printed by the script, and click **Build / Update Sound Index**. Either way, the first run downloads the model; audio analysis and later searches run locally. When ready, enable **Search by sound**.

On later launches the saved index loads automatically and the **Search by sound** switch remembers its state; **Load Existing Index** remains for manual retries. Once sound search is loaded, any scan that adds or changes files embeds just those files afterwards; **Build / Update Sound Index** remains for a manual run. Relevance has been checked on one library of about 10,000 sounds; treat it as a complement to text search rather than a replacement. It does not supply missing BPM/key values.

## Development and roadmap

The app uses SwiftUI/AppKit, AVFoundation/Core Audio, and SQLite FTS5. The optional Python worker uses a pinned CLAP model. Metadata filtering and ranked text search are combined with audio similarity when enabled. Rows load in pages of 200, with no total result cap.

```sh
swift test
swift build -c release
# After optional semantic setup:
cd semantic
.venv/bin/python -m unittest test_retrieval.py
```

Tests cover filename parsing, loop/one-shot classification, folder-tree filtering, the directory walk, catalog migration, search pagination, annotation persistence, the worker protocol, and retrieval ranking. Next priorities include similar-sound search, duplicate grouping, tempo estimation for the few loops without a label, library relinking, and notarized releases. See the [roadmap](PLAN.md).

Issues and pull requests are welcome. Include your macOS version, reproduction steps, and a non-sensitive filename example when relevant. Use synthetic or redistributable fixtures; do not attach private production audio or library databases.

[Detailed usage and troubleshooting](docs/USAGE.md) · [Roadmap](PLAN.md) · [MIT license](LICENSE)
