#!/usr/bin/env python3
"""Persistent JSON-lines audio retrieval worker. All protocol output goes to stdout.

The catalog is read-only. The separate cache is keyed by model, audio fingerprint,
path, and windowing version. Hard filters are supplied as eligible IDs by Swift.
"""
from __future__ import annotations

import argparse
from collections import OrderedDict
from contextlib import redirect_stdout
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time

import numpy as np

MODEL = "laion/clap-htsat-unfused"
# Resolve and lock this revision in model-revision.txt; never silently mix model spaces.
REVISION = Path(__file__).with_name("model-revision.txt").read_text().strip()
VERSION = f"{MODEL}@{REVISION}:three-windows-v1"
RATE = 48_000
WINDOW = RATE * 10


def unit_rows(values):
    values = np.asarray(values, dtype=np.float32)
    norms = np.linalg.norm(values, axis=-1, keepdims=True)
    if not np.isfinite(values).all() or np.any(norms < 1e-9):
        raise ValueError("Invalid or empty embedding")
    return values / norms


def filtered_top_k(matrix, sample_ids, query, eligible_ids, k=None):
    """Exact filtered cosine search; stable tie ordering and no postfilter recall loss."""
    if not len(sample_ids) or not eligible_ids:
        return []
    mask = np.isin(sample_ids, np.asarray(eligible_ids, dtype=np.int64))
    positions = np.flatnonzero(mask)
    if not len(positions):
        return []
    # Score the resident contiguous matrix without copying potentially hundreds of MB.
    all_scores = matrix @ query
    scores = all_scores[positions]
    take = len(scores) if k is None else min(max(0, k), len(scores))
    if take == 0:
        return []
    # Include boundary ties, then sort by score and ID for deterministic retrieval.
    threshold = np.partition(scores, len(scores) - take)[len(scores) - take]
    candidates = np.flatnonzero(scores >= threshold)
    order = np.lexsort((sample_ids[positions[candidates]], -scores[candidates]))[:take]
    chosen = candidates[order]
    return [int(value) for value in sample_ids[positions[chosen]]]


