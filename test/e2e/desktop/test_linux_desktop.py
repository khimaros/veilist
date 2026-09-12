"""linux desktop integration e2e.

launches the real bundle on a private headless display and reads the window back
with xprop, then installs into a throwaway prefix and inspects what a shell would
find. this is the only layer that looks at the window itself - the compliance
matrix drives the widgets inside it and never sees the icon, the title bar, or
the desktop entry the shell matches the window to.

the two things under test are one mechanism: gnome names and illustrates a
window by matching its wayland app_id (gtk takes it from the application id) to a
desktop entry of the same name, so a missing entry means both a generic icon and
a window called "com.khimaros.veilist".
"""

import os
import re
import shutil
import signal
import subprocess
import tempfile
import time

import pytest

_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

APP_ID = "com.khimaros.veilist"
BINARY_NAME = "veilist"
# the name a person should read in the shell, rather than the application id.
APP_NAME = "veilist"

# the desktop integration files inside the bundle. data/applications and
# data/icons mirror the xdg layout under $PREFIX/share, so installing is a copy.
DESKTOP_ENTRY = f"data/applications/{APP_ID}.desktop"
ICON_ROOT = "data/icons"
ICON_SIZES = (16, 24, 32, 48, 64, 128, 256, 512)

# any build mode proves the same integration; prefer the one a user would ship.
BUILD_MODES = ("release", "profile", "debug")

WINDOW_TIMEOUT = 90
# bytes of _NET_WM_ICON to pull back: enough for the first icon's dimensions and
# a sample of its pixels, without dragging every icon through xprop as text.
ICON_PROBE_BYTES = 64


def _read(path):
    with open(path) as f:
        return f.read()


def _entries(text):
    """the key=value pairs of a desktop entry's [Desktop Entry] group."""
    out = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def _run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


@pytest.fixture(scope="session")
def bundle():
    for mode in BUILD_MODES:
        path = os.path.join(_ROOT, "build", "linux", "x64", mode, "bundle")
        if os.path.exists(os.path.join(path, BINARY_NAME)):
            return path
    pytest.fail("no linux bundle found; build one with `make build-linux`")


def _start_xvfb(logdir):
    """a private x server, on whichever display number it picks for itself. the
    read blocks until the server is accepting connections, so no sleep-and-hope."""
    r, w = os.pipe()
    log = open(os.path.join(logdir, "xvfb.log"), "w")
    proc = subprocess.Popen(
        ["Xvfb", "-displayfd", str(w), "-screen", "0", "1280x720x24"],
        pass_fds=(w,), stdout=log, stderr=subprocess.STDOUT,
    )
    os.close(w)
    with os.fdopen(r) as f:
        num = f.readline().strip()
    if not num:
        proc.kill()
        raise RuntimeError("Xvfb did not start")
    return proc, f":{num}"


def _x(cmd, display):
    return _run(cmd, env=dict(os.environ, DISPLAY=display)).stdout


def _window_ids(display):
    out = _x(["xwininfo", "-root", "-children"], display)
    return re.findall(r"^\s+(0x[0-9a-f]+)", out, re.M)


def _prop(display, wid, name, length=None, as_cardinals=False):
    """one x property as text, or None when the window does not carry it."""
    cmd = ["xprop", "-id", wid]
    if as_cardinals:
        # xprop draws an icon property as colour blocks, and draws NOTHING at
        # all once -len truncates it, so ask for the numbers instead: a short
        # read then still carries the dimensions and the first pixels.
        cmd += ["-f", name, "32c", " = $0+"]
    if length is not None:
        cmd += ["-len", str(length)]
    out = _x(cmd + [name], display)
    if not out or "not found" in out:
        return None
    return out.split("=", 1)[1].strip() if "=" in out else None


