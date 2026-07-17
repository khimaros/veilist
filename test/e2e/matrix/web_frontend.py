"""web frontend: drives the served web build in the system chrome via playwright,
using the window.veilistTest hook (NOT the flutter driver - flutter web renders
to a canvas). needs the e2e web build (VEILIST_E2E=true) under build/web-e2e,
which test/scripts/matrix_run.sh produces. a second browser context runs a
second veilid node for the collaboration flows."""

import functools
import http.server
import json
import os
import socket
import socketserver
import threading

from frontend import Frontend

_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
# the e2e web build lands in build/web-e2e (separate from the production
# build/web) so the test artifact - which carries the window.veilistTest backdoor
# and a "/" base-href - never overwrites a deployable build. see matrix_run.sh.
WEB_DIR = os.path.join(_ROOT, "build", "web-e2e")


class _IsolatedHandler(http.server.SimpleHTTPRequestHandler):
    """COOP/COEP so the page is cross-origin isolated (veilid wasm)."""

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        super().end_headers()

    def log_message(self, *args):
        pass


def _serve(directory):
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    handler = functools.partial(_IsolatedHandler, directory=directory)
    httpd = socketserver.ThreadingTCPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, f"http://127.0.0.1:{port}/"


def _boot(page, base):
    page.goto(base, wait_until="load")
    # a cold second browser context (the collab peer) can take a while to
    # download + compile the flutter web app and install the hook; give it the
    # same budget as the veilid-attach wait below rather than a tighter 60s.
    page.wait_for_function(
        "() => typeof window.veilistTest !== 'undefined'", timeout=120_000
    )
    page.wait_for_function(
        "() => ['attaching','ready'].includes(window.veilistPhase)",
        timeout=120_000,
    )
    return page


class WebFrontend(Frontend):
    name = "web"
    supports_peers = True

    def __init__(self):
        self._pw = None
        self._browser = None
        self._httpd = None
        self._base = None
        self._ctx = None
        self._page = None
        self._is_peer = False
        self._current = None
        self._name = None
        self._name_to_key = {}

    # ---- lifecycle ----
    def start(self):
        if not os.path.exists(os.path.join(WEB_DIR, "index.html")):
            raise RuntimeError(f"{WEB_DIR} not built (e2e build); run run.sh web")
        from playwright.sync_api import sync_playwright

        self._httpd, self._base = _serve(WEB_DIR)
        self._pw = sync_playwright().start()
        self._browser = self._pw.chromium.launch(
            channel="chrome",
            headless=True,
            args=["--no-sandbox", "--disable-dev-shm-usage"],
        )
        self._ctx = self._browser.new_context()
        self._page = _boot(self._ctx.new_page(), self._base)

    def reset(self):
        pass  # flows are independent by record key; nothing to navigate

    def restart(self):
        _boot(self._page, self._base)  # roster persists in indexeddb

    def peer(self):
        p = WebFrontend()
        p._is_peer = True
        p._base = self._base
        p._browser = self._browser
        p._ctx = self._browser.new_context()
        p._page = _boot(p._ctx.new_page(), self._base)
        return p

    def stop(self):
        try:
            if self._ctx:
                self._ctx.close()
        except Exception:
            pass
        if self._is_peer:
            return
        for closer in (
            lambda: self._browser and self._browser.close(),
            lambda: self._pw and self._pw.stop(),
            lambda: self._httpd and self._httpd.shutdown(),
        ):
            try:
                closer()
            except Exception:
                pass

    # ---- hook plumbing ----
    def _call(self, method, *args):
        arglist = ", ".join(json.dumps(a) for a in args)
        return self._page.evaluate(
            f"async () => await window.veilistTest.{method}({arglist})"
        )

    def _sync_call(self, method):
        return self._page.evaluate(f"() => window.veilistTest.{method}()")

    def _items(self):
        return json.loads(self._call("items", self._current))

    def _texts(self):
        return [it["text"] for it in self._items()]

    def _id_of(self, text):
        for it in self._items():
            if it["text"] == text:
                return it["id"]
        raise AssertionError(f"item '{text}' not found")

    def _key_by_title(self, title):
        for r in json.loads(self._sync_call("lists")):
            if r["title"] == title:
                return r["recordKey"]
        raise AssertionError(f"list '{title}' not found")

    def _key_for(self, name):
        return self._name_to_key.get(name) or self._key_by_title(name)

    # ---- actions ----
    def create_list(self, name):
        self._current = self._call("create", name)
        self._name_to_key[name] = self._current
        self._name = name

    def open_list(self, name):
        self._current = self._key_for(name)
        self._name = name

    def add_item(self, text):
        self._call("add", self._current, text)

    def cycle_item(self, text):
        self._call("cycle", self._current, self._id_of(text))

    def cycle_item_nowait(self, text):
        # kick off the cycle write but do not await its network fanout, so a
        # second member's concurrent write lands in the same storage-node flush
        # window (the hook's cycle() otherwise blocks on setDHTValue).
        self._fire_cycle(self._id_of(text))

    def _fire_cycle(self, iid):
        self._page.evaluate(
            "(a) => { window.veilistTest.cycle(a[0], a[1]); return 0; }",
            [self._current, iid],
        )

    def cycle_with_peer(self, peer, my_text, peer_text):
        # playwright's sync api is not thread-safe, so resolve both item ids
        # first, then fire the two non-awaited writes back-to-back (one evaluate
        # round-trip apart) so they still coalesce in one flush window.
        my_id, their_id = self._id_of(my_text), peer._id_of(peer_text)
        self._fire_cycle(my_id)
        peer._fire_cycle(their_id)

    def go_offline(self):
        self._call("setOnline", False)

    def go_online(self):
        self._call("setOnline", True)

    def set_foreground(self, foreground):
        self._call("setForeground", foreground)

    def edit_item(self, old, new):
        self._call("setText", self._current, self._id_of(old), new)

    def reorder_below(self, item, other):
        texts = self._texts()
        oi, oj = texts.index(item), texts.index(other)
        self._call("reorder", self._current, oi, oj if oi < oj else oj + 1)

    def delete_item(self, text):
        self._call("removeItem", self._current, self._id_of(text))

    def rename_via_title(self, new):
        self._call("setTitle", self._current, new)
        self._name = new

    def rename_via_menu(self, name, new):
        self._call("setTitle", self._key_for(name), new)

    def share(self):
        link = self._call("share", self._current)
        # publishing re-keys the list; refresh the current key by its title.
        self._current = self._key_by_title(self._name)
        self._name_to_key[self._name] = self._current
        return link

    def open_link(self, link):
        try:
            self._current = self._call("join", link)
        except Exception:
            return False
        self._name = self._call("title", self._current)
        return True

    def delete_list(self, name):
        self._call("deleteList", self._key_for(name))
        self._name_to_key.pop(name, None)

    # ---- queries ----
    def lists(self):
        return [r["title"] for r in json.loads(self._sync_call("lists"))]

    def has_item(self, text):
        return text in self._texts()

    def item_state(self, text):
        for it in self._items():
            if it["text"] == text:
                return it["state"]
        raise AssertionError(f"item '{text}' not found")

    def item_order(self, texts):
        return [t for t in self._texts() if t in texts]

    def is_empty(self):
        return self._texts() == []

    def title(self):
        return self._call("title", self._current)

    def sync_status(self):
        return self._call("syncStatus", self._current)

    def connection_status_visible(self):
        return self._page.evaluate(
            "() => ['attaching','ready'].includes(window.veilistPhase)"
        )

    def is_editable(self):
        return self._call("editable", self._current) == "true"
