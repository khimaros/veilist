#!/usr/bin/env bash
# the veilid flutter plugin's linux cmake (rust.cmake) locates its rust crate by
# walking up to the monorepo root (`git rev-parse --show-cdup`), assuming it is
# built inside the veilid checkout. as an external pub/git dependency that path
# does not exist; worse, when git refuses the ci checkout as "dubious ownership"
# the empty result makes `string(STRIP ...)` abort cmake outright. veilid ships
# no supported route for external linux desktop builds (the same code is on
# veilid main), so rewrite the rule to point corrosion at the plugin's own
# bundled rust crate. idempotent; re-run after `flutter pub get`, which restores
# the pub cache. see DESIGN.md ("native builds").
set -euo pipefail

shopt -s nullglob
CMAKES=("$HOME"/.pub-cache/git/veilid-*/veilid-flutter/linux/rust.cmake)
if [ ${#CMAKES[@]} -eq 0 ]; then
  echo "veilid plugin not found in pub cache; run 'flutter pub get' first" >&2
  exit 1
fi

for cmake in "${CMAKES[@]}"; do
  if grep -q 'veilid_rust_manifest' "$cmake"; then
    echo "already patched: $cmake"
    continue
  fi
  # replace the whole monorepo-root block (from the git lookup through the
  # corrosion import) with a direct reference to the plugin's bundled crate.
  awk '
    /^execute_process\(COMMAND git rev-parse/ {
      print "# veilist: upstream resolves the crate against the monorepo root,"
      print "# assuming an in-monorepo build; that path is absent when veilid is an"
      print "# external pub/git dependency. use the plugin bundled crate instead."
      print "get_filename_component(veilid_rust_manifest"
      print "    \"${CMAKE_CURRENT_LIST_DIR}/../rust/Cargo.toml\" REALPATH)"
      print "corrosion_import_crate(MANIFEST_PATH ${veilid_rust_manifest} CRATES veilid-flutter)"
      skip = 1
      next
    }
    skip { if (/^corrosion_import_crate\(/) skip = 0; next }
    { print }
  ' "$cmake" > "$cmake.tmp"
  # fail loudly if a future veilid layout slipped past the anchors, so a silent
  # no-op patch never ships a broken linux build.
  if ! grep -q 'veilid_rust_manifest' "$cmake.tmp" \
     || grep -qE 'git rev-parse|string\(STRIP' "$cmake.tmp"; then
    rm -f "$cmake.tmp"
    echo "patch anchors not found in $cmake; veilid layout may have changed" >&2
    exit 1
  fi
  mv "$cmake.tmp" "$cmake"
  echo "patched $cmake"
done
