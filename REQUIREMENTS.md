# requirements

product requirements for veilist. it is never okay to regress on these in a
release. each requirement has a stable id so tests and the roadmap can refer
to it.

## functional

- **R1 list sharing.** a user can share any list with other people via a link.
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
  cycles it through the available states in order. the release ships
  new/active/complete (`[ ]`, `[@]`, `[x]`); the model must extend to the full
  state set (obsolete, undecided, blocked, deferred) without changing the share
  link format or on-the-wire data.
- **R11 edit and reorder.** a list item's text can be edited and items can be
  reordered.
- **R12 local-first.** creating a list and creating/editing items work
  immediately without waiting for the veilid network; changes are saved on the
  device and sync when connected.
- **R13 connection + sync status.** the veilid connection state is visible in
  the ui, and while editing a list the ui indicates whether changes are synced,
  syncing, or saved offline.
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

the full set and the order the checkbox cycles through. glyphs match the
user's text notation so a list reads the same in the app and in plain text.

| glyph | state     | shipped in v1 |
|-------|-----------|---------------|
| `[ ]` | new       | yes           |
| `[@]` | active    | yes           |
| `[x]` | complete  | yes           |
| `[~]` | obsolete  | later         |
| `[?]` | undecided | later         |
| `[!]` | blocked   | later         |
| `[>]` | deferred  | later         |
