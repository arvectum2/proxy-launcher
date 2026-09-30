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
        cls.preview = (ROOT / "installer" / "windows_preview_mode_helper.ps1").read_text(encoding="utf-8")
        cls.builder = (ROOT / "tools" / "build_windows_installer.ps1").read_text(encoding="utf-8")
        cls.preview_builder = (ROOT / "tools" / "build_windows_app_exclusions_preview.ps1").read_text(encoding="utf-8")
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
        self.assertNotIn("$env:OS", self.builder)
        self.assertIn("OSVersion.Platform", self.builder)
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

    def test_preview_installer_is_explicit_and_separate_from_public_setup(self):
        self.assertIn("[switch]$WindowsAppExclusionsPreview", self.builder)
        self.assertIn("WindowsAppExclusionsPreview requires -NativeStackBundle.", self.builder)
        self.assertIn(
            "WindowsAppExclusionsPreview requires an explicitly allowed test native stack.",
            self.builder,
        )
        self.assertIn("windows_app_exclusions_preview", self.builder)
        self.assertIn("windows_preview_mode_helper_sha256", self.builder)
        self.assertIn("windows_preview_mode_helper.ps1", self.builder)
        self.assertIn("/DWindowsAppExclusionsPreview=1", self.builder)
        self.assertIn("elseif ($WindowsAppExclusionsPreview)", self.builder)
        self.assertIn("'-preview'", self.builder)
        self.assertIn("#ifdef WindowsAppExclusionsPreview", self.iss)
        self.assertIn("windows-x64-setup-preview", self.iss)
        self.assertIn("windows_preview_mode_helper.ps1", self.iss)

    def test_preview_mode_is_isolated_from_production_native_helper(self):
        self.assertNotIn("testsigning", self.native.lower())
        self.assertIn("bcdedit.exe", self.preview.lower())
        self.assertIn("Import-Certificate", self.preview)
        self.assertIn("windows-preview-mode.json", self.preview)
        self.assertIn("root_certificate_owned", self.preview)
        self.assertIn("testsigning_owned", self.preview)

    def test_preview_mode_resolves_system_root_when_machine_environment_is_empty(self):
        self.assertIn("GetEnvironmentVariable('SystemRoot', [EnvironmentVariableTarget]::Machine)", self.preview)
        self.assertIn("GetEnvironmentVariable('SystemRoot')", self.preview)
        self.assertIn("[Environment]::SystemDirectory", self.preview)
        self.assertIn("GetEnvironmentVariable('ProgramData')", self.preview)
        self.assertIn("GetEnvironmentVariable('ALLUSERSPROFILE')", self.preview)

    def test_uninstall_cleans_preview_mode_after_native_stack(self):
        native_index = self.uninstall.index("Invoke-NativeStackUninstall $InstallRoot")
        preview_index = self.uninstall.index("Invoke-WindowsPreviewCleanup $InstallRoot")
        self.assertLess(native_index, preview_index)
        self.assertIn("windows_preview_mode_helper_sha256", self.uninstall)
        self.assertIn("& $powershell @arguments", self.uninstall)
        self.assertIn("& $powershell @arguments", self.upgrade)

    def test_preview_release_builder_keeps_private_key_local_and_binds_foundation_commit(self):
        self.assertIn("KeyExportPolicy NonExportable", self.preview_builder)
        self.assertIn("driver-submission-manifest.json", self.preview_builder)
        self.assertIn("foundationManifest.source_commit", self.preview_builder)
        self.assertIn("WindowsAppExclusionsPreview = $true", self.preview_builder)
        self.assertIn("AllowTestNativeStack = $true", self.preview_builder)
        self.assertIn("setup-preview.exe", self.preview_builder)
        self.assertIn("app-exclusions-preview.zip", self.preview_builder)
        self.assertIn("production_certified = $false", self.preview_builder)
        self.assertIn("requires_windows_testsigning = $true", self.preview_builder)
        self.assertIn("Cert:\\CurrentUser\\My\\{0}", self.preview_builder)
        self.assertNotIn("Export-PfxCertificate", self.preview_builder)

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
