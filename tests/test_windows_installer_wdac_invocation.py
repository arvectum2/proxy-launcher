from pathlib import Path


def test_inno_maintenance_helpers_are_not_launched_with_powershell_file_mode() -> None:
    installer = Path("installer/ArvectumProxyLauncher.iss").read_text(encoding="utf-8")

    exec_lines = [
        line.strip()
        for line in installer.splitlines()
        if "Result := Exec(PowerShell" in line
    ]

    assert len(exec_lines) == 2, exec_lines
    assert all(" -File " not in line for line in exec_lines), exec_lines
    assert all("-ExecutionPolicy Bypass" in line for line in exec_lines), exec_lines
    assert all("HelperPath" in line for line in exec_lines), exec_lines
