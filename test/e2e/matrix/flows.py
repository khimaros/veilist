"""the compliance flows, written once against the Frontend interface. the matrix
driver runs each against every frontend. an action a frontend cannot perform
raises SkipFlow (from the interface), so the flow is recorded skip, not fail.

each flow maps to a product requirement (see REQUIREMENTS.md). collaboration
flows take a second frontend via f.peer()."""

import uuid

# a concurrent-edit round must converge well under veilid's 30s fallback change
# inspection: live sync lands in a few seconds, so a coalesced value-less
# notification that the app drops instead of re-reading shows up as a stall past
# this timeout. one round coalesces only about half the time (it turns on the
# storage node's 1s flush-tick boundary), so repeat enough rounds that a dropped
# one is near-certain to be hit.
CONCURRENT_CONVERGE_S = 20
CONCURRENT_ROUNDS = 6

# a local state edit only has to reach this device's own screen, so it needs no
# network round-trip - just enough slack for a slow emulator to repaint.
STATE_S = 20


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


def add_and_toggle_item_state(f):  # R7
    # a plain checkbox tap only moves between open and complete, both ways.
    _new_list(f, unique("toggle"))
    f.add_item("wash dishes")
    assert f.has_item("wash dishes")
    f.toggle_item("wash dishes")
    f.wait_for_state("wash dishes", "complete", timeout_s=STATE_S)
    f.toggle_item("wash dishes")
    f.wait_for_state("wash dishes", "new", timeout_s=STATE_S)
    assert f.has_item("wash dishes")


def pick_item_state(f):  # R7
    # press and hold the checkbox to set a state a tap cannot reach.
    _new_list(f, unique("pick"))
    f.add_item("call plumber")
    f.set_item_state("call plumber", "blocked")
    f.wait_for_state("call plumber", "blocked", timeout_s=STATE_S)
    f.set_item_state("call plumber", "active")
    f.wait_for_state("call plumber", "active", timeout_s=STATE_S)
    # a tap still completes an item the picker put in another state.
    f.toggle_item("call plumber")
    f.wait_for_state("call plumber", "complete", timeout_s=STATE_S)


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
    f.toggle_item("done")  # -> complete
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


def scan_link_opens_camera(f):  # R1, R2
    # the other half of the share dialog's qr code: a device with a camera can
    # read one instead of pasting a link.
    assert f.scanner_opens()


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


def member_state_change_converges(f):  # R7 across devices
    # one party changes an item's state; another party viewing the same list must
    # see it live, both ways - the mirror of member_reorder_converges for the
    # state field. reported: marking an item active did not propagate to peers,
    # though a reorder did. covers both edit paths: a checkbox tap and the
    # press-and-hold picker.
    b = f.peer()
    name = unique("mstate")
    _share_and_join(f, b, name, "task")
    f.toggle_item("task")  # new -> complete
    b.wait_for_state("task", "complete")
    b.set_item_state("task", "blocked")  # from the picker
    f.wait_for_state("task", "blocked")


def member_item_rename_converges(f):  # R11 across devices
    # renaming a task (item text) must reach a peer viewing the list, the same
    # way a reorder does. reported as a suspected sibling of the state bug.
    b = f.peer()
    name = unique("mtaskname")
    _share_and_join(f, b, name, "byy milk")
    f.edit_item("byy milk", "buy milk")
    b.wait_for_item("buy milk")


def concurrent_member_edits_converge(f):  # R4/R7 - coalesced value-less notify
    # when two members write their own subkeys within the same storage-node
    # flush window (~1s), veilid coalesces the two changes into a single
    # ValueChanged that carries NO inline value - the app must re-read the
    # changed range. dropping it (the bug) leaves each party blind to the other's
    # edit until veilid's ~30s fallback inspection. this is the live-collaboration
    # case behind "marking an item active did not reach the other party while a
    # reorder (done while only one side was writing) did".
    b = f.peer()
    name = unique("concur")
    _new_list(f, name)
    f.add_item("alpha")
    f.add_item("bravo")
    link = f.share()
    assert b.open_link(link)
    b.wait_for_item("alpha")
    b.wait_for_item("bravo")
    # A toggles alpha and B toggles bravo at the same instant, round after round.
    # each round asserts the cross-device state lands fast; a coalesced round the
    # app dropped stalls past the timeout. states alternate complete -> new as
    # each item is toggled once per round.
    after_toggle = ["complete", "new"]
    for r in range(CONCURRENT_ROUNDS):
        f.toggle_with_peer(b, "alpha", "bravo")  # A -> subkey 0, B -> subkey 2
        want = after_toggle[r % 2]
        b.wait_for_state("alpha", want, timeout_s=CONCURRENT_CONVERGE_S)
        f.wait_for_state("bravo", want, timeout_s=CONCURRENT_CONVERGE_S)


