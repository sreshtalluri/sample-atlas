# Sample Atlas roadmap

Sample Atlas is a standalone Mac companion for browsing a personal sample library alongside Logic Pro. The core workflow is **search → preview → drag into the project**. The README documents current installation and use.

## Implemented

- Persistent local SQLite catalog, in-place recursive scans, filesystem change notifications, and explicit rescans.
- Filename, pack, subfolder, tag and category search; BPM, key/root, kind and favorite filters.
- Sidebar folder tree per library; selecting a folder limits results to its subtree and combines with search and filters.
- Folder-aware categories, loop/one-shot classification from labels, drum-hit names and tempo tags, and conservative filename metadata parsing.
- Ranked result snapshots with incremental row loading and no 200-result ceiling.
- Responsive native table, whole-row file dragging, automatic auditioning, waveform, volume, looping and scrubbing.
- Favorites and tags preserved across rescans and metadata-parser upgrades.
- Optional persistent Python worker with pinned CLAP embeddings, incremental embedding cache, exact eligible-ID filtering and reciprocal-rank fusion.
- Swift regression tests, semantic retrieval unit tests, and GitHub build/test workflows.

Implemented does not mean fully validated in every Logic/audio-interface setup. Semantic model loading, ranking quality and large-library performance still need production-library evaluation.

## Next milestones

| Priority | Work | Acceptance check |
| --- | --- | --- |
| 1 | Validate the daily workflow | Browse a representative pack, audition rapidly, drag into Logic, relaunch, and add a file while the app watches the folder. |
| 2 | Simplify installation | Ship a proper `.app` bundle with self-provisioning sound search (plan below), then signed/notarized releases when signing is available. |
| 3 | Improve musical metadata | Estimate tempo only for loops that still lack one (about 1% after the label parser), never invent tempo/key for one-shots or FX, expose confidence, and preserve user corrections. |
| 4 | Evaluate semantic retrieval | Run known production queries, measure relevance and latency, expose index coverage, and add similar-sound search. |
| 5 | Improve large-library navigation | Add duration filters, duplicate grouping, moved-library relinking, and clearer offline status. |
| 6 | Match the production session | Add audio-output selection, tempo/pitch-matched preview, and investigate optional Logic transport integration. |

### Plan: `.app` bundle with bundled `uv` (B1–B5 implemented; B6 awaits a Developer ID)

Goal: a double-clickable `Sample Atlas.app` where sound search needs no terminal, no Python install and no repository checkout. The bundle stays immutable (required for signing); everything mutable lives in `~/Library/Application Support/Sample Atlas/`.

Why `uv` rather than bundling Python: the worker needs PyTorch (~2 GB). Shipping it inside the bundle means a multi-gigabyte download and signing every dylib for notarization. `uv` is one ~15 MB static binary (MIT/Apache licensed) that can install a pinned Python 3.12 and the locked dependencies on demand.

| Step | Work | Acceptance check |
| --- | --- | --- |
| B1 | `scripts/make-app.sh`: `swift build -c release`, assemble `Contents/MacOS/SampleAtlas`, `Contents/Info.plist` (bundle ID, `LSMinimumSystemVersion` 14.0, `NSMicrophoneUsageDescription` not needed, `LSApplicationCategoryType` music), app icon, then `codesign --force --deep -s -` (ad hoc). | `open "Sample Atlas.app"` launches from Finder on a Mac without Xcode tools; text search and preview work with no other setup. |
| B2 | Copy into `Contents/Resources/semantic/`: `worker.py`, `pyproject.toml`, `uv.lock`, `model-revision.txt`, and `uv` binaries for arm64 and x86_64 (downloaded at build time from the pinned uv release, checksum verified). | Bundle size grows by <40 MB; `codesign --verify --deep` passes. |
| B3 | App-side provisioning: a "Set up sound search" button copies `pyproject.toml`/`uv.lock` to `Application Support/Sample Atlas/semantic-env/` and runs the bundled `uv sync --frozen --python 3.12` there, streaming progress into `semanticStatus`, cancellable. `pythonPath`/`workerPath` default to the provisioned interpreter and the bundled worker; the existing text fields stay as an advanced override. | On a clean user account with no Python, one click yields "Ready" after the download; quitting mid-install and clicking again resumes; `autoLoadSemantic` works on the next launch. |
| B4 | Failure handling: no network, disk full, uv exit code, and Gatekeeper blocking the extracted `uv` binary (mark it executable and strip quarantine on copy). Messages name the fix, never a stack trace. | Each failure is reproduced once and shows an actionable status line. |
| B5 | Release: `build-macos.yml` produces the zipped `.app` as the artifact/Release asset instead of the bare executable; README replaces `swift run` with download-and-open plus the right-click → Open note for unsigned builds. | A fresh download from the Releases page runs on another Mac. |
| B6 | Later, with a Developer ID: `codesign` with hardened runtime, `notarytool submit`, staple; remove the right-click → Open note. | Gatekeeper opens the app with no warning. |

Out of scope for this plan: converting CLAP to Core ML (removes Python entirely; revisit only after sound search proves useful on a real library), auto-updating, and Mac App Store distribution (sandboxing would block spawning `uv`).

## Engineering constraints

- Keep audio and personal catalog data outside source control; never rewrite originals during indexing or preview.
- Keep scanning and model inference off the UI thread.
- Preserve annotations through failed scans and disconnected drives.
- Do not assign musical metadata solely to fill an empty column. Filename hints and audio estimates have different reliability.
- Measure search performance on representative sizes before setting speed claims. Under 100 ms for warm text search at 100,000 records remains a target, not a measured guarantee.
- Retain bounded decoding and cache versioning. The first full semantic index build is explicit; after that, scans embed only new or changed files, and only when sound search is already loaded, so an unused feature never costs CPU during a session.

## Current boundaries

Splice integration covers local downloads. Apple content support covers readable audio, not playback of Logic's MIDI/pattern/Session Player instruments. Preview is independent of Logic's transport and original-file dragging does not render preview effects. There is no cloud hosting, audio upload service, or account requirement for normal use.
