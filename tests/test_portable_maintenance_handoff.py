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
        with mock.patch.object(core, "is_windows", return_value=False), \
             mock.patch.object(core, "ensure_stable_app_copy") as ensure:
            self.assertFalse(core.handoff_to_stable_copy(["--start"]))
        # The maintenance-command guard must not consume --start before the
        # platform/frozen checks that own the normal canonical handoff.
        ensure.assert_not_called()


if __name__ == "__main__":
    unittest.main()
