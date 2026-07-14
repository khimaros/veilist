# pytest fixtures for the appium flutter-driver ui suite. a session-scoped
# driver launches the app once on a single emulator; two-device tests declare
# their own drivers. the apk must be the driver build (it calls
# enableFlutterDriverExtension), see test/scripts/appium_e2e_run.sh.

import os

import pytest
from appium import webdriver
from appium.options.common.base import AppiumOptions

APPIUM_URL = os.environ.get("APPIUM_URL", "http://127.0.0.1:4723")
APP_PACKAGE = "com.khimaros.veilist"
APP_ACTIVITY = "com.khimaros.veilist.MainActivity"

# the driver waits this long for the app's dart vm service to come up before
# giving up on the flutter handshake.
FLUTTER_CONNECT_RETRIES = 40
FLUTTER_CONNECT_BACKOFF_MS = 3000


def _apk_path():
    path = os.environ.get("VEILIST_APK")
    if not path:
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
        path = os.path.join(
            root, "build", "app", "outputs", "flutter-apk", "app-debug.apk"
        )
    if not os.path.exists(path):
        raise RuntimeError(f"apk not found: {path}; run the driver build first")
    return path


def make_options(udid, install=True):
    caps = {
        "platformName": "Android",
        "appium:automationName": "Flutter",
        "appium:udid": udid,
        "appium:deviceName": udid,
        "appium:appPackage": APP_PACKAGE,
        "appium:appActivity": APP_ACTIVITY,
        "appium:newCommandTimeout": 600,
        "appium:maxRetryCount": FLUTTER_CONNECT_RETRIES,
        "appium:retryBackoffTime": FLUTTER_CONNECT_BACKOFF_MS,
    }
    if install:
        # a fresh install gives each run a clean list-of-lists (R5).
        caps["appium:app"] = _apk_path()
        caps["appium:fullReset"] = True
    else:
        caps["appium:noReset"] = True
    options = AppiumOptions()
    options.load_capabilities(caps)
    return options


def new_driver(udid, install=True):
    return webdriver.Remote(APPIUM_URL, options=make_options(udid, install))


@pytest.fixture(scope="module")
def driver():
    udid = os.environ.get("VEILIST_UDID", "emulator-5554")
    drv = new_driver(udid, install=True)
    yield drv
    drv.quit()
