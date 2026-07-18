# appium ui e2e

true ui end-to-end tests for veilist. python + [uv](https://docs.astral.sh/uv/)
+ [appium](https://appium.io) flutter-driver, driving the real widgets on
android emulators. no fakes, no test hook - the app behaves exactly as it does
for a person.

run from the repo root (one-time `make android-e2e-setup` first, for the
emulator + system image + avds):

```
make test-ui-e2e        # one emulator: all single-device flows
make test-ui-e2e-two    # two emulators: adds live collaboration over the dht
```

both wrap `test/scripts/appium_e2e_run.sh`, which installs the appium drivers
under `.appium/` on first run, builds the `test/driver/app.dart` apk (it enables the
flutter driver extension so appium can attach), boots the emulator(s), starts an
appium server, and runs pytest.

to run directly against an already-running appium server and emulator:

```
uv run pytest -v
```

## what it covers

- `test_smoke.py` - the app installs, launches, and appium can find a widget.
- `test_single_device.py` - every local-first flow: track created lists (R5,
  R12), open without an endless spinner (R12), add an item, toggle it complete
  and pick another state by holding the checkbox (R7), edit
  text, reorder, swipe-delete (R11), connection + sync status (R13), the share
  dialog with a qr and both link forms (R1), open-link validation (R2), and
  delete from the listing (R6).
- `test_two_device.py` - alice creates and shares a list on one emulator, bob
  opens the deep link on another, and their edits converge in both directions
  over the live dht (R1, R2, R4).

## notes

flutter paints to a canvas, so there is no native view tree; locators are widget
keys/types/text/tooltips resolved through the driver extension (`flutter_ui.py`).
the driver has no element-rect command, so reorder order is read from the list's
render-object diagnostics (`item_order`). pressing the hardware back button on
the root listing backgrounds the app and pauses the flutter engine, so tests
navigate back only from sub-routes (`app_flows.ensure_listing`).
