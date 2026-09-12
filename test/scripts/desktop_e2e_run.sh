#!/usr/bin/env bash
# builds the linux bundle and runs the desktop integration suite
# (test/e2e/desktop/) against it: the real app on a private headless display,
# read back with xprop the way a shell reads a window.
#
# usage: test/scripts/desktop_e2e_run.sh        (MODE=release|profile|debug)
set -euo pipefail

# this script lives at test/scripts/, so the repo root is two levels up.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

for tool in Xvfb xprop xwininfo; do
  command -v "$tool" >/dev/null || { echo "!! $tool not found" >&2; exit 1; }
done

MODE="${MODE:-release}"
echo "== building the linux $MODE bundle =="
mise exec -- flutter build linux "--$MODE"

cd test/e2e/desktop
uv sync >/dev/null
uv run pytest -v
