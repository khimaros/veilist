# minimal check that appium can install, launch, and talk to the flutter app.

import flutter_ui as ui


def test_app_launches_to_listing(driver):
    # the new-list fab only exists on the listing page, so finding it proves
    # the app booted and the flutter handshake works.
    ui.wait_for(driver, ui.key("fab_new_list"))
