import os
import tempfile
import unittest
from unittest import mock

import application_filesystem
import proxy_core as core


class LinuxStatePathTests(unittest.TestCase):
    def test_absolute_xdg_state_home_is_canonical_runtime_root(self):
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(application_filesystem.sys, "platform", "linux"), \
             mock.patch.dict(application_filesystem.os.environ, {
                 "HOME": td,
                 "XDG_STATE_HOME": os.path.join(td, "xdg-state"),
             }, clear=False):
            expected = os.path.join(td, "xdg-state", "Arvectum", "ProxyLauncher")
            self.assertEqual(core.data_dir(), expected)
            self.assertEqual(core.settings_path(), os.path.join(expected, "proxy_settings.json"))

    def test_relative_xdg_state_home_falls_back_to_home_state(self):
        with tempfile.TemporaryDirectory() as td, \
             mock.patch.object(application_filesystem.sys, "platform", "linux"), \
             mock.patch.dict(application_filesystem.os.environ, {
                 "HOME": td,
                 "XDG_STATE_HOME": "relative-state",
             }, clear=False):
            expected = os.path.join(td, ".local", "state", "Arvectum", "ProxyLauncher")
            self.assertEqual(core.data_dir(), expected)


if __name__ == "__main__":
    unittest.main()
