"""the compliance flows, written once against the Frontend interface. the matrix
driver runs each against every frontend. an action a frontend cannot perform
raises SkipFlow (from the interface), so the flow is recorded skip, not fail.

each flow maps to a product requirement (see REQUIREMENTS.md). collaboration
flows take a second frontend via f.peer()."""

import uuid


def unique(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:6]}"


def _new_list(f, name):
    f.create_list(name)
    f.open_list(name)


# ---------------------------------------------------------------- single-device


def created_lists_are_tracked(f):  # R5
    a, b = unique("a"), unique("b")
    f.create_list(a)
    f.create_list(b)
    assert f.list_present(a) and f.list_present(b), f.lists()


def open_list_no_infinite_spinner(f):  # R12
    _new_list(f, unique("open"))
    assert f.is_empty()  # resolves to empty content, not a perpetual spinner


def add_and_cycle_item_state(f):  # R7
    _new_list(f, unique("cycle"))
    f.add_item("wash dishes")
    assert f.has_item("wash dishes")
    for _ in range(3):  # new -> active -> complete -> new; item stays present
        f.cycle_item("wash dishes")
    assert f.has_item("wash dishes")


def edit_item_text(f):  # R11
    _new_list(f, unique("edit"))
    f.add_item("byy milk")
    f.edit_item("byy milk", "buy milk")
    assert f.has_item("buy milk") and not f.has_item("byy milk")


def reorder_items(f):  # R11
    _new_list(f, unique("reorder"))
    f.add_item("kangaroo")
    f.add_item("platypus")
    assert f.item_order(["kangaroo", "platypus"]) == ["kangaroo", "platypus"]
    f.reorder_below("kangaroo", "platypus")
    assert f.item_order(["kangaroo", "platypus"]) == ["platypus", "kangaroo"]


def delete_item(f):  # R11/R6 - remove one item, the rest survive
    _new_list(f, unique("delitem"))
    f.add_item("keeper")
    f.add_item("goner")
    f.delete_item("goner")
    assert f.has_item("keeper") and not f.has_item("goner")


def hide_show_completed(f):  # R7 (ui view filter)
    _new_list(f, unique("hide"))
    f.add_item("keep")
    f.add_item("done")
    f.cycle_item("done")
    f.cycle_item("done")  # -> complete
    f.toggle_completed()  # hide
    assert f.has_item("keep") and not f.has_item("done")
    f.toggle_completed()  # show
    assert f.has_item("done")


def local_list_is_private_until_shared(f):  # R8, R12
    _new_list(f, unique("private"))
    assert f.sync_status() == "local"
    assert f.is_editable()


def rename_via_title(f):  # rename
    name = unique("title")
    _new_list(f, name)
    renamed = name + "-r"
    f.rename_via_title(renamed)
    assert f.title() == renamed


def rename_via_menu(f):  # rename
    name = unique("menu")
    f.create_list(name)
    renamed = name + "-r"
    f.rename_via_menu(name, renamed)
    assert f.list_present(renamed)


def share_shows_link(f):  # R1
    _new_list(f, unique("share"))
    link = f.share()
    assert link and link.startswith("veilist://"), link


def open_link_rejects_invalid(f):  # R2
    assert f.open_link("not a veilist link") is False


def delete_list(f):  # R6
    name = unique("del")
    f.create_list(name)
    assert f.list_present(name)
    f.delete_list(name)
    assert not f.list_present(name)


def connection_status_visible(f):  # R13
    assert f.connection_status_visible()


# --------------------------------------------------------------- collaboration


def _share_and_join(f, b, name, first_item):
    """f creates+shares a list with one item; b joins and sees it."""
    _new_list(f, name)
    f.add_item(first_item)
    link = f.share()
    assert b.open_link(link)
    b.wait_for_item(first_item)


def edits_converge_both_ways(f):  # R4
    b = f.peer()
    _share_and_join(f, b, unique("collab"), "from A")
    b.add_item("from B")
    f.wait_for_item("from B")


def last_writer_wins(f):  # R4
    b = f.peer()
    _share_and_join(f, b, unique("lww"), "milk")
    f.edit_item("milk", "whole milk")
    b.wait_for_item("whole milk")
    b.edit_item("whole milk", "oat milk")
    f.wait_for_item("oat milk")


def member_reorder_converges(f):  # R11 across devices
    b = f.peer()
    name = unique("mreorder")
    _new_list(f, name)
    f.add_item("kangaroo")
    f.add_item("platypus")
    link = f.share()
    assert b.open_link(link)
    b.wait_for_item("platypus")
    b.reorder_below("kangaroo", "platypus")
    f.wait_for_order(["platypus", "kangaroo"])


def member_can_rename(f):  # rename by a member
    b = f.peer()
    name = unique("mrename")
    _share_and_join(f, b, name, "one")
    renamed = name + "-by-b"
    b.rename_via_title(renamed)
    f.wait_for_title(renamed)


def rename_reaches_listing(f):  # rename reaches a peer's listing via fg sync
    # unlike member_can_rename, b is NOT viewing the list: the new title must
    # reach b's LISTING through foreground sync, not the open-list watch.
    b = f.peer()
    name = unique("rlist")
    _share_and_join(f, b, name, "one")
    b.go_listing()
    renamed = name + "-renamed"
    f.rename_via_title(renamed)
    b.wait_for_list(renamed)


def reorder_while_closed_syncs_on_reopen(f):  # the reopen resync bug
    b = f.peer()
    name = unique("closed")
    _new_list(f, name)
    f.add_item("kangaroo")
    f.add_item("platypus")
    link = f.share()
    assert b.open_link(link)
    b.wait_for_item("platypus")
    f.restart()  # f closes and cold-starts; the reorder happens while it is gone
    b.reorder_below("kangaroo", "platypus")
    f.open_list(name)
    f.wait_for_order(["platypus", "kangaroo"])


SINGLE = [
    ("created_lists_are_tracked", created_lists_are_tracked),
    ("open_list_no_infinite_spinner", open_list_no_infinite_spinner),
    ("add_and_cycle_item_state", add_and_cycle_item_state),
    ("edit_item_text", edit_item_text),
    ("reorder_items", reorder_items),
    ("delete_item", delete_item),
    ("hide_show_completed", hide_show_completed),
    ("local_list_is_private_until_shared", local_list_is_private_until_shared),
    ("rename_via_title", rename_via_title),
    ("rename_via_menu", rename_via_menu),
    ("share_shows_link", share_shows_link),
    ("open_link_rejects_invalid", open_link_rejects_invalid),
    ("delete_list", delete_list),
    ("connection_status_visible", connection_status_visible),
]

COLLAB = [
    ("edits_converge_both_ways", edits_converge_both_ways),
    ("last_writer_wins", last_writer_wins),
    ("member_reorder_converges", member_reorder_converges),
    ("member_can_rename", member_can_rename),
    ("rename_reaches_listing", rename_reaches_listing),
    ("reorder_while_closed_syncs_on_reopen", reorder_while_closed_syncs_on_reopen),
]

ALL = SINGLE + COLLAB
