"""android frontend: drives the app on an emulator via appium flutter-driver
(flutter_ui). needs a booted emulator, a running appium server, and the driver
debug apk - all set up by matrix_run.sh (which reuses the test/e2e/appium
infrastructure). a second emulator (VEILIST_UDID_2) enables the collaboration
flows; without it they are skipped."""

import os
import subprocess
import sys

from appium import webdriver
from appium.options.common.base import AppiumOptions

_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
sys.path.insert(0, os.path.join(_ROOT, "test", "e2e", "appium"))
import flutter_ui  # noqa: E402

from frontend import SkipFlow  # noqa: E402
from widget_frontend import WidgetFrontend  # noqa: E402

APPIUM_URL = os.environ.get("APPIUM_URL", "http://127.0.0.1:4723")
APP_PACKAGE = "com.khimaros.veilist"
APP_ACTIVITY = "com.khimaros.veilist.MainActivity"


def _options(udid, apk, install):
    caps = {
        "platformName": "Android",
        "appium:automationName": "Flutter",
        "appium:udid": udid,
        "appium:deviceName": udid,
        "appium:appPackage": APP_PACKAGE,
        "appium:appActivity": APP_ACTIVITY,
        "appium:newCommandTimeout": 600,
        "appium:maxRetryCount": 40,
        "appium:retryBackoffTime": 3000,
    }
    if install:
        caps["appium:app"] = apk
        caps["appium:fullReset"] = True
    else:
        caps["appium:noReset"] = True
    opts = AppiumOptions()
    opts.load_capabilities(caps)
    return opts


class AndroidFrontend(WidgetFrontend):
    name = "android"
    supports_peers = True

    def __init__(self, udid=None):
        super().__init__()
        self.ui = flutter_ui
        self._udid = udid or os.environ.get("VEILIST_UDID", "emulator-5554")
        # never touch a real device (e.g. a phone plugged in for development):
        # the matrix reinstalls and pm-clears state, which must only ever hit a
        # throwaway emulator.
        if not self._udid.startswith("emulator-"):
            raise RuntimeError(
                f"refusing to run the android matrix on non-emulator device "
                f"'{self._udid}'; it only runs on an emulator (emulator-NNNN)"
            )
        self._apk = os.environ.get(
            "VEILIST_APK",
            os.path.join(_ROOT, "build/app/outputs/flutter-apk/app-debug.apk"),
        )
        self._peers = []

    def start(self):
        # the apk is installed once by matrix_run.sh; every session is noReset so
        # appium never uninstalls it on quit. fresh state per flow comes from a
        # force-stop in reset().
        self.d = webdriver.Remote(
            APPIUM_URL, options=_options(self._udid, self._apk, install=False)
        )
        self._await_online()

    def _await_online(self):
        # disable frame sync: the share button becomes an infinite spinner while
        # publishing, and appium's waitFor otherwise blocks waiting for the frame
        # to settle (which it never does). flutter_vm disables it for the same
        # reason, so linux/web were unaffected.
        try:
            self.d.execute_script("flutter:setFrameSync", False)
        except Exception:
            pass
        # the emulator's veilid re-attaches on each relaunch; wait until it is
        # actually online (public dht reachable) before a flow, so a share can
        # publish instead of blocking on an unready node. linux/web attach fast
        # enough not to need this.
        flutter_ui.wait_for(self.d, flutter_ui.key("fab_new_list"), 45000)
        try:
            flutter_ui.wait_for(self.d, flutter_ui.tooltip("veilid: online"), 90000)
        except Exception:
            pass  # proceed even if it never onlines; the flow will report it

    def reset(self):
        # force-stop + relaunch between flows: a fresh activity (so a stuck flow
        # cannot cascade) that KEEPS veilid's identity/state, so the node
        # re-attaches in seconds. pm clear would wipe the identity and force a
        # slow fresh bootstrap, leaving the node unready when a share publishes.
        # flows use unique names, so the accumulating roster does not
        # cross-contaminate (and the sync no longer crashes on a growing roster).
        for p in self._peers:
            p.stop()
        self._peers = []
        try:
            self.d.quit()
        except Exception:
            pass
        subprocess.run(
            ["adb", "-s", self._udid, "shell", "am", "force-stop", APP_PACKAGE],
            check=False,
            capture_output=True,
        )
        self.d = webdriver.Remote(
            APPIUM_URL, options=_options(self._udid, self._apk, install=False)
        )
        self._await_online()

    def stop(self):
        for p in self._peers:
            p.stop()
        self._peers = []
        try:
            self.d.quit()
        except Exception:
            pass

    def restart(self):
        # a genuine close-and-reopen: kill the process (not just the appium
        # session) so f's veilid node actually stops and misses edits made while
        # it is gone, then cold-start. state is kept (no pm clear), so it reopens
        # on the listing and re-attaches fast. without the force-stop the app
        # stays alive on its last route and the reconnect never sees the listing.
        try:
            self.d.quit()
        except Exception:
            pass
        subprocess.run(
            ["adb", "-s", self._udid, "shell", "am", "force-stop", APP_PACKAGE],
            check=False,
            capture_output=True,
        )
        self.d = webdriver.Remote(
            APPIUM_URL, options=_options(self._udid, self._apk, install=False)
        )
        self._await_online()

    def peer(self):
        udid = os.environ.get("VEILIST_UDID_2")
        if not udid:
            raise SkipFlow("no second emulator (set VEILIST_UDID_2)")
        # a previous collab flow leaves the peer's app running on whatever page it
        # ended on; force-stop it so the new session launches fresh on the listing
        # (start() waits for the fab). state is kept (no pm clear), so veilid
        # re-attaches in seconds.
        subprocess.run(
            ["adb", "-s", udid, "shell", "am", "force-stop", APP_PACKAGE],
            check=False,
            capture_output=True,
        )
        p = AndroidFrontend(udid=udid)
        p.start()
        self._peers.append(p)
        return p
