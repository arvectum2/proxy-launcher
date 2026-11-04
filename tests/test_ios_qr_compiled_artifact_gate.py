"""Portable simulated app bundles for compiled QR artifact attestation."""
import importlib.util
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest import mock

script = Path(__file__).resolve().parents[1] / "mobile/ios/Tools/verify_qr_compiled_app.py"
spec = importlib.util.spec_from_file_location("apl_qr_compiled_fixture", script)
tool = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = tool
spec.loader.exec_module(tool)

class QRBundleGate(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.app = Path(self.t.name) / "Fixture.app"
        self.app.mkdir()
        (self.app / "Runner").write_bytes(b"fake")
        self.ext = self.app / "PlugIns" / "Arvectum Packet Tunnel.appex"
        self.ext.mkdir(parents=True)
        self.write(self.app / "Info.plist", {
            "CFBundleIdentifier": tool.APP_ID, "CFBundleExecutable": "Runner"})
        self.write(self.ext / "Info.plist", {"CFBundleIdentifier": tool.EXT_ID})
        self.source = mock.patch.object(tool.source_gate, "source_status",
            return_value={"source_feature_present": True, "source_commit": "a"*40})
        self.sym = mock.patch.object(tool, "demangle",
            return_value="\n".join(tool.SYMBOLS.values()))
        self.source.start()
        self.sym.start()

    def tearDown(self):
        self.sym.stop()
        self.source.stop()
        self.t.cleanup()

    def write(self, p, data):
        with p.open("wb") as f:
            plistlib.dump(data, f)

    def test_present_compiled_symbols_never_claim_apple_ipa(self):
        r = tool.attest(self.app, "HEAD")
        self.assertTrue(r["compiled_qr_in_local_app"])
        self.assertTrue(all(r["compiled_symbols"].values()))
        for k in ("apple_signed_archive_verified", "app_store_publication_verified",
                  "two_iphone_qa_verified"):
            self.assertFalse(r[k])

    def test_missing_source_ref_gate(self):
        with mock.patch.object(tool.source_gate, "source_status",
                               return_value={"source_feature_present": False}):
            with self.assertRaises(ValueError):
                tool.attest(self.app, "old")

    def test_missing_each_symbol_rejected(self):
        for k, needle in tool.SYMBOLS.items():
            with self.subTest(k=k), mock.patch.object(
                tool, "demangle",
                return_value="\n".join(x for x in tool.SYMBOLS.values() if x != needle)
            ), self.assertRaisesRegex(ValueError, "symbols"):
                tool.attest(self.app, "HEAD")

    def test_missing_packet_tunnel_rejected(self):
        import shutil
        shutil.rmtree(self.app / "PlugIns")
        with self.assertRaises(ValueError):
            tool.attest(self.app, "HEAD")

    def test_forged_app_id_rejected(self):
        self.write(self.app / "Info.plist", {
            "CFBundleIdentifier": "com.fake.qr",
            "CFBundleExecutable": "Runner"})
        with self.assertRaises(ValueError):
            tool.attest(self.app, "HEAD")

    def test_forged_extension_id_rejected(self):
        self.write(self.ext / "Info.plist", {"CFBundleIdentifier": "com.fake.ext"})
        with self.assertRaises(ValueError):
            tool.attest(self.app, "HEAD")

    def test_missing_executable_rejected(self):
        (self.app / "Runner").unlink()
        with self.assertRaises(ValueError):
            tool.attest(self.app, "HEAD")

    def test_relative_executable_escape_rejected(self):
        self.write(self.app / "Info.plist", {
            "CFBundleIdentifier": tool.APP_ID, "CFBundleExecutable": "../Runner"})
        with self.assertRaises(ValueError):
            tool.attest(self.app, "HEAD")

    def test_xcode_debug_dylib_is_scanned_not_just_stub(self):
        (self.app / "Runner.debug.dylib").write_bytes(b"fake")
        with mock.patch.object(tool, "demangle",
                               side_effect=["", "\n".join(tool.SYMBOLS.values())]) as read:
            self.assertTrue(tool.attest(self.app, "HEAD")["compiled_qr_in_local_app"])
            self.assertEqual(read.call_count, 2)

if __name__ == "__main__":
    unittest.main()
