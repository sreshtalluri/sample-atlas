#!/bin/bash
set -euo pipefail
atlas_root="$(cd "$(dirname "$0")/.." && pwd)"
command -v uv >/dev/null || { echo 'Install uv first: https://docs.astral.sh/uv/getting-started/installation/'; exit 1; }
uv sync --project "$atlas_root/semantic" --python 3.12 --frozen
printf '\nPython executable: %s\nWorker script: %s\n' "$atlas_root/semantic/.venv/bin/python" "$atlas_root/semantic/worker.py"
printf 'The model downloads on first index/load. Audio stays on this Mac.\n'
