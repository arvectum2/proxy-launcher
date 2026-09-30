# Windows kernel driver production distribution

Status: engineering foundation implemented; public production signing is externally blocked until Arvectum completes Microsoft Hardware Developer Program onboarding and receives a Microsoft-signed driver package.

## Canonical production path

For current Windows 10/11 x64 systems, a new kernel-mode driver must be signed through Microsoft Hardware Dev Center. Arvectum's release gate therefore treats a Microsoft Hardware Compatibility Publisher signature on the driver package catalog as mandatory.

Microsoft's current Hardware Dev Center guidance requires an Extended Validation (EV) code-signing certificate associated with the Hardware Developer Program account. The preferred production route is Windows Hardware Lab Kit (HLK) testing plus Windows Hardware Compatibility Program (WHCP) dashboard signing.

Attestation signing is not the Arvectum public-production route. Microsoft currently describes attestation signing as a testing scenario and it does not provide Windows Certified status or normal retail Windows Update distribution.

## External account and HLK prerequisites

Hardware Developer Program onboarding currently requires:
- an EV code-signing certificate;
- a Microsoft Entra ID organization account with a Global Administrator;
- an authorized legal contact who can accept the Hardware Program agreements;
- uploading the EV certificate to Partner Center and completing Microsoft's organization questionnaire/approval flow.

For Windows 10/11 WHCP submissions, Partner Center expects an HLK result package. The HLK environment must be a dedicated test environment. Microsoft explicitly does not support the HLK test system inside Virtual PC or a third-party hypervisor, so ARVECTUM-WFP-DEV/VirtualBox is development and test-mode evidence only, not WHCP certification evidence.

The physical HLK test system must use the English-language/English-locale Windows image for the target OS and have at least 300 GB of disk capacity for test files and logs. The current Windows-dev host is not suitable as-is: it reports system locale ru-RU and a 237.5 GB C: disk. ARVECTUM-DEMO remains out of scope and must stay clean. Production certification therefore requires either rebuilding Windows-dev with an English Windows image plus >=300 GB storage or provisioning a separate physical Windows HLK client.

Primary Microsoft references:
- https://learn.microsoft.com/windows-hardware/drivers/dashboard/hardware-program-register
- https://learn.microsoft.com/windows-hardware/drivers/dashboard/code-signing-reqs
- https://learn.microsoft.com/windows-hardware/drivers/dashboard/driver-signing-offerings
- https://learn.microsoft.com/windows-hardware/drivers/dashboard/hardware-submission-create
- https://learn.microsoft.com/windows-hardware/test/hlk/getstarted/windows-hlk-prerequisites
- https://learn.microsoft.com/windows-hardware/drivers/dashboard
- https://learn.microsoft.com/windows-hardware/drivers/install/kernel-mode-code-signing-requirements--windows-vista-and-later-
- https://learn.microsoft.com/windows-hardware/drivers/develop/creating-a-primitive-driver

## Arvectum package model

The WFP callout is distributed as a primitive driver package:
- ArvectumProxyRoutingCallout.inf
- ArvectumProxyRoutingCallout.cat
- ArvectumProxyRoutingCallout.sys

The INF is architecture-decorated, uses DIRID 13, is PnpLockdown-enabled, and registers the kernel service as demand-start. Installation/uninstallation is performed with DiInstallDriverW/DiUninstallDriverW through ArvectumDriverPackageTool.exe. The privileged ArvectumProxyRouting service is auto-start and depends on both BFE and ArvectumProxyRoutingCallout.

The native installer bundle is flat and also contains:
- ArvectumProxyRoutingService.exe
- ArvectumDriverPackageTool.exe
- native-stack-bundle.json

Production bundle creation fails closed unless:
1. the CAT Authenticode signature is valid and the signer subject identifies Microsoft Windows Hardware Compatibility Publisher;
2. routing service and package tool Authenticode signatures are valid and match the expected Arvectum publisher;
3. all hashes and protocol/service identities match the bundle manifest.

The production helper never enables Windows test-signing and never imports a test certificate.

## Build/submission flow

1. Build the x64 WFP callout and PDB with the pinned WDK.
2. Run tools/prepare_windows_driver_submission.ps1 to materialize the INF and submission manifest.
3. Run InfVerif/HLK tests on the resulting package.
4. Create and sign the HLK submission package with the EV identity associated with the Hardware Developer Program account.
5. Submit through Microsoft Hardware Dev Center / Partner Center.
6. Download the Microsoft-signed driver package.
7. Sign ArvectumProxyRoutingService.exe and ArvectumDriverPackageTool.exe with the canonical Arvectum Windows code-signing identity.
8. Run tools/build_windows_native_stack_bundle.ps1 -SigningMode Production with the Microsoft-signed driver package.
9. Build/sign the final Inno Setup installer with that exact native bundle.
10. Run production install/upgrade/repair/uninstall acceptance on clean Windows 11 with Secure Boot and normal code-integrity policy.

## Release gate

application_exclusion_capability("win32") may report live_enforcement_supported=true only when windows_native_stack_readiness() verifies an installed marker with signing_mode=production, exact hashes, Driver Store driver path, service identities/start modes, and running services.

Until a genuine Microsoft-signed production package exists, public releases must remain fail-closed for per-application Windows enforcement.
