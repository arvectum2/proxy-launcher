; APL-REL-006 / APL-WIN-009..012. Canonical Windows installer definition.
; PREPROCVER/Ver is the compiler's own encoded version identity. 0x06070100 = 6.7.1.0.
#if Ver != 0x06070100
  #error Exact Inno Setup 6.7.1 is required for the canonical Windows installer
#endif
#ifndef AppVersion
  #error AppVersion must be supplied by tools/build_windows_installer.ps1
#endif
#ifndef VersionInfoVersion
  #error VersionInfoVersion must be supplied by tools/build_windows_installer.ps1
#endif
#ifndef PayloadDir
  #error PayloadDir must be supplied by tools/build_windows_installer.ps1
#endif
#define AppName "Arvectum Proxy Launcher"
#define AppPublisher "ООО «Арвектум»"
#define AppPublisherURL "https://arvectum.com"
#define AppSupportURL "https://github.com/arvectum2/proxy-launcher/issues"
#define LegacyAppDir "{userdocs}\ArvectumProxyLauncher"
#ifdef SyntheticLifecycleFixture
  ; The synthetic predecessor intentionally models the pre-0.2.5 Documents install.
  #define AppDir LegacyAppDir
  #define SetupName "Arvectum-Proxy-Launcher-" + AppVersion + "-windows-x64-setup-synthetic-predecessor"
#else
  ; 0.2.5+: keep executable payload outside Controlled Folder Access user folders.
  #define AppDir "{localappdata}\Programs\ArvectumProxyLauncher"
  #define SetupName "Arvectum-Proxy-Launcher-" + AppVersion + "-windows-x64-setup"
#endif
#define RepairExeName "Arvectum Proxy Launcher Repair.exe"

