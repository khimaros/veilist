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
- check items off - the checkbox cycles through item states (new, active, and
  complete today; more states later)
- collaborate: anyone you share with can edit, and edits are attributable to
  the person who made them
- a list you open from someone else stays read-only ("syncing") until its first
  data arrives, so you never edit an empty copy that the real list overwrites;
  once it has synced, it re-opens instantly and is editable while it refreshes
- every list stays current while the app is open, even the ones you have not
  opened, so the roster reflects what others have changed
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
make test-e2e       # browser e2e: real veilid-in-wasm in chrome (python)
make test-ui-e2e    # true ui e2e: the real app on an android emulator (appium)
make test-ui-e2e-two # two emulators: live collaboration over the dht
```

the two android targets need a one-time `make android-e2e-setup`. see
[CONTRIBUTING.md](CONTRIBUTING.md) for the test layers and the emulator setup.

see [CONTRIBUTING.md](CONTRIBUTING.md) for the full developer workflow and
[DESIGN.md](DESIGN.md) for the architecture.
