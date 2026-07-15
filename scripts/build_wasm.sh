#!/usr/bin/env bash
# build the veilid wasm blob into web/wasm/ so the flutter web build runs a full
# veilid node in the browser (REQUIREMENTS.md R3, R8). the blob is compiled from
# the exact pinned veilid source that pub fetched for our git dependency, so its
# abi matches the dart bindings. wasm-bindgen must match the version veilid
# depends on or the browser glue will not line up.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/web/wasm"

# keep this in step with the wasm-bindgen version in the veilid Cargo.lock.
WBGEN_VERSION="0.2.121"

# rust tools come from mise. under mise, cargo's home is the per-version rust
# dir, so `cargo install` tools (wasm-bindgen-cli) land in its bin. set it
# explicitly and put it on PATH so a rust version bump does not orphan them.
export CARGO_HOME="$(mise where rust 2>/dev/null)"
export PATH="$CARGO_HOME/bin:$HOME/.cargo/bin:$PATH"
export CARGO_TARGET_DIR="$ROOT/build/wasm-target"

VEILID_SRC="$(find "$HOME/.pub-cache/git" -maxdepth 1 -type d -name 'veilid-*' \
  2>/dev/null | head -1)"
if [ -z "$VEILID_SRC" ]; then
  echo "veilid source not found in pub cache; run 'flutter pub get' first" >&2
  exit 1
fi
echo "veilid source: $VEILID_SRC"

rustup target add wasm32-unknown-unknown
if ! wasm-bindgen --version 2>/dev/null | grep -q "$WBGEN_VERSION"; then
  echo "installing wasm-bindgen-cli $WBGEN_VERSION ..."
  cargo install wasm-bindgen-cli --version "$WBGEN_VERSION"
fi

echo "compiling veilid-flutter to wasm (this takes a while) ..."
( cd "$VEILID_SRC/veilid-flutter" &&
  cargo build --target wasm32-unknown-unknown --no-default-features \
    --features=default-wasm -p veilid-flutter )

mkdir -p "$OUT"
wasm-bindgen --out-dir "$OUT" --target web \
  "$CARGO_TARGET_DIR/wasm32-unknown-unknown/debug/veilid_flutter.wasm"
echo "wrote veilid wasm blob to $OUT"
