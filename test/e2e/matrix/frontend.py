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

    def cycle_item(self, text):
        """advance one item's state one step (new -> active -> complete -> new)."""
        raise SkipFlow("cycle_item unsupported")

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

    def delete_list(self, name):
        raise SkipFlow("delete_list unsupported")

    def go_listing(self):
        """return to the listing page. widget frontends navigate there; the web
        frontend queries the roster regardless of page, so it is a no-op."""

    # ---- queries ----
    # widget frontends cannot enumerate items (profile builds strip the
    # diagnostics tree, and both adapters only *order given* texts), so the
    # portable queries are has_item / item_order / is_empty.
    def lists(self):
        """titles shown on the listing page."""
        raise SkipFlow("lists query unsupported")

    def list_present(self, name):
        return name in self.lists()

    def has_item(self, text):
        """whether the current list shows an item with this text."""
        raise SkipFlow("has_item query unsupported")

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
    CONVERGE_S = 120
    POLL_S = 2

    def wait_for_item(self, text, timeout_s=None):
        self._poll(lambda: self.has_item(text), timeout_s, f"item '{text}'")

    def wait_for_order(self, order, timeout_s=None):
        self._poll(
            lambda: self.item_order(order) == order, timeout_s, f"order {order}"
        )

    def wait_for_title(self, title, timeout_s=None):
        self._poll(lambda: self.title() == title, timeout_s, f"title '{title}'")

    def wait_for_list(self, name, timeout_s=None):
        """wait for a list title to appear on the listing (foreground sync)."""
        self._poll(lambda: self.list_present(name), timeout_s, f"list '{name}'")

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
