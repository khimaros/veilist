#!/usr/bin/env bash
# veilid's inspect_dht_record fanout initializes consensus_nodes with the first
# peer even when a subkey is unwritten (ValueSeqNum::NONE), then gates every
# subsequent peer behind `if answer_seq.is_some()` in inspect_record.rs. any
# sparse record with unwritten subkeys can therefore never reach its 3-node
# consensus count on those subkeys and never returns DoneEarly, forcing every
# online inspect to wait out the full 20-peer fanout (~8-15s).
#
# ValueSeqNum derives Ord over Option<u32> (NONE < Some(0)), so letting NONE
# enter the comparison allows three peers agreeing on NONE to reach consensus in
# one round-trip. a Some(seq) supersedes NONE only until then: a subkey at
# consensus takes no more updates, and the fanout stops once all of them are. an
# inspect can therefore report a written subkey as unwritten, so veilist never
# treats that as proof a slot is empty (see OpenList._confirmMine).
# idempotent; re-run after `flutter pub get`, which restores the pub cache.
# delete this once a pinned veilid release fixes sparse-subkey inspect consensus
# (the anchor check below will say so). see DESIGN.md ("native builds").
set -euo pipefail

INSPECT=veilid-core/src/storage_manager/inspect_record.rs
GATED='if answer_seq.is_some() {'
PATCHED='{ // veilist: count NONE toward inspect consensus'

shopt -s nullglob
SOURCES=("$HOME"/.pub-cache/git/veilid-*/"$INSPECT")
if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "veilid source not found in pub cache; run 'flutter pub get' first" >&2
  exit 1
fi

for src in "${SOURCES[@]}"; do
  if grep -q 'veilist: count NONE toward inspect consensus' "$src"; then
    echo "already patched: $src"
    continue
  fi
  # fail loudly if a future veilid changed this line, so a silent no-op patch
  # never ships a build with slow sparse-record inspects.
  if ! grep -qF "$GATED" "$src"; then
    echo "patch anchor not found in $src; veilid may have fixed this upstream" >&2
    exit 1
  fi
  sed "s|$GATED|$PATCHED|" "$src" > "$src.tmp"
  mv "$src.tmp" "$src"
  echo "patched $src"
done
