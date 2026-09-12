#!/usr/bin/env bash
# registers a built (or unpacked) linux bundle with the desktop: the entry the
# shell matches the window to - which is where the app's name and icon come from,
# and the only route to either under wayland, since it has no per-window icon
# protocol - plus the hicolor icon theme.
#
# usage: scripts/install_linux.sh [bundle_dir]     (PREFIX defaults to ~/.local)
#
# the release tarball IS the bundle and carries this as install.sh at its root,
# where it finds the bundle around itself; from the repo it finds the newest
# thing `make build-linux` produced. the app keeps running from the bundle, so
# the bundle must stay where it is.
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BUILD_MODES="release profile debug"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# a bundle is identified by the desktop integration it carries, which is exactly
# what this script installs.
is_bundle() { [ -d "$1/data/applications" ]; }

resolve_bundle() {
  if [ -n "${1:-}" ]; then echo "$1"; return; fi
  if is_bundle "$SELF_DIR"; then echo "$SELF_DIR"; return; fi
  for mode in $BUILD_MODES; do
    local candidate="$SELF_DIR/../build/linux/x64/$mode/bundle"
    if is_bundle "$candidate"; then echo "$candidate"; return; fi
  done
}

BUNDLE="$(resolve_bundle "${1:-}")"
if [ -z "$BUNDLE" ] || ! is_bundle "$BUNDLE"; then
  echo "!! no linux bundle found; build one with 'make build-linux'" >&2
  exit 1
fi
BUNDLE="$(cd "$BUNDLE" && pwd)"

entries=("$BUNDLE"/data/applications/*.desktop)
ENTRY="${entries[0]}"
NAME="$(basename "$ENTRY")"

APPS="$PREFIX/share/applications"
ICONS="$PREFIX/share/icons"
install -d "$APPS" "$ICONS"
install -m644 "$ENTRY" "$APPS/$NAME"

# the bundled entry carries a bare Exec (the binary name); point it at THIS
# bundle, or the shell lists an app it cannot launch.
BINARY="$BUNDLE/$(sed -n 's/^Exec=//p' "$ENTRY" | cut -d' ' -f1)"
[ -x "$BINARY" ] || { echo "!! $BINARY is not executable" >&2; exit 1; }
case "$BINARY" in *[[:space:]]*) BINARY="\"$BINARY\"";; esac
sed -i "s|^Exec=.*|Exec=$BINARY|" "$APPS/$NAME"

cp -r "$BUNDLE/data/icons/." "$ICONS/"

# without these the entry and the icon can take until the next login to appear.
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$APPS" || true
fi
if command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -q -t -f "$ICONS/hicolor" || true
fi

echo "installed $NAME -> $APPS"
echo "          icons -> $ICONS/hicolor"
echo "          running from $BUNDLE"
