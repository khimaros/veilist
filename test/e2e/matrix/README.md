# compliance matrix

the cross-platform compliance suite (`make test-compliance`): one set of flows,
run against every frontend, reported as a matrix. the frontends cannot diverge
because they run the *same* flow code (`flows.py`) through a shared action
abstraction.

## layout

- `frontend.py` - the `Frontend` interface: user *actions* (create_list,
  add_item, toggle_item, set_item_state, edit_item, reorder_below, share,
  open_link, delete_list, ...) and *status queries* (has_item, item_order,
  title, sync_status, is_editable, ...). an action a frontend cannot perform
  raises `SkipFlow`, and the matrix records "skip" for that cell.
- `flows.py` - the compliance flows, written once against `Frontend`. `SINGLE`
  are single-device; `COLLAB` use a second instance via `f.peer()`.
- `widget_frontend.py` - `WidgetFrontend`, the interface over the flutter widget
  driver. linux and android share it because their driver adapters
  (`flutter_vm.py`, `test/e2e/appium/flutter_ui.py`) expose the same surface.
- `flutter_vm.py` - a small flutter_driver client over the app's dart vm service,
  used by the linux frontend (appium wraps the same protocol on android).
- `linux_frontend.py` - launches the profile desktop app on a headless display,
  driven over the dart vm service. fresh app per flow (veilid background work
  from one flow otherwise hangs the next).
- `android_frontend.py` - drives the app on an emulator via appium
  flutter-driver. reuses the `test/e2e/appium` infrastructure.
- `web_frontend.py` - drives the served web build in chrome via playwright and
  the `window.veilistTest` hook (flutter web renders to a canvas, so there is no
  dom to drive; the hook is the honest surface). ui-only flows (e.g. the
  hide-completed toggle) come back "skip".
- `matrix.py` - the single driver: runs each flow against each selected frontend
  and prints the frontend x flow matrix. non-zero exit if any flow FAILs.

## running

`make test-compliance` runs the matrix. `PLATFORMS` selects frontends (default
all three), e.g. `make test-compliance PLATFORMS=linux` for a quick local run.
it sets up each frontend's environment (profile build for linux; emulator +
appium + driver apk for android; e2e web build + chrome for web) via
`test/scripts/matrix_run.sh [linux] [android] [web]`. `make test-e2e` is a
shortcut for the web frontend alone (the browser e2e over real veilid-in-wasm).
to iterate on one frontend directly:

```
cd test/e2e/matrix
uv run python matrix.py --linux [--single]
```

## adding a feature

add or extend a flow in `flows.py` and, if it needs a new user action, add a
method to `Frontend` plus an implementation on each frontend that can perform it
(raise `SkipFlow` where it cannot). because every frontend runs the same flow,
a frontend that forgets the new behaviour shows up as a FAIL in its column - the
suites cannot silently drift.
