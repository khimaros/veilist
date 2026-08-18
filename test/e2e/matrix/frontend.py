"""the abstraction every frontend implements: user *actions* and *status
queries*, independent of how a platform is driven (the flutter widget driver on
linux/android, the window.veilistTest hook on web).

flows (flows.py) are written once against this interface, and the matrix driver
(matrix.py) runs every flow against every frontend, so the frontends can never
drift: they run the same flow code. an action a frontend genuinely cannot
perform (a ui-only gesture on the hook-driven web frontend) raises SkipFlow, and
the matrix records "skip" for that cell rather than a failure.

the interface is stateful in a uniform way: open_list()/create_list() select the
"current list", and later actions/queries act on it. each implementation tracks
that selection however suits its transport (a route on the widget frontends, a
record key on the web frontend).
"""


import os


class SkipFlow(Exception):
    """raised by an action/query a frontend cannot perform, so the matrix records
    skip (not fail) for that flow on that frontend."""


class Frontend:
    # human-readable id used in the result matrix.
    name = "abstract"

    # whether this frontend can run a second, independent instance in the same
    # environment (for the collaboration flows). widget frontends need a second
    # process/emulator; web uses a second browser context.
    supports_peers = False

    # ---- lifecycle ----
    def start(self):
        """launch/attach and leave the app on the listing page."""
        raise NotImplementedError

    def reset(self):
        """return to a clean listing between flows (fresh state if possible)."""
        raise NotImplementedError

    def stop(self):
        """tear down."""

    def peer(self):
        """a second, independent frontend instance sharing the same dht, for the
        collaboration flows. raise SkipFlow if unsupported."""
        raise SkipFlow(f"{self.name} cannot spawn a peer")

    # ---- actions ----
    def create_list(self, name):
        raise SkipFlow("create_list unsupported")

    def open_list(self, name):
        raise SkipFlow("open_list unsupported")

    def add_item(self, text):
        raise SkipFlow("add_item unsupported")

    def toggle_item(self, text):
        """tap one item's checkbox: complete it, or re-open a completed one."""
        raise SkipFlow("toggle_item unsupported")

    def set_item_state(self, text, state):
        """set one item's state outright (the press-and-hold picker), given as a
        wire code: new | active | complete | blocked."""
        raise SkipFlow("set_item_state unsupported")

    def toggle_item_nowait(self, text):
        """toggle an item's state without waiting for the network write to flush,
        so a second member's write can overlap in the same storage-node flush
        window (~1s). defaults to the blocking toggle_item, which already returns
        before the write completes on the widget frontends (a driver tap does not
        await the async flush); the web hook awaits it, so web overrides this."""
        self.toggle_item(text)

    def toggle_with_peer(self, peer, my_text, peer_text):
        """this frontend toggles my_text and `peer` toggles peer_text as close to
        simultaneously as possible, so both members' subkey writes land in one
        storage-node flush window and coalesce into a single value-less watch
        notification. default fires them back-to-back; frontends whose write call
        blocks the caller (widget taps) override to run the two in parallel."""
        self.toggle_item_nowait(my_text)
        peer.toggle_item_nowait(peer_text)

    def edit_item(self, old, new):
        raise SkipFlow("edit_item unsupported")

    def reorder_below(self, item, other):
        """move `item` so it sits after `other`."""
        raise SkipFlow("reorder unsupported")

    def delete_item(self, text):
        raise SkipFlow("delete_item unsupported")

    def toggle_completed(self):
        """flip the hide/show-completed view filter (ui-only)."""
        raise SkipFlow("hide-completed is a ui-only toggle")

    def rename_via_title(self, new):
        raise SkipFlow("rename_via_title unsupported")

    def rename_via_menu(self, name, new):
        raise SkipFlow("rename_via_menu unsupported")

    def share(self):
        """share the current list; returns the app share link."""
        raise SkipFlow("share unsupported")

    def open_link(self, link):
        """open/join a share link; returns True if it opened a list."""
        raise SkipFlow("open_link unsupported")

    def scanner_opens(self):
        """open the qr scanner from the listing, then return to the listing.
        True if the scanner page appeared. driving the camera itself needs a
        real code in front of a real lens, so this covers the affordance only;
        the decode path is covered by the dart tests."""
        raise SkipFlow("scanner_opens unsupported")

    def delete_list(self, name):
        raise SkipFlow("delete_list unsupported")

    def go_listing(self):
        """return to the listing page. widget frontends navigate there; the web
        frontend queries the roster regardless of page, so it is a no-op."""

    def go_offline(self):
        """detach this frontend's veilid node from the network."""
        raise SkipFlow("go_offline unsupported")

    def go_online(self):
        """re-attach this frontend's veilid node to the network."""
        raise SkipFlow("go_online unsupported")

    def set_foreground(self, foreground):
        """toggle foreground sync: True mimics sitting on the listing (sync
        running), False mimics the app being backgrounded (sync stopped)."""
        raise SkipFlow("set_foreground unsupported")

    # ---- queries ----
    # widget frontends cannot enumerate items (profile builds strip the
    # diagnostics tree, and both adapters only *order given* texts), so the
    # portable queries are has_item / item_order / is_empty.
    def lists(self):
        """titles shown on the listing page."""
        raise SkipFlow("lists query unsupported")

    def list_present(self, name):
        return name in self.lists()

    def list_updated(self, name):
        """whether the listing marks this list as changed since this device
        last had it on screen (R17)."""
        raise SkipFlow("list_updated query unsupported")

    def has_item(self, text):
        """whether the current list shows an item with this text."""
        raise SkipFlow("has_item query unsupported")

    def item_state(self, text):
        """the state of the item with this text, as its wire code: one of
        new | active | complete | blocked (the shipped set; the model carries
        more). web reads the folded state via the hook; widget frontends read
        the checkbox glyph via the driver."""
        raise SkipFlow("item_state query unsupported")

    def item_order(self, texts):
        """the given item texts in the order they appear (absent ones dropped)."""
        raise SkipFlow("item_order query unsupported")

    def is_empty(self):
        """whether the current list shows no items."""
        raise SkipFlow("is_empty query unsupported")

    def title(self):
        raise SkipFlow("title query unsupported")

    def sync_status(self):
        """one of: synced | syncing | offline | local."""
        raise SkipFlow("sync_status query unsupported")

    def connection_status_visible(self):
        raise SkipFlow("connection_status query unsupported")

    def is_editable(self):
        raise SkipFlow("is_editable query unsupported")

    # ---- convergence waits (dht is eventually consistent) ----
    # default implementations poll; widget frontends may override with a native
    # driver waitFor. CONVERGE_S is generous because two live nodes must meet.
    # VEILIST_CONVERGE_S raises it for diagnosis: a flow that passes only with a
    # longer budget is slow to propagate, not losing edits - a distinction worth
    # measuring rather than guessing at.
    CONVERGE_S = int(os.environ.get("VEILIST_CONVERGE_S", 120))
    POLL_S = 2

    def wait_for_item(self, text, timeout_s=None):
        self._poll(lambda: self.has_item(text), timeout_s, f"item '{text}'")

    def wait_for_order(self, order, timeout_s=None):
        self._poll(
            lambda: self.item_order(order) == order, timeout_s, f"order {order}"
        )

    def wait_for_state(self, text, state, timeout_s=None):
        self._poll(
            lambda: self.item_state(text) == state,
            timeout_s,
            f"state '{state}' for '{text}'",
        )

    def wait_for_sync_status(self, status, timeout_s=None):
        self._poll(
            lambda: self.sync_status() == status, timeout_s, f"sync status '{status}'"
        )

    def wait_for_title(self, title, timeout_s=None):
        self._poll(lambda: self.title() == title, timeout_s, f"title '{title}'")

    def wait_for_list(self, name, timeout_s=None):
        """wait for a list title to appear on the listing (foreground sync)."""
        self._poll(lambda: self.list_present(name), timeout_s, f"list '{name}'")

    def wait_for_list_updated(self, name, timeout_s=None):
        self._poll(
            lambda: self.list_updated(name), timeout_s, f"list '{name}' marked updated"
        )

    def _poll(self, cond, timeout_s, what):
        import time as _t

        deadline = _t.time() + (self.CONVERGE_S if timeout_s is None else timeout_s)
        while _t.time() < deadline:
            try:
                if cond():
                    return
            except SkipFlow:
                raise
            except Exception:
                pass
            _t.sleep(self.POLL_S)
        raise AssertionError(f"timed out waiting for {what}")

    def restart(self):
        """stop and relaunch this instance with the same identity/roster, back on
        the listing (for the reopen-after-close flow)."""
        raise SkipFlow("restart unsupported")