@pytest.fixture(scope="session")
def window(bundle):
    """the running app's window, as the properties a desktop shell reads."""
    state = tempfile.mkdtemp(prefix="veilist-desktop-")
    xvfb, display = _start_xvfb(state)
    env = dict(os.environ, DISPLAY=display, GDK_BACKEND="x11")
    env.pop("WAYLAND_DISPLAY", None)
    # a throwaway home so the test never touches the developer's own lists, and
    # never sees an icon theme they happen to have installed.
    for var in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"):
        sub = os.path.join(state, var.split("_")[1].lower())
        os.makedirs(sub, exist_ok=True)
        env[var] = sub
    log = open(os.path.join(state, "app.log"), "w")
    app = subprocess.Popen(
        [os.path.join(bundle, BINARY_NAME)], env=env, stdout=log,
        stderr=subprocess.STDOUT, start_new_session=True,
    )
    wid = None
    deadline = time.time() + WINDOW_TIMEOUT
    while time.time() < deadline and wid is None:
        if app.poll() is not None:
            pytest.fail(f"app exited early: {_read(os.path.join(state, 'app.log'))}")
        for candidate in _window_ids(display):
            klass = _prop(display, candidate, "WM_CLASS")
            if klass and APP_ID in klass:
                wid = candidate
                break
        if wid is None:
            time.sleep(1)
    if wid is None:
        pytest.fail(f"no window after {WINDOW_TIMEOUT}s: "
                    f"{_read(os.path.join(state, 'app.log'))}")
    try:
        yield display, wid
    finally:
        # the app gets a session of its own (veilid spawns threads and children),
        # so kill the group; xvfb shares ours and must be killed by pid alone.
        try:
            os.killpg(os.getpgid(app.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            app.kill()
        xvfb.kill()
        log.close()
        shutil.rmtree(state, ignore_errors=True)


def test_the_bundle_ships_a_desktop_entry(bundle):
    path = os.path.join(bundle, DESKTOP_ENTRY)
    assert os.path.exists(path), (
        f"{DESKTOP_ENTRY} is missing from the bundle, so a shell has nothing to "
        "match the window against"
    )
    entry = _entries(_read(path))
    assert entry.get("Name") == APP_NAME
    assert entry.get("Icon") == APP_ID
    assert entry.get("Type") == "Application"
    # gnome falls back to this when the app_id does not match the entry's name.
    assert entry.get("StartupWMClass") == APP_ID


def test_the_desktop_entry_is_valid(bundle):
    if not shutil.which("desktop-file-validate"):
        pytest.skip("desktop-file-validate not installed")
    path = os.path.join(bundle, DESKTOP_ENTRY)
    if not os.path.exists(path):
        pytest.fail(f"{DESKTOP_ENTRY} is missing from the bundle")
    result = _run(["desktop-file-validate", path])
    assert result.returncode == 0, result.stdout + result.stderr


def test_the_bundle_ships_an_icon_theme(bundle):
    missing = [
        size for size in ICON_SIZES
        if not os.path.exists(os.path.join(
            bundle, ICON_ROOT, "hicolor", f"{size}x{size}", "apps", f"{APP_ID}.png"))
    ]
    assert not missing, f"no icon rendered at {missing}"
    scalable = os.path.join(
        bundle, ICON_ROOT, "hicolor", "scalable", "apps", f"{APP_ID}.svg")
    assert os.path.exists(scalable), "no scalable icon for hidpi shells"


def test_the_window_carries_an_icon(window):
    """_NET_WM_ICON is what alt-tab, the window list, and the dock draw."""
    display, wid = window
    raw = _prop(display, wid, "_NET_WM_ICON", length=ICON_PROBE_BYTES,
                as_cardinals=True)
    assert raw is not None, "_NET_WM_ICON is not set, so the window has no icon"
    values = [int(v) for v in re.findall(r"\d+", raw)]
    assert len(values) > 2, "_NET_WM_ICON carries no pixels"
    width, height = values[0], values[1]
    assert width == height and width >= 16, f"implausible icon size {width}x{height}"
    assert any(values[2:]), "the icon is entirely transparent black"


def test_the_window_matches_the_desktop_entry(window, bundle):
    """the match that makes the shell print "veilist" instead of the app id."""
    display, wid = window
    klass = _prop(display, wid, "WM_CLASS")
    res_name = re.findall(r'"([^"]*)"', klass or "")
    assert res_name and res_name[0] == APP_ID
    assert os.path.basename(DESKTOP_ENTRY) == f"{res_name[0]}.desktop"


def _check_installed(prefix):
    """what a shell reading $PREFIX/share would find."""
    entry_path = os.path.join(prefix, "share/applications", f"{APP_ID}.desktop")
    assert os.path.exists(entry_path)
    entry = _entries(_read(entry_path))
    assert entry.get("Name") == APP_NAME
    # an entry the shell cannot launch is worse than no entry at all: it shows up
    # in the menu and does nothing.
    exec_path = entry["Exec"].split()[0]
    assert os.path.isabs(exec_path), f"Exec is not absolute: {exec_path}"
    assert os.access(exec_path, os.X_OK), f"Exec is not executable: {exec_path}"

    for size in ICON_SIZES:
        icon = os.path.join(
            prefix, "share/icons/hicolor", f"{size}x{size}", "apps", f"{APP_ID}.png")
        assert os.path.exists(icon), f"no {size}px icon installed"


def test_installing_lands_where_the_shell_looks(bundle):
    script = os.path.join(_ROOT, "scripts", "install_linux.sh")
    assert os.path.exists(script), "there is no way to install the app"
    with tempfile.TemporaryDirectory(prefix="veilist-prefix-") as prefix:
        result = _run(["bash", script, bundle], env=dict(os.environ, PREFIX=prefix))
        assert result.returncode == 0, result.stdout + result.stderr
        _check_installed(prefix)


def test_the_bundle_installs_itself(bundle):
    """the copy in the release tarball, which is handed no bundle to install and
    has to find the one around it."""
    script = os.path.join(bundle, "install.sh")
    assert os.access(script, os.X_OK), "the bundle carries no executable install.sh"
    with tempfile.TemporaryDirectory(prefix="veilist-prefix-") as prefix:
        result = _run([script], env=dict(os.environ, PREFIX=prefix))
        assert result.returncode == 0, result.stdout + result.stderr
        _check_installed(prefix)
