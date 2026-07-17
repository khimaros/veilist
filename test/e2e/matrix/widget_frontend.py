"""Frontend implemented over the flutter widget driver. linux (flutter_vm) and
android (flutter_ui) share it verbatim because their driver adapters expose the
same surface (key/text/tap/wait_for/...). subclasses provide only the lifecycle
(start/stop/reset/peer/restart) and set self.ui (the adapter module) and self.d
(the driver/session)."""

from frontend import Frontend, SkipFlow

SHORT_MS = 4000  # presence checks for queries
OPEN_MS = 30000  # opening a list resolves to content
# the first share publishes to the dht (a network round-trip); generous because
# a slow emulator's veilid node re-attaches per flow and can take a while.
PUBLISH_MS = 120000


class WidgetFrontend(Frontend):
    def __init__(self):
        self.ui = None
        self.d = None

    # ---- helpers ----
    def _present(self, finder, timeout=SHORT_MS):
        return self.ui.present(self.d, finder, timeout)

    # ---- actions ----
    def create_list(self, name):
        u, d = self.ui, self.d
        u.tap(d, u.key("fab_new_list"))
        u.enter_text(d, u.key("prompt_field"), name)
        u.tap(d, u.key("prompt_action"))
        u.wait_for(d, u.text(name))

    def open_list(self, name):
        u, d = self.ui, self.d
        u.tap(d, u.text(name))
        u.wait_for(d, u.key("add_field"), OPEN_MS)

    def add_item(self, text):
        u, d = self.ui, self.d
        u.enter_text(d, u.key("add_field"), text)
        u.tap(d, u.key("add_button"))
        u.wait_for(d, u.text(text))

    def cycle_item(self, text):
        u, d = self.ui, self.d
        u.tap(d, u.in_tile(text, "StateGlyphButton"))
        u.settle(d, 0.5)

    def cycle_item_nowait(self, text):
        # tap the checkbox but skip the settle, so a second member's tap follows
        # immediately and both writes land in one storage-node flush window.
        self.ui.tap(self.d, self.ui.in_tile(text, "StateGlyphButton"))

    def cycle_with_peer(self, peer, my_text, peer_text):
        # a driver tap blocks the caller for its round-trip, so back-to-back taps
        # are tens of ms apart - enough to sometimes straddle the 1s flush window.
        # each frontend has its own driver connection, so tap both in parallel
        # threads to fire them together and coalesce reliably.
        import threading

        workers = [
            threading.Thread(target=lambda: self.cycle_item_nowait(my_text)),
            threading.Thread(target=lambda: peer.cycle_item_nowait(peer_text)),
        ]
        for w in workers:
            w.start()
        for w in workers:
            w.join()

    def edit_item(self, old, new):
        u, d = self.ui, self.d
        u.tap(d, u.text(old))
        u.enter_text(d, u.key("edit_field"), new)
        u.tap(d, u.text("save"))
        # wait for the dialog to close first: its text field is an EditableText
        # holding `new`, which text(new) would otherwise match before the edit
        # has applied to the item.
        u.wait_absent(d, u.key("edit_field"))
        u.wait_for(d, u.text(new))

    def reorder_below(self, item, other):
        u, d = self.ui, self.d
        handle = u.in_tile(item, "Icon")
        target = [other, item]
        # the drag can need several tries to grab and commit on a slow emulator.
        for _ in range(12):
            u.scroll(d, handle, dx=0, dy=220, duration_ms=1200)
            u.settle(d, 1.5)
            if u.item_order(d, [item, other]) == target:
                return
        assert u.item_order(d, [item, other]) == target, u.item_order(d, [item, other])

    def delete_item(self, text):
        u, d = self.ui, self.d
        # swipe the row left to dismiss it (the tile is a Dismissible,
        # endToStart). the gesture can need a couple tries to grab and commit.
        for _ in range(4):
            u.scroll(d, u.text(text), dx=-600, dy=0, duration_ms=600)
            u.settle(d, 0.5)
            if not u.present(d, u.text(text), 1500):
                return
        u.wait_absent(d, u.text(text))

    def toggle_completed(self):
        u, d = self.ui, self.d
        u.tap(d, u.key("toggle_completed"))
        u.settle(d, 0.5)

    def rename_via_title(self, new):
        u, d = self.ui, self.d
        u.tap(d, u.key("list_title"))
        u.enter_text(d, u.key("rename_field"), new)
        u.tap(d, u.text("save"))
        # close the dialog before checking: its text field holds `new` too.
        u.wait_absent(d, u.key("rename_field"))
        u.wait_for(d, u.text(new))

    def rename_via_menu(self, name, new):
        u, d = self.ui, self.d
        menu = u.descendant(
            u.ancestor(u.text(name), u.type_("ListTile")),
            u.type_("PopupMenuButton<String>"),
        )
        u.tap(d, menu)
        u.tap(d, u.text("rename"))
        u.enter_text(d, u.key("prompt_field"), new)
        u.tap(d, u.key("prompt_action"))
        u.wait_for(d, u.text(new))

    def share(self):
        u, d = self.ui, self.d
        u.tap(d, u.tooltip("share"))
        u.wait_for(d, u.type_("QrImageView"), PUBLISH_MS)
        link = u.get_text(d, u.key("app_link_value"))
        u.tap(d, u.text("done"))
        return link

    def open_link(self, link):
        u, d = self.ui, self.d
        u.tap(d, u.key("open_link_button"))
        u.enter_text(d, u.key("prompt_field"), link)
        u.tap(d, u.key("prompt_action"))
        if self._present(u.text("not a veilist link"), 3000):
            return False
        u.wait_for(d, u.key("add_field"), OPEN_MS)
        return True

    def delete_list(self, name):
        u, d = self.ui, self.d
        menu = u.descendant(
            u.ancestor(u.text(name), u.type_("ListTile")),
            u.type_("PopupMenuButton<String>"),
        )
        u.tap(d, menu)
        u.tap(d, u.text("delete"))
        u.tap(d, u.text("delete"))
        u.wait_absent(d, u.text(name))

    def go_listing(self):
        self.ui.home(self.d)

    # e2e control channel (driver requestData -> test/driver/app.dart handler).
    def go_offline(self):
        self.ui.request_data(self.d, "offline")

    def go_online(self):
        self.ui.request_data(self.d, "online")

    def set_foreground(self, foreground):
        self.ui.request_data(self.d, "foreground" if foreground else "background")

    # ---- queries ----
    def list_present(self, name):
        return self._present(self.ui.text(name))

    def has_item(self, text):
        return self._present(self.ui.text(text))

    # glyph rendered by StateGlyphButton -> wire code (see ItemState). "new"
    # renders an empty glyph, so an empty string maps back to it.
    _GLYPH_STATE = {"": "new", " ": "new", "@": "active", "x": "complete"}

    def item_state(self, text):
        u, d = self.ui, self.d
        glyph = u.get_text(
            d, u.descendant(u.in_tile(text, "StateGlyphButton"), u.type_("Text")), SHORT_MS
        )
        return self._GLYPH_STATE.get(glyph, glyph)

    def item_order(self, texts):
        return self.ui.item_order(self.d, texts)

    def is_empty(self):
        return self._present(self.ui.text("no items yet - add one below"))

    def title(self):
        return self.ui.get_text(self.d, self.ui.key("list_title"))

    def sync_status(self):
        labels = {
            "saved on this device": "local",
            "synced": "synced",
            "syncing": "syncing",
            "offline": "offline",
        }
        for phrase, status in labels.items():
            if self._present(self.ui.tooltip(f"changes are {phrase}"), 1500):
                return status
        return "unknown"

    def connection_status_visible(self):
        return self._present(self.ui.key("connection_status"))

    def is_editable(self):
        # the add field's hint is "add an item" when editable, "syncing..." when
        # a joined list is still read-only.
        return self._present(self.ui.text("add an item"))
