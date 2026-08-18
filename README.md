# veilist

simple, private list sharing over the [veilid](https://veilid.com) network.

make a list, share it with a link, and everyone with the link edits it
together. list contents travel only over veilid - no server ever sees them.
open a link on a phone with the app and it opens in the app; open it anywhere
else and it opens in a web page that runs veilid right in the browser.

## status

early development. see [ROADMAP.md](ROADMAP.md) for what works and what is
next, and [REQUIREMENTS.md](REQUIREMENTS.md) for the product requirements.

## what it does

- keep a list of every list you have made or opened from someone else
- open, share, or delete any list from the listing page
- check items off - tapping the checkbox marks an item complete, and tapping it
  again re-opens it
- press and hold an item to pick another state: active or blocked (the rest of
  the notation - obsolete, undecided, deferred - comes later)
- join a list by scanning its qr code with the camera, instead of pasting the
  link (android and ios; in a browser wherever the page is served over https)
- collaborate: anyone you share with can edit, and edits are attributable to
  the person who made them
- opening a shared link shows a loading screen and goes straight into the list,
  instead of flashing the listing first
- a list you open from someone else stays read-only ("syncing") until its first
  data arrives, so you never edit an empty copy that the real list overwrites;
  once it has synced, it re-opens instantly and is editable while it refreshes
- every list stays current while the app is open, even the ones you have not
  opened, so the roster reflects what others have changed. they all catch up at
  once rather than one after another, so picking the app up on a second device
  does not wait through the whole roster
- a list someone else has changed since you last looked at it is marked on the
  listing, so you can see what moved without opening every list
- a list someone shared with you is editable with no connection, even if you
  have never added anything to it yourself - the edit is yours straight away and
  goes out when you are back
- your own edits are kept on your device as well as in the shared list, so a
  list nobody has touched for a while - one the network has stopped holding on
  to - comes back with your items intact rather than empty
- a list nobody edits is refreshed on the network in the background while the
  app is open, so it stays reachable to everyone you shared it with
- hide or show completed items from the list's app bar

## platforms

android, ios, linux, and web from one codebase. the web build is also the
in-browser fallback for people who do not have the app installed.

## build and run

toolchains are pinned with [mise](https://mise.jdx.dev). from the repo root:

```
mise install      # flutter + rust, as pinned in mise.toml
make              # build the app (alias for `make build`; default target web)
make run          # run it locally
```

the web build runs veilid in the browser via wasm. build the wasm blob once
(needs the rust toolchain) before the first web build or run:

```
make wasm         # compiles the veilid wasm blob into web/wasm/
```

## tests

```
make test           # dart unit + widget tests (fast, hermetic)
make test-e2e       # e2e: compliance flows on two android emulators over the real dht
make test-compliance PLATFORMS=linux  # same flows, faster desktop column (no emulator)
make test-compliance PLATFORMS=web    # web column (veilid-in-wasm in chrome)
```

`make test-e2e` (android) needs a one-time `make android-e2e-setup`. see
[CONTRIBUTING.md](CONTRIBUTING.md) for the test layers and the emulator setup.

see [CONTRIBUTING.md](CONTRIBUTING.md) for the full developer workflow,
[DESIGN.md](DESIGN.md) for the architecture, and
[DISTRIBUTION.md](DISTRIBUTION.md) for releases, app signing, and the f-droid /
izzyondroid path.
