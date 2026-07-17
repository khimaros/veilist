# a minimal flutter_driver client that talks to a running flutter app over its
# dart vm service. flutter paints to a canvas on every platform, so the driver
# extension (enabled by test/driver/app.dart) is the one locator surface that
# works identically on android, linux, and web. appium wraps this same protocol
# for android; here we speak it directly so linux and web run the same flows.

import json
import time

from websocket import create_connection

DEFAULT_TIMEOUT_MS = 20000


class DriverError(RuntimeError):
    pass


class VMDriver:
    """connects to the app's vm service and invokes ext.flutter.driver."""

    def __init__(self, ws_url, connect_timeout=60):
        self._ws = create_connection(ws_url, timeout=connect_timeout, max_size=None)
        self._id = 0
        self.isolate_id = self._main_isolate()
        self._await_extension()
        # the connection-status progress bar animates forever while attaching;
        # without this, waitFor would block on "no pending frames".
        self.command({"command": "set_frame_sync", "enabled": "false"})

    def _rpc(self, method, params):
        self._id += 1
        rid = self._id
        self._ws.send(
            json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        )
        while True:
            msg = json.loads(self._ws.recv())
            if msg.get("id") != rid:
                continue  # a stream event, not our reply
            if "error" in msg:
                raise DriverError(msg["error"])
            return msg["result"]

    def _main_isolate(self, retries=60, interval=0.5):
        # the isolate can register a moment after the vm service starts (more so
        # in profile/aot builds), so poll rather than check once.
        for _ in range(retries):
            isolates = self._rpc("getVM", {}).get("isolates", [])
            for iso in isolates:
                if "main" in iso.get("name", ""):
                    return iso["id"]
            if isolates:
                return isolates[0]["id"]
            time.sleep(interval)
        raise DriverError("no dart isolates found")

    def _await_extension(self, retries=60, interval=0.5):
        for _ in range(retries):
            iso = self._rpc("getIsolate", {"isolateId": self.isolate_id})
            if "ext.flutter.driver" in iso.get("extensionRPCs", []):
                return
            time.sleep(interval)
        raise DriverError("ext.flutter.driver never registered (not a driver build?)")

    def command(self, cmd):
        """send one flutter_driver command; cmd fields are all strings."""
        # a waitFor blocks app-side for up to its own `timeout` ms before it
        # replies, so the socket read must wait at least that long (plus slack)
        # or long convergence waits die on a premature socket timeout.
        timeout_ms = int(cmd.get("timeout", DEFAULT_TIMEOUT_MS))
        self._ws.settimeout(timeout_ms / 1000 + 30)
        params = {"isolateId": self.isolate_id}
        params.update({k: str(v) for k, v in cmd.items()})
        result = self._rpc("ext.flutter.driver", params)
        if str(result.get("isError", False)).lower() == "true":
            raise DriverError(result.get("response"))
        return result.get("response", {})

    def close(self):
        try:
            self._ws.close()
        except Exception:
            pass


# ---- finders (raw flutter_driver json; sub-finders are json-encoded) --------


def key(name):
    return {"finderType": "ByValueKey", "keyValueString": name, "keyValueType": "String"}


def text(value):
    return {"finderType": "ByText", "text": value}


def type_(name):
    return {"finderType": "ByType", "type": name}


def tooltip(value):
    return {"finderType": "ByTooltipMessage", "text": value}


def descendant(of, matching, first=False):
    # firstMatchOnly must stay false: a first-only finder calls .first on its
    # candidates, which throws "Bad state: No element" on an empty match and so
    # breaks waitForAbsent. matches inside a single tile are unique anyway.
    return {
        "finderType": "Descendant",
        "of": json.dumps(of),
        "matching": json.dumps(matching),
        "matchRoot": "false",
        "firstMatchOnly": "true" if first else "false",
    }


def ancestor(of, matching, first=False):
    return {
        "finderType": "Ancestor",
        "of": json.dumps(of),
        "matching": json.dumps(matching),
        "matchRoot": "false",
        "firstMatchOnly": "true" if first else "false",
    }


def in_tile(item_text, child_type, tile_type="ListTile"):
    tile = ancestor(text(item_text), type_(tile_type))
    return descendant(tile, type_(child_type))


# ---- actions (mirror e2e-appium/flutter_ui.py so scenarios are shared) -------


def _with(finder, **extra):
    cmd = dict(finder)
    cmd.update(extra)
    return cmd


def wait_for(drv, finder, timeout=DEFAULT_TIMEOUT_MS):
    drv.command(_with(finder, command="waitFor", timeout=timeout))


def wait_absent(drv, finder, timeout=DEFAULT_TIMEOUT_MS):
    drv.command(_with(finder, command="waitForAbsent", timeout=timeout))


def present(drv, finder, timeout=DEFAULT_TIMEOUT_MS):
    try:
        wait_for(drv, finder, timeout)
        return True
    except DriverError:
        return False


def tap(drv, finder, timeout=DEFAULT_TIMEOUT_MS):
    drv.command(_with(finder, command="tap", timeout=timeout))


def enter_text(drv, finder, value, timeout=DEFAULT_TIMEOUT_MS):
    tap(drv, finder, timeout)  # focus the field first
    drv.command({"command": "enter_text", "text": value, "timeout": str(timeout)})


def get_text(drv, finder, timeout=DEFAULT_TIMEOUT_MS):
    return drv.command(_with(finder, command="get_text", timeout=timeout)).get("text")


def request_data(drv, message, timeout=DEFAULT_TIMEOUT_MS):
    """send a string to the app's driver DataHandler (test/driver/app.dart) and
    return its reply. the app's e2e control channel (offline/online/etc.)."""
    return drv.command(
        {"command": "request_data", "message": message, "timeout": timeout}
    ).get("message")


def scroll(drv, finder, dx, dy, duration_ms=1500, frequency=30, timeout=DEFAULT_TIMEOUT_MS):
    drv.command(
        _with(
            finder,
            command="scroll",
            dx=dx,
            dy=dy,
            duration=duration_ms * 1000,
            frequency=frequency,
            timeout=timeout,
        )
    )


def offset(drv, finder, kind="center", timeout=DEFAULT_TIMEOUT_MS):
    """a widget's screen coordinates. uses render geometry (localToGlobal), so
    unlike the diagnostics tree it works in profile/release builds too."""
    r = drv.command(_with(finder, command="get_offset", offsetType=kind, timeout=timeout))
    return r.get("dx"), r.get("dy")


def item_order(drv, texts):
    """the given item texts ordered top-to-bottom by on-screen position. the
    driver has no element-rect command, but get_offset gives each widget's
    center, which is all reorder assertions need."""
    ys = {}
    for t in texts:
        try:
            ys[t] = offset(drv, text(t))[1]
        except DriverError:
            pass
    return sorted(ys, key=ys.get)


def settle(drv, seconds=2.0):
    # frame sync is disabled, so give animated transitions (reorder, dialogs)
    # a moment to finish before asserting on the result.
    time.sleep(seconds)


def home(drv, tries=6):
    """return to the listing page. desktop/web have no hardware back button, so
    pop detail routes via the app bar's back button (tooltip 'Back')."""
    for _ in range(tries):
        if present(drv, key("fab_new_list"), 2500):
            return
        try:
            tap(drv, tooltip("Back"), 2500)
        except DriverError:
            pass
    wait_for(drv, key("fab_new_list"), 5000)

