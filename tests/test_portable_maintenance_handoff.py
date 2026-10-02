import json
import os
import tempfile
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

    def test_maintenance_main_never_repairs_run_entries_or_self_heals(self):
        commands = (
            ("--stop", "_cmd_stop"),
            ("--status", "_cmd_status"),
            ("--rollback", "_cmd_rollback"),
        )
        for command, handler_name in commands:
            with self.subTest(command=command), \
                 mock.patch.object(
                     portable_lifecycle.sys,
                     "argv",
                     ["Arvectum Proxy Launcher.exe", command],
                 ), \
                 mock.patch.object(core, "_ensure_local_files", return_value=True), \
                 mock.patch.object(core, "repair_portable_run_entries") as repair, \
                 mock.patch.object(core, "managed_executable") as managed, \
                 mock.patch.object(core, handler_name, return_value=0) as handler:
                self.assertEqual(core.main(), 0)
            repair.assert_not_called()
            managed.assert_not_called()
            handler.assert_called_once_with()

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


class PortableSupportSyncTests(unittest.TestCase):
    def test_stable_copy_carries_manifest_and_windivert_sidecar(self):
        with tempfile.TemporaryDirectory() as td:
            source_dir = os.path.join(td, "source")
            target_dir = os.path.join(td, "target")
            os.makedirs(source_dir)
            source = os.path.join(
                source_dir, "Arvectum Proxy Launcher.exe"
            )
            target = os.path.join(
                target_dir, "Arvectum Proxy Launcher.exe"
            )
            with open(source, "wb") as stream:
                stream.write(b"portable-exe")
            with open(
                os.path.join(source_dir, "build_manifest.json"),
                "w",
                encoding="utf-8",
            ) as stream:
                json.dump({"source_commit": "a" * 40}, stream)
            sidecar = os.path.join(source_dir, "WINDOWS_WINDIVERT")
            os.makedirs(sidecar)
            with open(
                os.path.join(sidecar, "windivert-stack-build.json"),
                "w",
                encoding="utf-8",
            ) as stream:
                json.dump({"source_commit": "a" * 40}, stream)

            with mock.patch.object(
                core, "is_windows", return_value=True
            ), mock.patch.object(
                portable_lifecycle.sys,
                "frozen",
                True,
                create=True,
            ), mock.patch.object(
                portable_lifecycle.sys, "executable", source
            ), mock.patch.object(
                core, "stable_app_exe", return_value=target
            ), mock.patch.object(
                core, "_same_path", return_value=False
            ):
                self.assertEqual(
                    core.ensure_stable_app_copy(),
                    os.path.realpath(target),
                )

            self.assertTrue(os.path.isfile(target))
            self.assertTrue(
                os.path.isfile(
                    os.path.join(target_dir, "build_manifest.json")
                )
            )
            self.assertTrue(
                os.path.isfile(
                    os.path.join(
                        target_dir,
                        "WINDOWS_WINDIVERT",
                        "windivert-stack-build.json",
                    )
                )
            )


if __name__ == "__main__":
    unittest.main()