def offline_edit_reaches_peer_after_reconnect(f):  # R12 - deterministic receive
    # f edits while genuinely offline (confirmed via the sync chip), reconnects,
    # and confirms its OWN write flushed to the dht (chip reads 'synced'). the
    # value is now provably on the network, so a peer viewing the list must show
    # it. isolates the receive side: if the peer never sees it, it missed the live
    # watch update and never reconciled (OpenList stops re-reading after its first
    # live sync). one edit, proper sequencing -> no timing flake.
    b = f.peer()
    name = unique("offlrx")
    _share_and_join(f, b, name, "seed")
    f.go_offline()
    f.wait_for_sync_status("offline", timeout_s=30)
    f.toggle_item("seed")  # new -> complete, guaranteed offline
    f.go_online()
    f.wait_for_sync_status("synced", timeout_s=120)  # f flushed to the dht
    b.wait_for_state("seed", "complete", timeout_s=45)  # peer must receive it


def live_view_reconciles_missed_edits(f):  # R12/R13 - consistently-failing repro
    # b is viewing a shared list (already live-synced). round after round, b goes
    # offline, f toggles the item, and b reconnects and must show f's new state.
    # each round b's watch cannot see f's edit (b was offline), so b must catch up
    # on reconnect; the unfixed OpenList only re-reads before its FIRST live sync,
    # so an already-synced view never resyncs and strands. one flaky round is
    # ~1/3; looping makes a strand near-certain. no items are added, so the single
    # tracked item stays on-screen for the driver.
    b = f.peer()
    name = unique("strand")
    _share_and_join(f, b, name, "seed")
    for _ in range(8):
        b.go_offline()
        b.wait_for_sync_status("offline", timeout_s=30)
        f.toggle_item("seed")  # f edits while b is offline
        want = f.item_state("seed")  # f's own view is the ground truth
        b.go_online()
        b.wait_for_sync_status("synced", timeout_s=90)  # b's node reconnected
        b.wait_for_state("seed", want, timeout_s=20)  # b must catch up, or strand


def peer_offline_misses_edit_then_reconnects(f):  # R12/R13 - deterministic
    # b is viewing a shared list (already live-synced), then goes offline. f edits
    # while b is offline, so b's watch cannot see it. when b reconnects it must
    # catch up. reproduces the strand deterministically: OpenList only re-reads on
    # reconnect while it has NOT yet live-synced, so an already-synced view that
    # went offline never resyncs and stays one edit behind forever.
    b = f.peer()
    name = unique("boffl")
    _share_and_join(f, b, name, "seed")
    b.go_offline()
    b.wait_for_sync_status("offline", timeout_s=30)
    f.toggle_item("seed")  # new -> complete while b is offline
    f.wait_for_sync_status("synced", timeout_s=30)  # edit is on the dht
    b.go_online()
    b.wait_for_sync_status("synced", timeout_s=90)  # b's node is back online
    b.wait_for_state("seed", "complete", timeout_s=30)  # b must catch up


