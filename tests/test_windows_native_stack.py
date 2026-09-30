import hashlib
import json
import os
import tempfile
import unittest
from unittest import mock

import windows_native_stack as native


def _hash(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class WindowsNativeStackTests(unittest.TestCase):
    def _fixture(self, root, *, mode="production", protocol=3):
        driver_path = os.path.join(root, native.DRIVER_FILENAME)
        service_path = os.path.join(root, native.SERVICE_FILENAME)
        with open(driver_path, "wb") as stream:
            stream.write(b"driver")
        with open(service_path, "wb") as stream:
            stream.write(b"service")
        marker = {
            "schema": native.SCHEMA,
            "signing_mode": mode,
            "protocol_version": protocol,
            "install_root": root,
            "source_commit": "abc123",
            "version": "0.2.16",
            "driver": {
                "filename": native.DRIVER_FILENAME,
                "service_name": native.DRIVER_SERVICE_NAME,
                "sha256": _hash(driver_path),
                "image_path": driver_path,
            },
            "service": {
                "filename": native.SERVICE_FILENAME,
                "service_name": native.ROUTING_SERVICE_NAME,
                "sha256": _hash(service_path),
                "image_path": service_path,
            },
        }
        marker_path = os.path.join(root, "native-stack.json")
        with open(marker_path, "w", encoding="utf-8") as stream:
            json.dump(marker, stream)
        return marker_path, driver_path, service_path

    def _records(self, driver_path, service_path):
        return {
            native.DRIVER_SERVICE_NAME: {
                "image_path": driver_path,
                "type": 1,
                "start": 3,
            },
            native.ROUTING_SERVICE_NAME: {
                "image_path": service_path,
                "type": 16,
                "start": 2,
            },
        }

    def test_non_windows_fails_closed(self):
        with mock.patch.object(native, "_is_windows", return_value=False):
            result = native.windows_native_stack_readiness(marker_path="unused")
        self.assertFalse(result["ready"])
        self.assertEqual(result["state"], "not_windows")

    def test_production_marker_requires_exact_files_services_and_running_state(self):
        with tempfile.TemporaryDirectory() as td:
            marker, driver_path, service_path = self._fixture(td)
            records = self._records(driver_path, service_path)
            with mock.patch.object(native, "_is_windows", return_value=True), \
                 mock.patch.object(native, "_service_registry_record", side_effect=lambda name: records.get(name)), \
                 mock.patch.object(native, "_service_running", return_value=True):
                result = native.windows_native_stack_readiness(marker_path=marker)
        self.assertTrue(result["ready"])
        self.assertEqual(result["state"], "production_ready")
        self.assertEqual(result["protocol_version"], 3)

    def test_test_signed_stack_never_enables_production_readiness(self):
        with tempfile.TemporaryDirectory() as td:
            marker, _, _ = self._fixture(td, mode="test")
            with mock.patch.object(native, "_is_windows", return_value=True):
                result = native.windows_native_stack_readiness(marker_path=marker)
        self.assertFalse(result["ready"])
        self.assertEqual(result["state"], "non_production_stack")

    def test_protocol_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            marker, _, _ = self._fixture(td, protocol=2)
            with mock.patch.object(native, "_is_windows", return_value=True):
                result = native.windows_native_stack_readiness(marker_path=marker)
        self.assertFalse(result["ready"])
        self.assertEqual(result["state"], "protocol_mismatch")

    def test_hash_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            marker, driver_path, service_path = self._fixture(td)
            with open(driver_path, "ab") as stream:
                stream.write(b"tamper")
            records = self._records(driver_path, service_path)
            with mock.patch.object(native, "_is_windows", return_value=True), \
                 mock.patch.object(native, "_service_registry_record", side_effect=lambda name: records.get(name)), \
                 mock.patch.object(native, "_service_running", return_value=True):
                result = native.windows_native_stack_readiness(marker_path=marker)
        self.assertFalse(result["ready"])
        self.assertEqual(result["state"], "hash_mismatch")

    def test_service_path_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            marker, driver_path, service_path = self._fixture(td)
            records = self._records(driver_path, service_path)
            records[native.ROUTING_SERVICE_NAME]["image_path"] = r"C:\foreign\service.exe"
            with mock.patch.object(native, "_is_windows", return_value=True), \
                 mock.patch.object(native, "_service_registry_record", side_effect=lambda name: records.get(name)), \
                 mock.patch.object(native, "_service_running", return_value=True):
                result = native.windows_native_stack_readiness(marker_path=marker)
        self.assertFalse(result["ready"])
        self.assertEqual(result["state"], "service_path_mismatch")

    def test_stopped_service_fails_closed(self):
        with tempfile.TemporaryDirectory() as td:
            marker, driver_path, service_path = self._fixture(td)
            records = self._records(driver_path, service_path)
            with mock.patch.object(native, "_is_windows", return_value=True), \
                 mock.patch.object(native, "_service_registry_record", side_effect=lambda name: records.get(name)), \
                 mock.patch.object(native, "_service_running", side_effect=lambda name: name == native.DRIVER_SERVICE_NAME):
                result = native.windows_native_stack_readiness(marker_path=marker)
        self.assertFalse(result["ready"])
        self.assertEqual(result["state"], "services_not_running")


    def test_production_packaging_sources_use_primitive_driver_store_lifecycle(self):
        root = os.path.dirname(os.path.dirname(__file__))
        inf = open(
            os.path.join(root, "native", "windows_routing", "ArvectumProxyRoutingCallout.inf.in"),
            encoding="utf-8",
        ).read()
        tool = open(
            os.path.join(root, "native", "windows_routing", "driver_package_tool.cpp"),
            encoding="utf-8",
        ).read()
        helper = open(
            os.path.join(root, "installer", "native_stack_helper.ps1"),
            encoding="utf-8",
        ).read()
        self.assertIn("DefaultDestDir=13", inf)
        self.assertIn("[DefaultInstall.NTamd64]", inf)
        self.assertIn("PnpLockdown=1", inf)
        self.assertIn("StartType=3", inf)
        self.assertNotIn("[DefaultUninstall", inf)
        self.assertIn("DiInstallDriverW", tool)
        self.assertIn("DiUninstallDriverW", tool)
        self.assertIn("Microsoft Windows Hardware Compatibility Publisher", helper)
        self.assertIn("depend= $dependency", helper)
        self.assertIn('$dependency = "BFE/$DriverService"', helper)
        self.assertIn("& $Tool $Operation $InfPath 1> $stdoutPath 2> $stderrPath", helper)
        self.assertNotIn("Start-Process -FilePath $Tool -ArgumentList @($Operation,$InfPath)", helper)
        self.assertNotIn("testsigning", helper.lower())

    def test_installer_embeds_complete_flat_native_bundle(self):
        root = os.path.dirname(os.path.dirname(__file__))
        iss = open(
            os.path.join(root, "installer", "ArvectumProxyLauncher.iss"),
            encoding="utf-8",
        ).read()
        builder = open(
            os.path.join(root, "tools", "build_windows_installer.ps1"),
            encoding="utf-8",
        ).read()
        for name in (
            "ArvectumProxyRoutingCallout.inf",
            "ArvectumProxyRoutingCallout.cat",
            "ArvectumProxyRoutingCallout.sys",
            "ArvectumProxyRoutingService.exe",
            "ArvectumDriverPackageTool.exe",
            "native-stack-bundle.json",
        ):
            self.assertIn(name, iss)
            self.assertIn(name, builder)
        self.assertIn("Test native stack requires -AllowTestNativeStack", builder)
        self.assertIn("NativePayloadRoot", iss)

if __name__ == "__main__":
    unittest.main()
