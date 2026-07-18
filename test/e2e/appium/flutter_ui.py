# thin wrappers over the appium flutter-driver protocol. finders locate
# widgets by the same keys/text/tooltips the app assigns; actions wait for a
# widget before touching it so tests do not race the ui. flutter renders to a
# canvas (no native view tree), so every locator goes through the driver
# extension, not uiautomator2.

import time

from appium_flutter_finder import FlutterElement, FlutterFinder

finder = FlutterFinder()

# default wait for a widget to appear, in milliseconds. veilid is never on the
# critical path for local-first flows, so the ui settles quickly.
DEFAULT_TIMEOUT = 20000


def key(name):
    return finder.by_value_key(name)


def text(value):
    return finder.by_text(value)


def tooltip(value):
    return finder.by_tooltip(value)


def type_(name):
    return finder.by_type(name)


def descendant(of, matching):
    return finder.by_descendant(of, matching)


def ancestor(of, matching):
    return finder.by_ancestor(of, matching)


def in_tile(item_text, child_type, tile_type="ListTile"):
    """a widget of child_type inside the same tile as item_text. lets a test
    target one row's checkbox/handle without knowing the item's generated id."""
    tile = ancestor(text(item_text), type_(tile_type))
    return descendant(tile, type_(child_type))


def wait_for(driver, find, timeout=DEFAULT_TIMEOUT):
    driver.execute_script("flutter:waitFor", find, timeout)
    return FlutterElement(driver, find)


def wait_absent(driver, find, timeout=DEFAULT_TIMEOUT):
    driver.execute_script("flutter:waitForAbsent", find, timeout)


def present(driver, find, timeout=DEFAULT_TIMEOUT):
    try:
        wait_for(driver, find, timeout)
        return True
    except Exception:
        return False


def tap(driver, find, timeout=DEFAULT_TIMEOUT):
    el = wait_for(driver, find, timeout)
    el.click()
    return el


def enter_text(driver, field, value, timeout=DEFAULT_TIMEOUT):
    # focus the field, then let the driver drive the platform text input.
    tap(driver, field, timeout)
    driver.execute_script("flutter:enterText", value)


def get_text(driver, find, timeout=DEFAULT_TIMEOUT):
    return wait_for(driver, find, timeout).text


def scroll(driver, find, dx, dy, duration_ms=1500, frequency=30):
    driver.execute_script(
        "flutter:scroll",
        find,
        {
            "dx": dx,
            "dy": dy,
            "durationMilliseconds": duration_ms,
            "frequency": frequency,
        },
    )


def long_press(driver, find, duration_ms=1000, timeout=DEFAULT_TIMEOUT):
    wait_for(driver, find, timeout)
    driver.execute_script(
        "flutter:longTap", find, {"durationMilliseconds": duration_ms}
    )


def settle(driver, seconds=2.0):
    # let animated transitions (reorder, dialogs) finish before asserting.
    time.sleep(seconds)


def home(driver, tries=6):
    """return to the listing by popping detail routes via the app-bar back
    button (tooltip 'Back'); the listing has none, so this stops there. matches
    flutter_vm.home so the shared scenarios run identically here."""
    for _ in range(tries):
        if present(driver, key("fab_new_list"), 2500):
            return
        try:
            tap(driver, tooltip("Back"), 2500)
        except Exception:
            pass
    wait_for(driver, key("fab_new_list"), 5000)


def item_order(driver, texts, list_type="ReorderableListView", depth=30):
    """the given item texts ordered as they appear in the list's render
    subtree, which serializes children top-to-bottom. lets a test assert a
    reorder without reading screen coordinates (the driver exposes no element
    rect). texts not found in the tree are dropped."""
    tree = str(
        driver.execute_script(
            "flutter:getRenderObjectDiagnostics",
            type_(list_type),
            {"includeProperties": True, "subtreeDepth": depth},
        )
    )
    found = {t: tree.find(t) for t in texts}
    found = {t: pos for t, pos in found.items() if pos >= 0}
    return sorted(found, key=found.get)
