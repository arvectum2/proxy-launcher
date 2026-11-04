"""Keep patched iOS Simulator slice reproducible for hosted UI-test target CI."""
import importlib.util
import plistlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "mobile/ios/Tools/fetch_tun2proxy.py"
spec = importlib.util.spec_from_file_location("apl_pinned_tun2proxy", TOOL)
tun2proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tun2proxy)


class SimulatorBuildContractTests(unittest.TestCase):
    def test_ci_requests_simulator_only_on_ui_build_job(self):
        pipeline = (ROOT / ".github/workflows/mobile-ios-personal.yml").read_text()
        self.assertEqual(pipeline.count("fetch_tun2proxy.py --with-simulator"), 1)
        self.assertIn("aarch64-apple-ios-sim", TOOL.read_text())
        self.assertIn("build-for-testing", pipeline)

    def test_pinned_rust_simulator_slice_is_deduplicated_with_shared_headers(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / "tun2proxy.xcframework"
            headers = f / "ios-arm64" / "Headers"
            headers.mkdir(parents=True)
            (headers / "tun2proxy.h").write_text("void tun2proxy_stop(void);\n")
            (headers / "module.modulemap").write_text("old")
            info = {
                "CFBundlePackageType": "XFWK",
                "AvailableLibraries": [{
                    "LibraryIdentifier": "ios-arm64", "LibraryPath": "libtun2proxy.a",
                    "SupportedArchitectures": ["arm64"], "SupportedPlatform": "ios"
                }],
            }
            with (f / "Info.plist").open("wb") as target:
                plistlib.dump(info, target)
            simulator_lib = Path(tmp) / "simulator-patched.a"
            simulator_lib.write_bytes(b"patched-simulator-binary")
            for _ in range(2):
                tun2proxy.add_simulator_slice(f, simulator_lib)
            with (f / "Info.plist").open("rb") as target:
                installed = plistlib.load(target)["AvailableLibraries"]
            self.assertEqual(len(installed), 2)
            sim = installed[1]
            self.assertEqual(sim["LibraryIdentifier"], "ios-arm64-simulator")
            self.assertEqual(sim["SupportedPlatformVariant"], "simulator")
            self.assertEqual(sim["SupportedArchitectures"], ["arm64"])
            self.assertEqual((f / "ios-arm64-simulator/libtun2proxy.a").read_bytes(), simulator_lib.read_bytes())
            self.assertIn("tun2proxy_stop", (f / "ios-arm64-simulator/Headers/tun2proxy.h").read_text())
            self.assertIn('module tun2proxy', (f / "ios-arm64-simulator/Headers/module.modulemap").read_text())


if __name__ == "__main__":
    unittest.main()
