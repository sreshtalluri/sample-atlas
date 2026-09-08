# Sample Atlas roadmap

Sample Atlas is a standalone Mac companion for browsing a personal sample library alongside Logic Pro. The core workflow is **search → preview → drag into the project**. The README documents current installation and use.

## Implemented

- Persistent local SQLite catalog, in-place recursive scans, filesystem change notifications, and explicit rescans.
- Filename, pack, subfolder, tag and category search; BPM, key/root, kind and favorite filters.
- Folder-aware categories, explicit loop/one-shot labels, and conservative filename metadata parsing.
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
| 2 | Simplify installation | Ship a proper `.app` bundle, then signed/notarized releases when signing is available. |
| 3 | Improve musical metadata | Analyze missing tempo/key, distinguish one-shot root pitch, expose confidence, and preserve user corrections. |
| 4 | Evaluate semantic retrieval | Run known production queries, measure relevance and latency, expose index coverage, and add similar-sound search. |
| 5 | Improve large-library navigation | Add folder-tree browsing, duration filters, duplicate grouping, moved-library relinking, and clearer offline status. |
| 6 | Match the production session | Add audio-output selection, tempo/pitch-matched preview, and investigate optional Logic transport integration. |

## Engineering constraints

- Keep audio and personal catalog data outside source control; never rewrite originals during indexing or preview.
- Keep scanning and model inference off the UI thread.
- Preserve annotations through failed scans and disconnected drives.
- Do not assign musical metadata solely to fill an empty column. Filename hints and audio estimates have different reliability.
- Measure search performance on representative sizes before setting speed claims. Under 100 ms for warm text search at 100,000 records remains a target, not a measured guarantee.
- Retain bounded decoding and cache versioning. Expensive semantic indexing remains explicit so it does not interrupt a production session.

## Current boundaries

Splice integration covers local downloads. Apple content support covers readable audio, not playback of Logic's MIDI/pattern/Session Player instruments. Preview is independent of Logic's transport and original-file dragging does not render preview effects. There is no cloud hosting, audio upload service, or account requirement for normal use.
