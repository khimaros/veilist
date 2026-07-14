# veilist-specific ui flows built on the generic flutter_ui helpers. keeping
# them here lets each test read as a short user story.

import uuid

import flutter_ui as ui

APP_PACKAGE = "com.khimaros.veilist"
LISTING_ANCHOR = ui.key("fab_new_list")
EMPTY_LIST_TEXT = "no items yet - add one below"


def unique(prefix):
    # unique per call so tests stay independent even though they share one
    # installed app (the list-of-lists persists across a session).
    return f"{prefix}-{uuid.uuid4().hex[:6]}"


# cold start (profile install, first-frame raster) can take many seconds on an
# emulator, so the initial wait is generous.
COLD_START_TIMEOUT = 45000


def wait_for_listing(driver, timeout=COLD_START_TIMEOUT):
    """block until the listing page is shown, without pressing back. used at
    each test's start, where the app may still be booting to its first frame."""
    ui.wait_for(driver, LISTING_ANCHOR, timeout)


def ensure_listing(driver, tries=5):
    """return to the listing after a test, dismissing any dialog or detail
    route. the hardware back button on the root route backgrounds the app,
    which pauses the flutter engine and hangs the driver, so we only press back
    when the listing is genuinely absent (warm app) and reactivate as a last
    resort."""
    if ui.present(driver, LISTING_ANCHOR, timeout=4000):
        return
    for _ in range(tries):
        try:
            driver.back()
        except Exception:
            pass
        if ui.present(driver, LISTING_ANCHOR, timeout=3000):
            return
    try:
        driver.activate_app(APP_PACKAGE)
    except Exception:
        pass
    ui.wait_for(driver, LISTING_ANCHOR, 10000)


def create_list(driver, name):
    ui.tap(driver, LISTING_ANCHOR)
    ui.enter_text(driver, ui.key("prompt_field"), name)
    ui.tap(driver, ui.key("prompt_action"))
    ui.wait_for(driver, ui.text(name))


def open_list(driver, name):
    ui.tap(driver, ui.text(name))
    # loading must resolve to real content, not spin forever (R12).
    ui.wait_for(driver, ui.text(EMPTY_LIST_TEXT), timeout=30000)


def add_item(driver, item_text):
    ui.enter_text(driver, ui.key("add_field"), item_text)
    ui.tap(driver, ui.key("add_button"))
    ui.wait_for(driver, ui.text(item_text))
