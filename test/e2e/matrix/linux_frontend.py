"""linux frontend: launches the profile desktop app on a private headless
display and drives it over the dart vm service (flutter_vm)."""

import os
import re
import shutil
import signal
import subprocess
import tempfile
import time

import flutter_vm
from widget_frontend import WidgetFrontend

_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
LINUX_BINARY = os.path.join(_ROOT, "build/linux/x64/profile/bundle/veilist")


def _vm_url_from(proc, timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                raise RuntimeError("app exited before printing its vm service url")
            continue
        m = re.search(r"Dart VM service is listening on (http://\S+)", line)
        if m:
            return m.group(1).rstrip("/").replace("http://", "ws://") + "/ws"
    raise RuntimeError("timed out waiting for the vm service url")


def _launch(state):
    if not os.path.exists(LINUX_BINARY):
        raise RuntimeError(
            f"missing {LINUX_BINARY}; build with "
            "flutter build linux --profile -t test/driver/app.dart"
        )
    if shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a", LINUX_BINARY]
        env = dict(os.environ, GDK_BACKEND="x11")
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
    else:
        cmd = [LINUX_BINARY]
        env = dict(os.environ, DISPLAY=os.environ.get("DISPLAY", ":0"))
    for var in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
        sub = os.path.join(state, var.split("_")[1].lower())
        os.makedirs(sub, exist_ok=True)
        env[var] = sub
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    return flutter_vm.VMDriver(_vm_url_from(proc)), proc


class LinuxFrontend(WidgetFrontend):
    name = "linux"
    supports_peers = True

    def __init__(self, state=None):
        super().__init__()
        self.ui = flutter_vm
        self._state = state or tempfile.mkdtemp(prefix="veilist-matrix-")
        self._own_state = state is None
        self._proc = None
        self._peers = []

    def start(self):
        self.reset()

    def reset(self):
        # a fresh app per flow: veilid background work from one flow otherwise
        # hangs the next (the compliance suite relaunches for the same reason).
        for p in self._peers:
            p.stop()
        self._peers = []
        self._kill()
        shutil.rmtree(self._state, ignore_errors=True)
        self._state = tempfile.mkdtemp(prefix="veilist-matrix-")
        self.d, self._proc = _launch(self._state)
        flutter_vm.wait_for(self.d, flutter_vm.key("fab_new_list"), 45000)

    def _kill(self):
        try:
            self.d.close()
        except Exception:
            pass
        if self._proc:
            try:
                os.killpg(os.getpgid(self._proc.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            self._proc = None

    def stop(self):
        for p in self._peers:
            p.stop()
        self._peers = []
        self._kill()
        if self._own_state:
            shutil.rmtree(self._state, ignore_errors=True)

    def restart(self):
        # keep the state dir so the reopened app has the same roster/identity.
        self._kill()
        self.d, self._proc = _launch(self._state)
        flutter_vm.wait_for(self.d, flutter_vm.key("fab_new_list"), 45000)
        flutter_vm.home(self.d)

    def peer(self):
        p = LinuxFrontend()
        p.start()
        self._peers.append(p)
        return p
