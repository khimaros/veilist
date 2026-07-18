# true end-to-end ui coverage on one emulator: drives the real widgets the way
# a person would and asserts on what the screen shows. each test maps to a
# product requirement (see REQUIREMENTS.md). local-first flows (create/open/
# edit) never wait on veilid, so these run fast and offline.

import time

import pytest

import app_flows as flows
import flutter_ui as ui


@pytest.fixture(autouse=True)
def on_listing(driver):
    # every test starts and ends on the listing page, so the module-scoped
    # driver can be reused without one test's leftover route breaking the next.
    # setup waits (never pressing back, so a cold-booting app is not sent to the
    # background); teardown actively recovers.
    flows.wait_for_listing(driver)
    yield
    flows.ensure_listing(driver)


def test_connection_status_visible(driver):
    # R13: the veilid connection state is always on the listing app bar.
    ui.wait_for(driver, ui.key("connection_status"))


def test_created_lists_are_tracked(driver):
    # R5 + R12: creating lists works immediately and every one is remembered.
    a = flows.unique("alpha")
    b = flows.unique("beta")
    flows.create_list(driver, a)
    flows.create_list(driver, b)
    ui.wait_for(driver, ui.text(a))
    ui.wait_for(driver, ui.text(b))


def test_open_list_does_not_spin_forever(driver):
    # R12 + regression: opening a freshly created list resolves to content
    # instead of an endless spinner.
    name = flows.unique("open")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    ui.wait_for(driver, ui.text(flows.EMPTY_LIST_TEXT))
    # R13: while editing, the sync indicator is present.
    assert ui.present(driver, ui.tooltip("changes are synced")) or ui.present(
        driver, ui.tooltip("changes are syncing")
    ) or ui.present(driver, ui.tooltip("changes are offline"))


def test_add_and_toggle_item_state(driver):
    # R7: a checkbox tap toggles the item between open and complete.
    name = flows.unique("toggle")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    flows.add_item(driver, "wash dishes")
    glyph = ui.in_tile("wash dishes", "StateGlyphButton")
    tile = ui.ancestor(ui.text("wash dishes"), ui.type_("ListTile"))
    x_glyph = ui.descendant(tile, ui.text("x"))  # complete
    ui.tap(driver, glyph)
    ui.wait_for(driver, x_glyph)
    ui.tap(driver, glyph)  # back to new
    ui.wait_absent(driver, x_glyph)


def test_pick_item_state_by_holding_the_checkbox(driver):
    # R7: press and hold the checkbox to reach the states a tap does not.
    name = flows.unique("pick")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    flows.add_item(driver, "call plumber")
    glyph = ui.in_tile("call plumber", "StateGlyphButton")
    tile = ui.ancestor(ui.text("call plumber"), ui.type_("ListTile"))
    ui.long_press(driver, glyph)
    ui.wait_for(driver, ui.key("state_picker"))
    ui.tap(driver, ui.key("state_blocked"))
    ui.wait_absent(driver, ui.key("state_picker"))
    ui.wait_for(driver, ui.descendant(tile, ui.text("!")))  # blocked


def test_edit_item_text(driver):
    # R11: an item's text can be edited.
    name = flows.unique("edit")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    flows.add_item(driver, "byy milk")
    ui.tap(driver, ui.text("byy milk"))  # tap the row to edit
    ui.enter_text(driver, ui.key("edit_field"), "buy milk")
    ui.tap(driver, ui.text("save"))
    ui.wait_for(driver, ui.text("buy milk"))
    ui.wait_absent(driver, ui.text("byy milk"))


def test_reorder_items(driver):
    # R11: items can be reordered by dragging the handle.
    name = flows.unique("reorder")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    flows.add_item(driver, "row one")
    flows.add_item(driver, "row two")
    pair = ["row one", "row two"]
    assert ui.item_order(driver, pair) == ["row one", "row two"]
    # drag row one's handle down past row two.
    handle = ui.in_tile("row one", "Icon")
    ui.scroll(driver, handle, dx=0, dy=160, duration_ms=1600)
    # the reorder animates and then persists; poll until the order flips.
    flipped = ["row two", "row one"]
    for _ in range(10):
        if ui.item_order(driver, pair) == flipped:
            break
        time.sleep(1)
    assert ui.item_order(driver, pair) == flipped


def test_swipe_to_delete_item(driver):
    # R11/R6: an item can be removed (swipe-to-dismiss).
    name = flows.unique("dismiss")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    flows.add_item(driver, "throwaway")
    # a leftward swipe on the row dismisses it; scroll with a big negative dx.
    ui.scroll(driver, ui.text("throwaway"), dx=-600, dy=0, duration_ms=600)
    ui.wait_absent(driver, ui.text("throwaway"))


def test_share_dialog_shows_qr_and_links(driver):
    # R1 + regression: sharing opens a dialog with a scannable qr and both link
    # forms (this dialog used to render as an empty overlay).
    name = flows.unique("share")
    flows.create_list(driver, name)
    flows.open_list(driver, name)
    ui.tap(driver, ui.tooltip("share"))
    ui.wait_for(driver, ui.type_("QrImageView"))
    link = ui.get_text(driver, ui.key("app_link_value"))
    assert link.startswith("veilist://"), link
    ui.tap(driver, ui.text("done"))


def test_open_link_rejects_invalid(driver):
    # R2 path: pasting something that is not a veilist link is rejected.
    ui.tap(driver, ui.key("open_link_button"))
    ui.enter_text(driver, ui.key("prompt_field"), "https://example.com/not-a-list")
    ui.tap(driver, ui.key("prompt_action"))
    ui.wait_for(driver, ui.text("not a veilist link"))


def test_delete_list_from_listing(driver):
    # R6: a list can be deleted from the listing via its overflow menu.
    name = flows.unique("todelete")
    flows.create_list(driver, name)
    menu = ui.descendant(
        ui.ancestor(ui.text(name), ui.type_("ListTile")),
        ui.type_("PopupMenuButton<String>"),
    )
    ui.tap(driver, menu)
    ui.tap(driver, ui.text("delete"))  # menu entry
    ui.tap(driver, ui.text("delete"))  # confirm dialog
    ui.wait_absent(driver, ui.text(name))
