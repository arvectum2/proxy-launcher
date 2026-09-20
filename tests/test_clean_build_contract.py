import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class CleanBuildContractTests(unittest.TestCase):
    def read(self, name: str) -> str:
        return (ROOT / name).read_text(encoding="utf-8-sig")

    def test_build_python_version_pinned(self):
        self.assertTrue((ROOT / "BUILD_PYTHON_VERSION").is_file())
        version = self.read("BUILD_PYTHON_VERSION").strip()
        self.assertEqual(version, "3.12.10")

    def test_requirements_build_lock_pinned(self):
        self.assertTrue((ROOT / "requirements-build.lock.txt").is_file())
        lock_text = self.read("requirements-build.lock.txt")
        self.assertIn("pyinstaller==6.22.0", lock_text)
        self.assertNotIn(">=", lock_text)
        self.assertNotIn("~=", lock_text)
        self.assertNotIn("*", lock_text)

    def test_clean_build_windows_script_contract(self):
        self.assertTrue((ROOT / "tools" / "clean_build_windows.ps1").is_file())
        script = self.read("tools/clean_build_windows.ps1")

        # Cleanup of build paths
        self.assertIn(".build-venv", script)
        self.assertIn("build", script)
        self.assertIn("dist", script)
        self.assertIn("out", script)
        self.assertIn("artifact", script)

        # Fresh isolated venv
        self.assertIn("-m venv", script)
        self.assertIn("sys.prefix != sys.base_prefix", script)

        # Toolchain installation. The online compatibility path remains version-pinned;
        # the controlled release path can additionally enforce an offline hash-locked wheelhouse.
        self.assertIn("pip==26.1.2", script)
        self.assertNotIn("pip==25.3", script)
        self.assertIn("requirements-build.lock.txt", script)
        self.assertIn("requirements-build.windows-x64.hashes.txt", script)
        self.assertIn("--no-index", script)
        self.assertIn("--require-hashes", script)
        self.assertIn("pip check", script)

        # Compilation & tests
        self.assertIn("py_compile", script)
        self.assertIn("unittest discover", script)

        # PyInstaller build
        self.assertIn("PyInstaller", script)
        self.assertIn('Arvectum Proxy Launcher.exe', script)

        # Packaging & Checksums
        self.assertIn("SHA256SUMS.txt", script)
        self.assertIn("Compress-Archive", script)
        self.assertIn("Expand-Archive", script)
        self.assertIn("build-result.json", script)

    def test_build_exe_bat_is_wrapper(self):
        bat = self.read("build_exe.bat")
        self.assertIn("tools\\clean_build_windows.ps1", bat)
        self.assertNotIn("PyInstaller", bat)
        self.assertNotIn("pip install", bat)
        self.assertNotIn("unittest", bat)

    def test_windows_workflow_uses_clean_build_script(self):
        workflow = self.read(".github/workflows/windows-p0.yml")
        self.assertIn("python-version: '3.12.10'", workflow)
        self.assertIn("./tools/clean_build_windows.ps1", workflow)
        self.assertNotIn("PyInstaller --noconfirm", workflow)
        self.assertNotIn("pip install --upgrade pip==", workflow)

    def test_package_does_not_contain_runtime_state_or_secrets(self):
        script = self.read("tools/clean_build_windows.ps1")
        # Expected files in package are explicit
        self.assertIn('$ExpectedFiles = @("Arvectum Proxy Launcher.exe", "README.txt", "diagnose_app_control.ps1", "run_p01_native_qa_v2.ps1", "SHA256SUMS.txt")', script)
        self.assertNotIn("proxy_settings.json", script.split("$ExpectedFiles")[1].split("foreach")[0])


if __name__ == "__main__":
    unittest.main()