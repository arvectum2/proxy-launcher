import unittest
from unittest import mock

import proxy_gui as gui


class _BoolVar:
    def __init__(self, value):
        self.value = value

    def get(self):
        return self.value

    def set(self, value):
        self.value = value


class _Completed:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


class ProductionSafeAutostartTests(unittest.TestCase):
    def launcher(self, value=True):
        launcher = gui.Launcher.__new__(gui.Launcher)
        launcher.auto_var = _BoolVar(value)
        return launcher

    def test_task_ownership_requires_owned_exec_action(self):
        launcher = self.launcher()
        xml = """<?xml version='1.0'?>
<Task xmlns='http://schemas.microsoft.com/windows/2004/02/mit/task'>
  <RegistrationInfo>
    <Description>C:\\Users\\Test\\Documents\\ArvectumProxyLauncher\\Arvectum Proxy Launcher.exe --start</Description>
  </RegistrationInfo>
  <Actions><Exec><Command>C:\\Windows\\System32\\notepad.exe</Command></Exec></Actions>
</Task>"""
        with mock.patch.object(gui.core, "is_owned_arvectum_start_command", return_value=False) as owned:
            self.assertFalse(launcher._autostart_task_is_ours(xml))
        owned.assert_called_once()
        self.assertIn("notepad.exe", owned.call_args.args[0])

    def test_task_ownership_accepts_owned_exec_action(self):
        launcher = self.launcher()
        xml = """<?xml version='1.0'?>
<Task xmlns='http://schemas.microsoft.com/windows/2004/02/mit/task'>
  <Actions><Exec>
    <Command>C:\\Users\\Test\\Documents\\ArvectumProxyLauncher\\Arvectum Proxy Launcher.exe</Command>
    <Arguments>--start</Arguments>
  </Exec></Actions>
</Task>"""
        with mock.patch.object(
                gui.core,
                "is_owned_arvectum_start_command",
                side_effect=lambda command: "Arvectum Proxy Launcher.exe" in command and "--start" in command):
            self.assertTrue(launcher._autostart_task_is_ours(xml))

    def test_enable_requires_exact_post_write_run_value(self):
        launcher = self.launcher(True)
        launcher._autostart_run_value = mock.Mock(side_effect=[None, '"C:\\wrong.exe" --start'])
        launcher._autostart_run_is_ours = mock.Mock(return_value=False)
        launcher._autostart_task_xml = mock.Mock(return_value=None)
        launcher._autostart_task_is_ours = mock.Mock(return_value=False)
        launcher._write_autostart_run_value = mock.Mock()

        with mock.patch.object(gui, "_is_macos", return_value=False), \
             mock.patch.object(gui.core, "load_settings", return_value={"upstream": [{"host": "proxy.invalid"}]}), \
             mock.patch.object(gui, "_portable_fallback_active", return_value=False), \
             mock.patch.object(gui, "_autostart_target", return_value='"C:\\canonical.exe" --start'), \
             mock.patch.object(gui.messagebox, "showerror") as error:
            self.assertFalse(launcher._enable_autostart())

        launcher._write_autostart_run_value.assert_called_once_with('"C:\\canonical.exe" --start')
        error.assert_called_once()

    def test_enable_rolls_back_new_run_when_owned_legacy_task_cannot_be_removed(self):
        launcher = self.launcher(True)
        target = '"C:\\canonical.exe" --start'
        launcher._autostart_run_value = mock.Mock(side_effect=[None, target])
        launcher._autostart_run_is_ours = mock.Mock(side_effect=lambda value=None: value == target)
        launcher._autostart_task_xml = mock.Mock(side_effect=["owned xml", "owned xml"])
        launcher._autostart_task_is_ours = mock.Mock(side_effect=lambda xml=None: xml == "owned xml")
        launcher._write_autostart_run_value = mock.Mock()
        launcher._delete_owned_autostart_run_value = mock.Mock(return_value=True)

        with mock.patch.object(gui, "_is_macos", return_value=False), \
             mock.patch.object(gui.core, "load_settings", return_value={"upstream": [{"host": "proxy.invalid"}]}), \
             mock.patch.object(gui, "_portable_fallback_active", return_value=False), \
             mock.patch.object(gui, "_autostart_target", return_value=target), \
             mock.patch.object(gui.subprocess, "run", return_value=_Completed(returncode=1)), \
             mock.patch.object(gui.messagebox, "showerror"):
            self.assertFalse(launcher._enable_autostart())

        launcher._delete_owned_autostart_run_value.assert_called_once()

    def test_disable_cleans_owned_run_and_owned_legacy_task(self):
        launcher = self.launcher(False)
        launcher._autostart_run_value = mock.Mock(side_effect=["owned run", None])
        launcher._autostart_run_is_ours = mock.Mock(side_effect=lambda value=None: value == "owned run")
        launcher._delete_owned_autostart_run_value = mock.Mock(return_value=True)
        launcher._autostart_task_xml = mock.Mock(side_effect=["owned xml", None])
        launcher._autostart_task_is_ours = mock.Mock(side_effect=lambda xml=None: xml == "owned xml")

        with mock.patch.object(gui, "_is_macos", return_value=False), \
             mock.patch.object(gui.subprocess, "run", return_value=_Completed(returncode=0)) as run, \
             mock.patch.object(gui.messagebox, "showerror") as error:
            self.assertTrue(launcher._disable_autostart())

        launcher._delete_owned_autostart_run_value.assert_called_once()
        run.assert_called_once_with(
            ["schtasks", "/Delete", "/F", "/TN", gui.TASK_NAME],
            capture_output=True,
            text=True,
        )
        error.assert_not_called()

    def test_disable_reports_owned_task_that_survives_delete(self):
        launcher = self.launcher(False)
        launcher._autostart_run_value = mock.Mock(return_value=None)
        launcher._autostart_run_is_ours = mock.Mock(return_value=False)
        launcher._delete_owned_autostart_run_value = mock.Mock(return_value=False)
        launcher._autostart_task_xml = mock.Mock(side_effect=["owned xml", "owned xml"])
        launcher._autostart_task_is_ours = mock.Mock(side_effect=lambda xml=None: xml == "owned xml")

        with mock.patch.object(gui, "_is_macos", return_value=False), \
             mock.patch.object(gui.subprocess, "run", return_value=_Completed(returncode=0)), \
             mock.patch.object(gui.messagebox, "showerror") as error:
            self.assertFalse(launcher._disable_autostart())

        error.assert_called_once()


if __name__ == "__main__":
    unittest.main()
