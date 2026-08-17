# requirements

product requirements for veilist. it is never okay to regress on these in a
release. each requirement has a stable id so tests and the roadmap can refer
to it.

## functional

- **R1 list sharing.** a user can share any list with other people via a link.
  the link is also shown as a qr code, and a device with a camera can join the
  list by scanning that code instead of typing or pasting the link.
- **R2 app deep link.** opening a share link on a device that has the app opens
  that list directly in the app.
- **R3 web fallback.** opening a share link on a device without the app reaches
  a web ui that shows the list. the web ui also works in a normal desktop
  browser with no install.
- **R4 collaboration.** anyone a list is shared with can edit it. edits are
  attributable to the member who made them and a member's contributions can be
  ignored (revoked) by others.
- **R5 list of lists.** the app keeps track of every list the user has created
  or opened from someone else.
- **R6 manage from listing.** from the listing page the user can view a list,
  delete an individual list, and share a list.
- **R15 participant count.** a shared list surfaces how many members it has, and
  the share affordance reflects that the list is shared (distinct from a private,
  never-shared list).
- **R7 item states.** a list item has a state. clicking the item's checkbox
  toggles it between open and complete; pressing and holding the checkbox opens
  a picker for the other states. the release ships new/active/complete/blocked
  (`[ ]`, `[@]`, `[x]`, `[!]`); the model must extend to the full state set
  (obsolete, undecided, deferred) without changing the share link format or
  on-the-wire data.
- **R11 edit and reorder.** a list item's text can be edited and items can be
  reordered.
- **R12 local-first.** creating a list and creating/editing items work
  immediately without waiting for the veilid network; changes are saved on the
  device and sync when connected. an edit made offline survives leaving the
  list, backgrounding the app, and reconnecting, and goes out once the app is
  open again with a working network - the app runs no foreground service, so it
  does not promise to sync while it is in the background.
- **R16 no silent data loss.** nothing but a deliberate delete removes items
  from a list. a device never publishes less for its own member slot than it
  published before, so a read that fails, comes back partial, or comes back
  empty - including a record the network has forgotten while everyone was away -
  can never turn the next edit into a wipe. this device's own contribution is
  kept on-device, not only in the dht record.
- **R13 connection + sync status.** the veilid connection state is visible in
  the ui, and while editing a list the ui indicates whether changes are synced,
  syncing, or saved offline. "synced" means data was actually exchanged: a read
  that reached nothing is never reported as being in sync.
- **R14 theme.** dark mode is the default, with a material-you (device dynamic)
  accent color where available and a seed-color fallback.

## non-functional

- **R8 private by default.** list contents travel only over veilid and are
  never visible to a central server. the web fallback runs veilid in the
  browser (wasm), so no gateway server sees list data.
- **R9 deterministic builds.** toolchains are pinned (mise) and the veilid
  dependency is pinned to a released tag.
- **R10 minimal dependencies.** prefer the veilid sdk and the flutter/dart
  standard library over adding third-party packages.

## item state set (R7)

the full set, in canonical order. glyphs match the user's text notation so a
list reads the same in the app and in plain text. a checkbox tap moves between
new and complete; the shipped states in between are reached by pressing and
holding the checkbox.

| glyph | state     | shipped in v1 |
|-------|-----------|---------------|
| `[ ]` | new       | yes           |
| `[@]` | active    | yes           |
| `[x]` | complete  | yes           |
| `[~]` | obsolete  | later         |
| `[?]` | undecided | later         |
| `[!]` | blocked   | yes           |
| `[>]` | deferred  | later         |
