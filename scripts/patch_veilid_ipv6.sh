#!/usr/bin/env bash
# veilid only starts its PublicInternet routing domain for an address family
# that has a default route WITH a gateway address. an ipv6-only mobile carrier
# (464xlat, e.g. t-mobile us) has neither: the cellular link is point-to-point,
# so its ipv6 default route names no gateway, and veilid skips the clat
# interface that carries the ipv4 one. the node then fails network startup once
# a second forever and never attaches. veilid main already dropped the ipv6
# gateway requirement (a unicast-global address is enough) but no release has
# it, so apply the same one-line change to the pinned source. idempotent;
# re-run after `flutter pub get`, which restores the pub cache. delete this
# once the pinned tag carries the change (the anchor check below will say so).
# see DESIGN.md ("native builds").
set -euo pipefail

STATE=veilid-core/src/network_manager/network/native/network_state.rs
GATED='let ipv6_global = ipv6_local && has_v6_default_route && raw.has_unicast_global_ipv6;'
PATCHED='let ipv6_global = ipv6_local \&\& raw.has_unicast_global_ipv6; // veilist: no gateway needed'

shopt -s nullglob
SOURCES=("$HOME"/.pub-cache/git/veilid-*/"$STATE")
if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "veilid source not found in pub cache; run 'flutter pub get' first" >&2
  exit 1
fi

for src in "${SOURCES[@]}"; do
  if grep -q 'veilist: no gateway needed' "$src"; then
    echo "already patched: $src"
    continue
  fi
  # fail loudly if a future veilid changed this line, so a silent no-op patch
  # never ships a build that cannot attach on mobile data.
  if ! grep -qF "$GATED" "$src"; then
    echo "patch anchor not found in $src; veilid may have fixed this upstream" >&2
    exit 1
  fi
  sed "s|$GATED|$PATCHED|" "$src" > "$src.tmp"
  mv "$src.tmp" "$src"
  echo "patched $src"
done
