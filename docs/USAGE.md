# Using Sample Atlas

## Update and launch

Quit any running Sample Atlas first. From the repository folder:

```sh
git pull --ff-only
swift run SampleAtlas
```

Keep that terminal open while the app runs. The current distribution is a development executable, not a signed `.app` installer.

Your local catalog is reused automatically. This metadata-parser upgrade performs one refresh of previously indexed files on the first launch; it preserves favorites and custom tags. Later launches check for changes and skip metadata decoding for unchanged files. There is no need to re-add packs or delete the database.

## Add sample packs

1. Extract ZIP downloads in Finder.
2. Click **Add folders**, choose a pack root, and click **Add to Library**.
3. Keep external drives connected during scans and playback.
4. Wait for the scan progress in the sidebar. Use **Show scan issues** for unreadable files.

Nested folders are included automatically. Add the parent once, not each child. For example, adding `KSHMR` also indexes `KSHMR/Drums/One Shots/Kicks` and `KSHMR/Effects/Risers`. Names from the pack root and every subfolder are searchable. A clear filename category takes precedence; otherwise the closest recognized folder supplies the category.

For Splice, choose **Preferences → Go to folder** in Splice and add that folder. Download cloud-only samples through Splice first. For Apple loops, add the actual audio-loop folder, including a relocated library if applicable. The common `/Library/Audio/Apple Loops` location may be empty. MIDI, pattern, and Session Player instrument playback are not supported by this app.

## Find and audition sounds

- Search `kshmr kick` or `sweeps`; combine that with the Type and Kind filters.
- Kind has **Loops**, **One-shots**, and **Unknown**. It reads explicit file/folder labels, not duration guesses.
- Click a row to hear it. Changing the selection stops the previous preview. Clicking the same row restarts it. Arrow-key selection also auto-previews.
- Turn off **Auto-preview** if you want manual playback; Space toggles play/pause while the table is focused.
- Use looping, volume and scrubbing in the preview strip.
- Scroll to load more rows. All matches are available; the footer shows how many are loaded. **Load more** is an accessible alternative to scrolling.
- Star a sound or add tags and choose **Save tags**.

Sweeps, risers, downlifters, impacts, claps and snares are distinct categories. Category synonyms expand name searches, while category filters use the inferred category exactly. If an inferred type hides an expected result, reset that filter and use the searchable folder/name.

## BPM, musical key, and root notes

- Explicit BPM labels are read from filenames and, as fallback, folders. A single plausible bare number is also accepted in a loop filename or alongside a pitch label, except for explicitly labeled one-shots where numbers may be hit IDs. These remain filename hints, not audio measurements.
- Major/minor labels such as `F#min` are stored as keys.
- A final pitch label such as `Bass_01_C` is a **root note**. It does not imply C major.
- A one-shot usually has no meaningful tempo, but a pitched bass/synth/kick can have a root note; a chord one-shot can have a key.
- Unpitched percussion/noise can have neither. Unknown values remain blank (`—`). No automatic audio-based BPM/key estimation is included yet.
- A BPM range excludes samples without BPM. Reset it when looking for untagged one-shots.

## Drag into Logic

1. Open your Logic project and put Sample Atlas beside it.
2. Select and audition a sound.
3. Drag from anywhere in its row into an audio track, or the empty Tracks area below existing tracks. The **Drag to Logic** control also remains available.
4. If a destination rejects the drag, right-click the row, choose **Reveal in Finder**, and drag from Finder.

Dragging sends the original file URL. Scanning and previewing do not convert WAV to AIFF or modify the original file. The File column shows the original extension. The optional semantic worker can create a temporary decoded WAV for otherwise unsupported formats, and deletes that temporary file afterward; it does not replace the source or produce an AIFF library copy. If AIFF appears, compare the original in Finder with Logic's project copy before concluding which app created it.

Preview is independent of Logic's transport and plays at original tempo and pitch. It does not follow project BPM/key or route through Logic's mixer. Direct dragging and audio-device behavior need validation in your Logic setup.

## Keep the library up to date

While the app runs, recursive folder events trigger a scan after a short debounce. Changes during a scan queue another pass. New/changed files are read; unchanged files reuse stored metadata. At launch the app also checks for additions made while it was closed.

Use **Rescan folders** as a fallback, particularly after reconnecting an external or network drive. A missing or unreadable source reports an issue and retains its catalog and annotations. Moving an entire pack to a different path does not yet automatically relink it.

Local data is in `~/Library/Application Support/Sample Atlas/`. It stays outside the public repository. A normal source-code update does not wipe that data. Avoid removing and re-adding sources to refresh them: source removal removes that source's catalog annotations (never its audio).

## Optional semantic search

Run in a second terminal, from the repository:

```sh
./scripts/setup-semantic.sh
```

Open **Sound search settings**, paste the printed Python and worker paths, and choose **Build / Update Sound Index**. The first run downloads the model and can take time. When ready, enable **Search by sound** and try a description such as `airy noise riser`.

After restarting, choose **Load Existing Index**. After new files are scanned, choose **Build / Update Sound Index** again; expensive audio embedding updates remain manual. Audio stays local, but the first model download needs internet access. Search results are similarity-ranked, and their quality on a production library is still experimental.

## Next development

1. Validate direct row drag, auto-preview and filesystem events in Logic with a real pack; test audio interface output selection.
2. Package a proper `.app` and add a straightforward installer.
3. Add audio BPM/key estimation, confidence, manual corrections and reliable loop/one-shot detection for unlabeled files.
4. Measure semantic retrieval latency and relevance on representative production queries; add similar-sound search and index coverage/status.
5. Add folder tree browsing, duration filters, duplicate grouping and moved-library relinking.
6. Add tempo/pitch-matched preview and optional Logic integration.
