import os
import unittest
from unittest import mock

import proxy_core as core
import portable_lifecycle


class PortableMaintenanceHandoffTests(unittest.TestCase):
    def test_stop_status_and_rollback_never_use_async_stable_copy_handoff(self):
        for command in ("--stop", "--status", "--rollback"):
            with self.subTest(command=command), \
                 mock.patch.object(core, "ensure_stable_app_copy") as ensure, \
                 mock.patch.object(portable_lifecycle.subprocess, "Popen") as spawn:
                self.assertFalse(core.handoff_to_stable_copy([command]))
            ensure.assert_not_called()
            spawn.assert_not_called()

    def test_start_remains_eligible_for_stable_copy_handoff(self):
        source = os.path.realpath("source-launcher.exe")
        target = os.path.realpath("canonical-launcher.exe")
        with mock.patch.object(core, "is_windows", return_value=True), \
             mock.patch.object(portable_lifecycle.sys, "frozen", True, create=True), \
             mock.patch.object(portable_lifecycle.sys, "executable", source), \
             mock.patch.object(core, "ensure_stable_app_copy", return_value=target) as ensure, \
             mock.patch.object(core, "_same_path", return_value=False), \
             mock.patch.object(portable_lifecycle.subprocess, "Popen") as spawn:
            self.assertTrue(core.handoff_to_stable_copy(["--start"]))
        ensure.assert_called_once_with()
        spawn.assert_called_once_with(
            [target, "--start"],
            cwd=os.path.dirname(target),
            creationflags=getattr(portable_lifecycle.subprocess, "CREATE_NEW_PROCESS_GROUP", 0),
        )


if __name__ == "__main__":
    unittest.main()