[Setup]
AppId={{6A5A0706-4015-4EAF-BFA1-25EF435C9E1B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
AppSupportURL={#AppSupportURL}
DefaultDirName={#AppDir}
; Never reuse the pre-0.2.5 Documents path persisted by an older AppId install.
UsePreviousAppDir=no
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
OutputBaseFilename={#SetupName}
OutputDir=..\out\installer
SetupIconFile=..\assets\arvectum.ico
UninstallDisplayIcon={app}\Arvectum Proxy Launcher.exe
Uninstallable=yes
Compression=lzma2
SolidCompression=yes
CloseApplications=no
VersionInfoVersion={#VersionInfoVersion}
VersionInfoProductVersion={#VersionInfoVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription=Arvectum Proxy Launcher Windows Installer
VersionInfoProductName={#AppName}
VersionInfoCopyright=© 2026 ООО «Арвектум». All rights reserved.
VersionInfoOriginalFileName={#SetupName}.exe

[Files]
; All required files are compiled into the setup executable; no portable folder is consulted at install time.
; The application stays in {tmp} until the late transactional handover in ssPostInstall.
Source: "{#PayloadDir}\Arvectum Proxy Launcher.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "{#PayloadDir}\build_manifest.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\build_manifest.json"; Flags: dontcopy
Source: "{#PayloadDir}\upgrade_helper.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\uninstall_helper.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\upgrade_helper.ps1"; Flags: dontcopy
Source: "{#PayloadDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\THIRD_PARTY_NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\THIRD_PARTY_LICENSES\*"; DestDir: "{app}\THIRD_PARTY_LICENSES"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\INSTALL.txt"; DestDir: "{app}"; Flags: ignoreversion

[UninstallDelete]
Type: files; Name: "{app}\Arvectum Proxy Launcher.exe"
Type: files; Name: "{app}\Arvectum Proxy Launcher.exe.new"
Type: files; Name: "{app}\Arvectum Proxy Launcher.exe.old"
Type: files; Name: "{app}\{#RepairExeName}"
Type: files; Name: "{app}\.arvectum-install-owner"

[Icons]
Name: "{autoprograms}\Arvectum Proxy Launcher"; Filename: "{app}\Arvectum Proxy Launcher.exe"; WorkingDir: "{app}"
Name: "{autoprograms}\Repair Arvectum Proxy Launcher"; Filename: "{app}\{#RepairExeName}"; Parameters: "/SP-"; WorkingDir: "{app}"
; No desktop shortcut: Desktop may itself be protected by Controlled Folder Access.

[Code]
function RunEmbeddedHelper(const Helper, Arguments: String; var ErrorText: String): Boolean;
var
  PowerShell, HelperPath: String;
  ExitCode: Integer;
begin
  ExtractTemporaryFile(Helper);
  ExtractTemporaryFile('Arvectum Proxy Launcher.exe');
  ExtractTemporaryFile('build_manifest.json');
  HelperPath := ExpandConstant('{tmp}\' + Helper);
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  // Do not use PowerShell file-mode execution here. Under enforced App Control / UMCI,
  // Windows PowerShell 5.1 treats that mode as local-scope execution and rejects the
  // transition from a CLM host session into an exact-hash trusted FullLanguage script.
  // Passing the script path directly invokes the trusted script without dot-sourcing.
  Result := Exec(PowerShell, '-NoProfile -ExecutionPolicy Bypass "' + HelperPath + '" ' + Arguments,
    '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if (not Result) or (ExitCode <> 0) then begin
    ErrorText := 'InstallFailure: ' + Helper + ' failed with exit code ' + IntToStr(ExitCode);
    Result := False;
  end;
end;

function HelperArguments(const Extra: String): String;
begin
  Result := '-PayloadRoot "' + ExpandConstant('{tmp}') +
    '" -InstallRoot "' + ExpandConstant('{app}') +
    '" -LegacyInstallRoot "' + ExpandConstant('{#LegacyAppDir}') + '"';
  if Extra <> '' then
    Result := Result + ' ' + Extra;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var ErrorText: String;
begin
  // Contract: preflight is observational only. It may validate/log, but it must
  // not stop the current runtime, restore network state, or mutate install roots.
  Result := '';
  if not RunEmbeddedHelper('upgrade_helper.ps1', HelperArguments('-PreflightOnly'), ErrorText) then
    Result := ErrorText;
end;

procedure InstallVerifiedPayload();
var ErrorText: String;
begin
  if not RunEmbeddedHelper('upgrade_helper.ps1', HelperArguments(''), ErrorText) then
    RaiseException(ErrorText);
end;

procedure CacheRepairInstaller();
var
  SourcePath, TargetPath: String;
begin
  SourcePath := ExpandConstant('{srcexe}');
  TargetPath := ExpandConstant('{app}\{#RepairExeName}');
  if CompareText(SourcePath, TargetPath) <> 0 then begin
    if not CopyFile(SourcePath, TargetPath, False) then
      RaiseException('InstallFailure: could not cache the Windows repair installer.');
  end;
  if not FileExists(TargetPath) then
    RaiseException('InstallFailure: cached Windows repair installer is missing.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    // Finish ordinary Inno writes first. Only then perform the runtime/network
    // handover so an earlier Setup/CFA failure leaves the old runtime untouched.
    CacheRepairInstaller();
    SaveStringToFile(ExpandConstant('{app}\.arvectum-install-owner'), 'ARVECTUM_PROXY_LAUNCHER_INSTALL_OWNER' + #13#10, False);
    InstallVerifiedPayload();
  end;
end;

function RunInstalledUninstallHelper(var ErrorText: String): Boolean;
var
  PowerShell, HelperPath: String;
  ExitCode: Integer;
begin
  HelperPath := ExpandConstant('{app}\uninstall_helper.ps1');
  if not FileExists(HelperPath) then begin
    ErrorText := 'InstallFailure: installed uninstall helper is missing.';
    Result := False;
    exit;
  end;
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  // Same WDAC/CLM boundary rule as RunEmbeddedHelper: invoke the trusted script directly.
  Result := Exec(PowerShell, '-NoProfile -ExecutionPolicy Bypass "' + HelperPath + '" -InstallRoot "' + ExpandConstant('{app}') + '"', '', SW_HIDE, ewWaitUntilTerminated, ExitCode);
  if (not Result) or (ExitCode <> 0) then begin
    ErrorText := 'InstallFailure: installed uninstall helper failed with exit code ' + IntToStr(ExitCode);
    Result := False;
  end;
end;

function InitializeUninstall(): Boolean;
var ErrorText: String;
begin
  Result := RunInstalledUninstallHelper(ErrorText);
  if not Result then
    SuppressibleMsgBox(ErrorText, mbError, MB_OK, IDOK);
end;