class Engine:
    def __init__(self, catalog: str, cache: str):
        self.catalog = Path(catalog)
        self.catalog_db = sqlite3.connect(self.catalog.resolve().as_uri() + "?mode=ro", uri=True)
        self.cache = Path(cache)
        self.cache.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.cache / "embeddings.sqlite")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS embeddings(
            path TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, version TEXT NOT NULL,
            dimension INTEGER NOT NULL, vector BLOB NOT NULL)""")
        self.processor = self.model = None
        self.queries = OrderedDict()
        self.ids = np.empty(0, dtype=np.int64)
        self.matrix = np.empty((0, 512), dtype=np.float32)
        self.identity = None

    def rows(self):
        # Read-only URI rejects accidentally creating a new catalog at a mistyped path.
        return self.catalog_db.execute("SELECT id,path,fingerprint FROM samples WHERE available=1 ORDER BY id").fetchall()

    def data_version(self):
        return self.catalog_db.execute("PRAGMA data_version").fetchone()[0]

    def ensure_model(self):
        if self.model is None:
            import torch
            from transformers import ClapModel, ClapProcessor
            torch.set_num_threads(2)
            # CPU is the reproducible default; inference avoids contention with Logic's GPU usage.
            self.processor = ClapProcessor.from_pretrained(MODEL, revision=REVISION)
            self.model = ClapModel.from_pretrained(MODEL, revision=REVISION, use_safetensors=False).eval()

    def windows(self, path):
        import soundfile as sf
        from scipy.signal import resample_poly
        with tempfile.TemporaryDirectory(prefix="sample-atlas-") as temp:
            try:
                audio = sf.SoundFile(path)
            except (RuntimeError, sf.LibsndfileError):
                # Core Audio handles Apple-compressed CAF files that libsndfile cannot decode.
                converted = str(Path(temp) / "decoded.wav")
                subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEF32", path, converted],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
                audio = sf.SoundFile(converted)
            with audio:
                length, rate = len(audio), audio.samplerate
                if length == 0 or rate <= 0:
                    raise ValueError("Empty audio")
                window = min(length, rate * 10)
                starts = sorted({0, max(0, (length - window) // 2), max(0, length - window)})
                waves = []
                for start in starts:
                    audio.seek(start)
                    data = audio.read(window, dtype="float32", always_2d=True).mean(axis=1)
                    if rate != RATE:
                        divisor = math.gcd(rate, RATE)
                        data = resample_poly(data, RATE // divisor, rate // divisor).astype(np.float32)
                    if not np.isfinite(data).all():
                        raise ValueError("Non-finite audio")
                    waves.append(data[:WINDOW])
                return waves

    def audio_vector(self, path):
        import torch
        waves = self.windows(path)
        inputs = self.processor(audio=waves, sampling_rate=RATE, return_tensors="pt", padding=True)
        with torch.inference_mode():
            vectors = self.model.get_audio_features(**inputs).cpu().numpy()
        # Three windows capture beginning/middle/end without decoding entire long files into RAM.
        return unit_rows(unit_rows(vectors).mean(axis=0))

    def index(self, progress):
        self.ensure_model()
        rows = self.rows()
        changed = failures = 0
        for index, (_, path, fingerprint) in enumerate(rows):
            cached = self.db.execute("SELECT fingerprint,version FROM embeddings WHERE path=?", (path,)).fetchone()
            if cached == (fingerprint, VERSION):
                continue
            try:
                before = os.stat(path)
                expected_size, expected_time = fingerprint.split(":", 1)
                if before.st_size != int(expected_size) or abs(before.st_mtime - float(expected_time)) > 0.00001:
                    raise ValueError("Catalog is stale; rescan folders before sound indexing")
                vector = self.audio_vector(path)
                after = os.stat(path)
                if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                    raise ValueError("Audio changed while indexing; rescan and retry")
                self.db.execute("INSERT OR REPLACE INTO embeddings VALUES(?,?,?,?,?)",
                                (path, fingerprint, VERSION, vector.size, vector.astype("<f4").tobytes()))
                self.db.commit()  # each completed sample survives cancellation or process exit
                changed += 1
            except Exception as exc:
                failures += 1
                print(f"Skipped {Path(path).name}: {exc}", file=sys.stderr)
            if index % 10 == 0 or index + 1 == len(rows):
                progress(f"Analyzed {index + 1}/{len(rows)} · {changed} updated · {failures} failed")
        self.load()
        progress(f"{len(self.ids)} audio embeddings ready · {failures} failed")
        return {"indexed": changed, "failed": failures, "total": len(self.ids)}

    def load(self):
        vectors, ids = [], []
        cached = {row[0]: row[1:] for row in self.db.execute(
            "SELECT path,fingerprint,dimension,vector FROM embeddings WHERE version=?", (VERSION,))}
        for sample_id, path, fingerprint in self.rows():
            record = cached.get(path)
            if record and record[0] == fingerprint:
                vector = np.frombuffer(record[2], dtype="<f4")
                if vector.size != record[1] or vector.size != 512 or not np.isfinite(vector).all():
                    continue
                vectors.append(vector); ids.append(sample_id)
        self.ids = np.asarray(ids, dtype=np.int64)
        self.matrix = np.ascontiguousarray(vectors, dtype=np.float32) if vectors else np.empty((0, 512), dtype=np.float32)
        # Fingerprint the eligible catalog view to refresh resident vectors after catalog changes.
        self.identity = self.data_version()
        if not len(ids):
            raise ValueError("No matching audio embeddings. Build the sound index first.")

    def search(self, text, eligible):
        self.ensure_model()
        if self.data_version() != self.identity:
            self.load()
        text = " ".join(text.split())[:1000]
        if not text:
            return []
        if text not in self.queries:
            import torch
            inputs = self.processor(text=[text], return_tensors="pt", padding=True, truncation=True)
            with torch.inference_mode():
                vector = self.model.get_text_features(**inputs).cpu().numpy()[0]
            self.queries[text] = unit_rows(vector)
            if len(self.queries) > 128:
                self.queries.popitem(last=False)
        else:
            self.queries.move_to_end(text)
        return filtered_top_k(self.matrix, self.ids, self.queries[text], eligible)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--cache", required=True)
    args = parser.parse_args()
    protocol = sys.stdout
    def emit(message):
        protocol.write(json.dumps(message) + "\n"); protocol.flush()
    with redirect_stdout(sys.stderr):
        engine = Engine(args.catalog, args.cache)
        for line in sys.stdin:
            request = {}
            try:
                request = json.loads(line)
                request_id = request["id"]
                started = time.perf_counter()
                if request["command"] == "index":
                    result = engine.index(lambda status: emit({"id": request_id, "progress": status}))
                elif request["command"] == "load":
                    engine.load(); engine.ensure_model(); result = {"total": len(engine.ids)}
                elif request["command"] == "search":
                    result = {"ids": engine.search(request.get("text", ""), request.get("ids", []))}
                else:
                    raise ValueError("Unknown command")
                emit({"id": request_id, **result, "elapsed_ms": round((time.perf_counter() - started) * 1000, 2)})
            except Exception as exc:
                emit({"id": request.get("id"), "error": str(exc)})


if __name__ == "__main__":
    main()
