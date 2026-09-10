<#
.SYNOPSIS
    Prove that the exact APL-WIN-014 harness script is executing in FullLanguage
    after deployment of the dedicated exact-hash harness supplemental policy.
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$mode = [string]$ExecutionContext.SessionState.LanguageMode
if ($mode -ne 'FullLanguage') {
    throw "APL-WIN-014 harness is not trusted by App Control. Expected FullLanguage, got $mode. Close this shell, deploy the exact harness supplemental policy, then open a new elevated Windows PowerShell 5.1."
}

# This method is deliberately used as a positive FullLanguage capability probe. It is
# rejected in ConstrainedLanguage on the physical stand and therefore proves that the
# App Control script rule is actually taking effect for this exact trusted script.
$documents = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($documents)) { throw 'Unable to resolve the Documents folder in trusted FullLanguage mode.' }

Write-Host 'APL-WIN-014 harness App Control script trust: PASS'
Write-Host "PowerShell language mode: $mode"
Write-Host "Documents: $documents"
