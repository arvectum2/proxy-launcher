from pathlib import Path
import unittest


class WindowsInstallerWdacInvocationTests(unittest.TestCase):
    def test_inno_maintenance_helpers_are_not_launched_with_powershell_file_mode(self) -> None:
        installer = Path("installer/ArvectumProxyLauncher.iss").read_text(encoding="utf-8")

        exec_lines = [
            line.strip()
            for line in installer.splitlines()
            if "Result := Exec(PowerShell" in line
        ]

        self.assertEqual(len(exec_lines), 2, exec_lines)
        self.assertTrue(all(" -File " not in line for line in exec_lines), exec_lines)
        self.assertTrue(all("-ExecutionPolicy Bypass" in line for line in exec_lines), exec_lines)
        self.assertTrue(all("HelperPath" in line for line in exec_lines), exec_lines)


if __name__ == "__main__":
    unittest.main()
