import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class WindowsNativeStackInstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.iss = (ROOT / "installer" / "ArvectumProxyLauncher.iss").read_text(encoding="utf-8")
        cls.upgrade = (ROOT / "installer" / "upgrade_helper.ps1").read_text(encoding="utf-8")
        cls.uninstall = (ROOT / "installer" / "uninstall_helper.ps1").read_text(encoding="utf-8")
        cls.native = (ROOT / "installer" / "native_stack_helper.ps1").read_text(encoding="utf-8")
        cls.builder = (ROOT / "tools" / "build_windows_installer.ps1").read_text(encoding="utf-8")
        cls.bundle = (ROOT / "tools" / "build_windows_native_stack_bundle.ps1").read_text(encoding="utf-8")
        cls.submission = (ROOT / "tools" / "prepare_windows_driver_submission.ps1").read_text(encoding="utf-8")
        cls.inf = (ROOT / "native" / "windows_routing" / "ArvectumProxyRoutingCallout.inf.in").read_text(encoding="utf-8")
        cls.package_tool = (ROOT / "native" / "windows_routing" / "driver_package_tool.cpp").read_text(encoding="utf-8")

    def test_main_installer_remains_per_user_and_native_helper_self_elevates(self):
        self.assertIn("PrivilegesRequired=lowest", self.iss)
        self.assertIn("native_stack_helper.ps1", self.iss)
        self.assertIn("-Verb RunAs", self.native)
        self.assertNotIn("PrivilegesRequired=admin", self.iss)

    def test_inno_embeds_complete_driver_store_package(self):
        for name in (
            "ArvectumProxyRoutingCallout.inf",
            "ArvectumProxyRoutingCallout.cat",
            "ArvectumProxyRoutingCallout.sys",
            "ArvectumProxyRoutingService.exe",
            "ArvectumDriverPackageTool.exe",
            "native-stack-bundle.json",
        ):
            self.assertIn(name, self.iss)
        self.assertIn(r"{tmp}\native\ArvectumProxyRoutingCallout.inf", self.iss)
        self.assertIn("NativePayloadRoot", self.iss)

    def test_primitive_inf_contract_is_driver_store_managed(self):
        self.assertIn("[DefaultInstall.NTamd64]", self.inf)
        self.assertIn("[DefaultInstall.NTamd64.Services]", self.inf)
        self.assertIn("DefaultDestDir=13", self.inf)
        self.assertIn("PnpLockdown=1", self.inf)
        self.assertIn("StartType=3", self.inf)
        self.assertNotIn("[Manufacturer]", self.inf)
        self.assertNotIn("[DefaultUninstall", self.inf)

    def test_driver_package_tool_uses_supported_primitive_driver_apis(self):
        self.assertIn("DiInstallDriverW", self.package_tool)
        self.assertIn("DiUninstallDriverW", self.package_tool)
        self.assertIn("Newdev.lib", self.package_tool)
        self.assertNotIn("CreateService", self.package_tool)

    def test_native_helper_never_enables_test_mode_or_installs_test_certificates(self):
        lowered = self.native.lower()
        for forbidden in ("bcdedit", "testsigning", "import-certificate", "certutil -addstore"):
            self.assertNotIn(forbidden, lowered)
        self.assertIn("DriverStore\\FileRepository", self.native)
        self.assertIn("Invoke-PackageTool", self.native)
        self.assertIn("Refusing to modify foreign", self.native)

    def test_native_lifecycle_does_not_depend_on_process_environment_paths(self):
        for forbidden in ("$env:OS", "$env:ProgramFiles", "$env:ProgramData", "$env:SystemRoot", "$env:TEMP"):
            self.assertNotIn(forbidden, self.native)
        self.assertNotIn("$env:OS", self.bundle)
        self.assertIn("GetFolderPath", self.native)
        self.assertIn("EnvironmentVariableTarget", self.native)
        self.assertIn("OSVersion.Platform", self.native)
        self.assertIn("OSVersion.Platform", self.bundle)

    def test_routing_service_auto_starts_with_bfe_and_driver_dependency(self):
        self.assertIn('$dependency = "BFE/$DriverService"', self.native)
        self.assertIn("sc.exe create $RoutingService type= own start= auto depend= $dependency", self.native)
        self.assertNotIn("sc.exe create $DriverService", self.native)

    def test_upgrade_preflight_and_handover_order(self):
        preflight = self.upgrade.index("Assert-PreflightRecoverySafe $previousExe")
        native_preflight = self.upgrade.index("Invoke-NativeStackHelper $manifest 'Preflight'")
        rollback = self.upgrade.index("Invoke-PreviousRollback $previousExe")
        native_install = self.upgrade.index("Invoke-NativeStackHelper $manifest 'Install'")
        runtime_start = self.upgrade.index("Start-RuntimeAndVerify $targetExe 'new-version'")
        self.assertLess(preflight, native_preflight)
        self.assertLess(native_preflight, rollback)
        self.assertLess(rollback, native_install)
        self.assertLess(native_install, runtime_start)

    def test_uninstall_cannot_orphan_owned_native_stack(self):
        self.assertIn("native-stack.json", self.uninstall)
        self.assertIn("Invoke-NativeStackUninstall $InstallRoot", self.uninstall)
        self.assertIn("ownership marker exists but installed native_stack_helper.ps1 is missing", self.uninstall)
        self.assertLess(
            self.uninstall.index("Invoke-NativeStackUninstall $InstallRoot"),
            self.uninstall.index("Remove-OwnedRunValue $MainRunName $exe"),
        )

    def test_public_installer_rejects_test_bundle_by_default(self):
        self.assertIn("[switch]$AllowTestNativeStack", self.builder)
        self.assertIn("Test native stack requires -AllowTestNativeStack", self.builder)
        self.assertIn("native_stack_allow_test_bundle", self.builder)

    def test_production_bundle_requires_microsoft_catalog_and_signed_user_mode_helpers(self):
        self.assertIn("Microsoft Windows Hardware Compatibility Publisher", self.bundle)
        self.assertIn("ExpectedServicePublisher", self.bundle)
        self.assertIn("ArvectumDriverPackageTool.exe", self.bundle)

    def test_submission_stage_requires_inf2cat_and_disallows_attestation_release(self):
        self.assertIn("Inf2Cat.exe is required", self.submission)
        self.assertIn("10_25H2_X64", self.submission)
        self.assertIn("attestation_release_allowed = $false", self.submission)
        self.assertIn("microsoft-hardware-dashboard-whcp-hlk", self.submission)


if __name__ == "__main__":
    unittest.main()
