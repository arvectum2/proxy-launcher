from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WindowsMaintenanceFlowTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8-sig")

    def test_repair_is_cached_and_removed_with_the_install(self):
        iss = self.read("installer/ArvectumProxyLauncher.iss")
        self.assertIn('RepairExeName "Arvectum Proxy Launcher Repair.exe"', iss)
        self.assertIn("procedure CacheRepairInstaller", iss)
        self.assertIn("{srcexe}", iss)
        self.assertIn('Repair Arvectum Proxy Launcher', iss)
        self.assertIn('Type: files; Name: "{app}\\{#RepairExeName}"', iss)
        self.assertIn("SuppressibleMsgBox(ErrorText", iss)

    def test_install_target_avoids_controlled_folder_access_user_folders(self):
        iss = self.read("installer/ArvectumProxyLauncher.iss")
        filesystem = self.read("application_filesystem.py")
        portable = self.read("portable_lifecycle.py")

        self.assertIn('#define AppDir "{localappdata}\\Programs\\ArvectumProxyLauncher"', iss)
        self.assertIn("UsePreviousAppDir=no", iss)
        self.assertIn('#define LegacyAppDir "{userdocs}\\ArvectumProxyLauncher"', iss)
        self.assertNotIn('Name: "{autodesktop}\\Arvectum Proxy Launcher"', iss)
        self.assertIn('os.path.join(local, "Programs", "ArvectumProxyLauncher")', filesystem)
        self.assertIn("historical_documents_app_dir", filesystem)
        self.assertIn("historical_documents_app_exe", filesystem)
        self.assertIn("canonical LocalAppData Programs location", portable)

    def test_preflight_is_observational_before_any_runtime_handover(self):
        helper = self.read("installer/upgrade_helper.ps1")
        start = helper.index("Assert-PreflightRecoverySafe $previousExe")
        exit_point = helper.index("if ($PreflightOnly)", start)
        handover = helper.index("Invoke-PreviousRollback $previousExe", exit_point)
        stage = helper.index("incoming application staged and verified before runtime handover", exit_point)

        self.assertLess(start, exit_point)
        self.assertLess(exit_point, stage)
        self.assertLess(stage, handover)
        preflight_window = helper[start:exit_point]
        self.assertNotIn("Invoke-PreviousRollback", preflight_window)
        self.assertNotIn("Stop-Process", preflight_window)
        self.assertNotIn("Remove-ItemProperty", preflight_window)
        self.assertNotIn("Remove-StalePid", preflight_window)

    def test_installer_defers_handover_until_postinstall(self):
        iss = self.read("installer/ArvectumProxyLauncher.iss")
        app_file_line = next(
            line for line in iss.splitlines()
            if 'Source: "{#PayloadDir}\\Arvectum Proxy Launcher.exe"' in line
        )
        self.assertNotIn("AfterInstall", app_file_line)
        step = iss[iss.index("procedure CurStepChanged"):iss.index("function RunInstalledUninstallHelper")]
        self.assertIn("if CurStep = ssPostInstall", step)
        self.assertIn("CacheRepairInstaller();", step)
        self.assertIn("InstallVerifiedPayload();", step)
        self.assertLess(step.index("CacheRepairInstaller();"), step.index("InstallVerifiedPayload();"))

    def test_handover_restarts_previous_runtime_on_failure(self):
        helper = self.read("installer/upgrade_helper.ps1")
        self.assertIn("$previousRuntimeActive = @(Get-RecoveryBackups).Count -gt 0", helper)
        self.assertIn("Start-RuntimeAndVerify $targetExe 'new-version'", helper)
        self.assertIn("Stop-TargetRuntimeBestEffort $targetExe", helper)
        self.assertIn("Start-RuntimeAndVerify $previousExe 'previous-version recovery'", helper)
        self.assertIn("previous runtime restored after failed handover", helper)
        self.assertIn("transactional replacement rolled back", helper)

    def test_repair_does_not_execute_damaged_exe_when_no_recovery_is_pending(self):
        helper = self.read("installer/upgrade_helper.ps1")
        rollback = helper[helper.index("function Invoke-PreviousRollback"):helper.index("function Get-PreviousInstallRoot")]
        self.assertIn("$backups = @(Get-RecoveryBackups)", rollback)
        self.assertIn("if ($backups.Count -gt 0)", rollback)
        self.assertIn("Start-Process -FilePath $ExistingExe -ArgumentList '--stop' -Wait -PassThru", rollback)
        self.assertNotIn("& $ExistingExe --stop", rollback)
        self.assertIn("$rollback.ExitCode", rollback)
        self.assertIn("Stop-OwnedProcess $ExistingExe", rollback)

    def test_repair_fails_closed_if_backups_exist_without_recovery_executable(self):
        helper = self.read("installer/upgrade_helper.ps1")
        self.assertIn("recovery backups remain but the installed Launcher executable is missing", helper)
        self.assertIn("repair is blocked until network recovery can be proven", helper)

    def test_installer_runs_maintenance_preflight_before_install_phase(self):
        iss = self.read("installer/ArvectumProxyLauncher.iss")
        start = iss.index("function PrepareToInstall")
        end = iss.index("procedure InstallVerifiedPayload")
        prepare = iss[start:end]
        self.assertIn("RunEmbeddedHelper('upgrade_helper.ps1'", prepare)
        self.assertIn("-PreflightOnly", prepare)
        self.assertIn("Result := ErrorText", prepare)
        self.assertNotEqual("function PrepareToInstall(var NeedsRestart: Boolean): String;\nbegin\n  Result := '';\nend;", prepare.strip())

    def test_issue_171_has_dedicated_portable_transition_and_partial_install_regression(self):
        workflow = self.read(".github/workflows/windows-installer.yml")
        regression = self.read("qa/windows_installer_171_e2e.ps1")
        self.assertIn("./qa/windows_installer_171_e2e.ps1", workflow)
        self.assertIn("out\\windows-installer-171-e2e.json", workflow)
        self.assertIn("active_portable_to_installer", regression)
        self.assertIn("preflight_partial_install_prevention", regression)
        self.assertIn("final EXE SHA256 does not match build manifest", regression)
        self.assertIn("uninstall registration was committed before preflight completed", regression)
        self.assertIn("recovery evidence was unexpectedly deleted", regression)
        self.assertIn("PASS \\(read-only preflight REPAIR\\)", regression)

    def test_repair_cleans_only_operational_stale_state(self):
        helper = self.read("installer/upgrade_helper.ps1")
        self.assertIn("function Clear-StaleMaintenanceState", helper)
        self.assertIn("proxy_core.pid", helper)
        self.assertIn("stale owned recovery Run value removed", helper)
        self.assertIn("stale transactional artifact removed", helper)
        self.assertNotIn("Remove-Item -LiteralPath (Join-Path $StateRoot 'proxy_settings.json')", helper)
        self.assertNotIn("Remove-Item -LiteralPath (Join-Path $StateRoot 'no_proxy.txt')", helper)

    def test_uninstall_requires_proven_network_recovery(self):
        helper = self.read("installer/uninstall_helper.ps1")
        self.assertIn("Get-RecoveryBackups", helper)
        self.assertIn("Network rollback cannot be proven", helper)
        self.assertIn("recovery backups exist but the installed Launcher executable is missing", helper)
        self.assertIn("$rollback.ExitCode", helper)
        self.assertIn("recovery backups remain and uninstall stopped safely", helper)

    def test_uninstall_removes_only_owned_startup_state(self):
        helper = self.read("installer/uninstall_helper.ps1")
        self.assertIn("function Test-OwnedStartCommand", helper)
        self.assertIn("function Remove-OwnedRunValue", helper)
        self.assertIn("foreign or unknown Run value preserved", helper)
        self.assertIn("function Remove-OwnedLegacyTask", helper)
        self.assertIn("//t:Actions/t:Exec", helper)
        self.assertIn("foreign or unknown legacy scheduled task preserved", helper)
        self.assertNotIn("taskkill", helper.lower())

    def test_absent_legacy_task_is_captured_as_native_exit_code(self):
        helper = self.read("installer/uninstall_helper.ps1")
        self.assertIn("function Invoke-NativeCapture", helper)
        self.assertIn("RedirectStandardOutput", helper)
        self.assertIn("RedirectStandardError", helper)
        self.assertIn("legacy scheduled task absent; nothing to remove", helper)
        self.assertIn("$query.ExitCode -ne 0", helper)
        self.assertNotIn("/XML 2>$null", helper)

    def test_windows_ci_repairs_corruption_and_checks_config_preservation(self):
        workflow = self.read(".github/workflows/windows-installer.yml")
        e2e = self.read("qa/windows_rc_e2e.ps1")

        self.assertIn("./qa/windows_rc_e2e.ps1", workflow)
        self.assertIn("out\\windows-rc-e2e.json", workflow)
        self.assertIn("damaged-binary-for-apl-win-012-repair", e2e)
        self.assertIn("Arvectum Proxy Launcher Repair.exe", e2e)
        self.assertIn('"config_version":1', e2e)
        self.assertIn("Get-FileHash -LiteralPath $settings -Algorithm SHA256", e2e)
        self.assertIn("repair left stale PID file", e2e)
        self.assertIn("repair modified persistent proxy settings", e2e)
        self.assertIn("uninstall left owned main autostart value", e2e)
        self.assertIn("uninstall modified foreign recovery autostart value", e2e)
        self.assertIn("uninstall modified persistent no-proxy rules", e2e)

    def test_contract_document_is_present(self):
        contract = self.read("APL-WIN-009_WINDOWS_UNINSTALL_REPAIR.md")
        self.assertIn("Status: **implemented**", contract)
        self.assertIn("fail-closed", contract)
        self.assertIn("proxy_settings.json", contract)
        self.assertIn("no_proxy.txt", contract)
        self.assertIn("cached repair", contract.lower())


if __name__ == "__main__":
    unittest.main()
