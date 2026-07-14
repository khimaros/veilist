# live two-emulator collaboration over the real veilid dht (R1, R2, R4). alice
# creates and shares a list; bob opens the share link, sees alice's items, and
# their edits converge in both directions. this is the python replacement for
# the old dart integration_test/two_device_test.dart: it drives the real ui on
# both devices, so it exercises deep-link join and collaboration exactly as a
# user would. veilid must attach on both emulators, so the waits are generous.

import os

import pytest

import app_flows as flows
import flutter_ui as ui
from conftest import new_driver

ALICE_UDID = os.environ.get("VEILIST_ALICE_UDID", "emulator-5554")
BOB_UDID = os.environ.get("VEILIST_BOB_UDID", "emulator-5556")

# veilid can take a while to attach on a cold emulator; dht propagation plus
# watch delivery is slower still. these mirror the old dart test's budgets.
ATTACH_TIMEOUT = 240000
CONVERGE_TIMEOUT = 180000

ONLINE = ui.tooltip("veilid: online")


@pytest.fixture(scope="module")
def alice():
    drv = new_driver(ALICE_UDID, install=True)
    yield drv
    drv.quit()


@pytest.fixture(scope="module")
def bob():
    drv = new_driver(BOB_UDID, install=True)
    yield drv
    drv.quit()


def test_share_link_and_bidirectional_convergence(alice, bob):
    # both nodes must reach the public dht before sharing/joining.
    ui.wait_for(alice, ONLINE, timeout=ATTACH_TIMEOUT)
    ui.wait_for(bob, ONLINE, timeout=ATTACH_TIMEOUT)

    # R1: alice creates a list, adds an item, and gets a share link.
    name = flows.unique("shared")
    flows.create_list(alice, name)
    flows.open_list(alice, name)
    flows.add_item(alice, "from alice")
    ui.tap(alice, ui.tooltip("share"))
    link = ui.get_text(alice, ui.key("app_link_value"))
    assert link.startswith("veilist://"), link
    ui.tap(alice, ui.text("done"))

    # R2 + R4: bob opens the deep link and sees alice's list and item. joining
    # navigates straight into the list detail.
    ui.tap(bob, ui.key("open_link_button"))
    ui.enter_text(bob, ui.key("prompt_field"), link)
    ui.tap(bob, ui.key("prompt_action"))
    ui.wait_for(bob, ui.text("from alice"), timeout=CONVERGE_TIMEOUT)

    # R4: bob's edit propagates back to alice (convergence both ways).
    flows.add_item(bob, "from bob")
    ui.wait_for(alice, ui.text("from bob"), timeout=CONVERGE_TIMEOUT)