def offline_multi_edits_reach_peer_after_reconnect(f):  # R12 - deterministic
    # like the single-edit version but several rapid offline edits, then f
    # confirms 'synced' (every edit flushed to the dht). the peer must show the
    # full final state. reproduces the multi-edit flake: on reconnect f flushes a
    # burst of successive seqs to its subkey; the peer's watch lands an
    # intermediate seq but not the last, and never reconciles after its first live
    # sync -> stuck one edit behind.
    b = f.peer()
    name = unique("offlmx")
    _share_and_join(f, b, name, "seed")
    f.go_offline()
    f.wait_for_sync_status("offline", timeout_s=30)
    f.add_item("off-1")
    f.add_item("off-2")
    f.add_item("off-3")
    f.toggle_item("seed")  # last edit: new -> complete
    f.go_online()
    f.wait_for_sync_status("synced", timeout_s=120)  # all edits now on the dht
    b.wait_for_item("off-1", timeout_s=45)
    b.wait_for_item("off-2", timeout_s=45)
    b.wait_for_item("off-3", timeout_s=45)
    b.wait_for_state("seed", "complete", timeout_s=45)  # the final edit must land


def offline_edits_flush_on_reconnect(f):  # R12
    # a device makes several edits while offline, then sits on the listing with
    # the list closed. once it reconnects it must flush every queued edit to a
    # peer without the user reopening the list - "keep trying until synced" from
    # the main screen.
    b = f.peer()
    name = unique("offl")
    _share_and_join(f, b, name, "seed")
    f.go_offline()
    f.add_item("off-1")
    f.add_item("off-2")
    f.toggle_item("seed")  # new -> complete, also queued offline
    f.go_listing()  # main screen; the widget frontends close the record here
    f.go_online()
    b.wait_for_item("off-1")
    b.wait_for_item("off-2")
    b.wait_for_state("seed", "complete")


def offline_edits_flush_while_backgrounded(f):  # R12
    # the same, but the device is backgrounded (foreground sync stopped) when it
    # reconnects, so the flush cannot rely on foreground sync being active.
    b = f.peer()
    name = unique("offlbg")
    _share_and_join(f, b, name, "seed")
    f.go_offline()
    f.add_item("bg-1")
    f.toggle_item("seed")  # new -> complete
    f.go_listing()
    f.set_foreground(False)  # background: stop foreground sync
    f.go_online()  # reconnect while backgrounded
    b.wait_for_item("bg-1")
    b.wait_for_state("seed", "complete")
    f.set_foreground(True)  # restore for a clean teardown


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
    ("add_and_toggle_item_state", add_and_toggle_item_state),
    ("pick_item_state", pick_item_state),
    ("edit_item_text", edit_item_text),
    ("reorder_items", reorder_items),
    ("delete_item", delete_item),
    ("hide_show_completed", hide_show_completed),
    ("local_list_is_private_until_shared", local_list_is_private_until_shared),
    ("rename_via_title", rename_via_title),
    ("rename_via_menu", rename_via_menu),
    ("share_shows_link", share_shows_link),
    ("open_link_rejects_invalid", open_link_rejects_invalid),
    ("scan_link_opens_camera", scan_link_opens_camera),
    ("delete_list", delete_list),
    ("connection_status_visible", connection_status_visible),
]

COLLAB = [
    ("edits_converge_both_ways", edits_converge_both_ways),
    ("last_writer_wins", last_writer_wins),
    ("member_reorder_converges", member_reorder_converges),
    ("member_state_change_converges", member_state_change_converges),
    ("member_item_rename_converges", member_item_rename_converges),
    ("concurrent_member_edits_converge", concurrent_member_edits_converge),
    ("offline_edit_reaches_peer_after_reconnect", offline_edit_reaches_peer_after_reconnect),
    ("live_view_reconciles_missed_edits", live_view_reconciles_missed_edits),
    ("peer_offline_misses_edit_then_reconnects", peer_offline_misses_edit_then_reconnects),
    ("offline_multi_edits_reach_peer_after_reconnect", offline_multi_edits_reach_peer_after_reconnect),
    ("offline_edits_flush_on_reconnect", offline_edits_flush_on_reconnect),
    ("offline_edits_flush_while_backgrounded", offline_edits_flush_while_backgrounded),
    ("member_can_rename", member_can_rename),
    ("rename_reaches_listing", rename_reaches_listing),
    ("reorder_while_closed_syncs_on_reopen", reorder_while_closed_syncs_on_reopen),
]

ALL = SINGLE + COLLAB
