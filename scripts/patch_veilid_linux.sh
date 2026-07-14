#!/usr/bin/env bash
# the veilid flutter plugin's linux cmake (rust.cmake) locates its rust crate
# with `git rev-parse`, assuming it is built inside the veilid monorepo. that
# resolves to a nonexistent path when veilid is a pub git dependency in another
# app, so point corrosion at the plugin's own rust crate instead. idempotent;
# re-run after `flutter pub get` (which restores the pub cache). see DESIGN.md.
set -euo pipefail

CMAKE="$(ls "$HOME"/.pub-cache/git/veilid-*/veilid-flutter/linux/rust.cmake 2>/dev/null | head -1)"
if [ -z "$CMAKE" ]; then
  echo "veilid plugin not found in pub cache; run 'flutter pub get' first" >&2
  exit 1
fi

if grep -q '${repository_root}/../veilid/Cargo.toml' "$CMAKE"; then
  sed -i \
    's#${repository_root}/../veilid/Cargo.toml#${CMAKE_CURRENT_LIST_DIR}/../rust/Cargo.toml#' \
    "$CMAKE"
  echo "patched $CMAKE"
else
  echo "already patched: $CMAKE"
fi
