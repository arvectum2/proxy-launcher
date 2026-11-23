"""Guard the strict, ownership-scoped product VPN re-read sequence."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
CTRL=(ROOT/"mobile/ios/App/VPNController.swift").read_text()
CORE=(ROOT/"mobile/ios/SharedCore/NativeCredentialReceiver.swift").read_text()

def product():
    return CTRL.split("private func connectProduct(",1)[1].split("private func connectWithLease(",1)[0]

def test_initial_invalid_can_only_be_read_back_when_owned():
    section=product()
    assert "let initial=try splitProductManagers(all,owner:store.nativeProductOwner())" in section
    assert "let ownedIndex=initial.product.flatMap" in section
    assert "all.firstIndex(where:{$0 === candidate})" in section
    assert "onDemandOff(all)" in section
    assert "NativeProductManagerPreflight.permitsReadback(all.map(status),ownedProductIndex:ownedIndex)" in section
    assert section.index("permitsReadback(") < section.index("try await reload(target)")
    assert "case .invalid:return .invalid" in section

def test_ticket_launch_requires_fresh_disconnected_manager_census():
    section=product()
    assert "NativeProductManagerPreflight.permitsLaunch(items.map(status))" in section
    assert section.index("let refreshed=try await loadAllManagers") < section.index("allOff(refreshed)")
    assert section.index("allOff(refreshed)") < section.index("store.issueNativeProductLaunch")
    assert "ownsProductManager(target,owner:owner)" in section
    assert "ownsProductManager(readback,owner:owner)" in section
    assert "removeFromPreferences" not in section
    assert "startTunnel(options:launch.options)" in section

def test_model_blocks_stale_or_active_before_launch():
    assert "case .invalid:" in CORE
    assert "guard ownedProductIndex == index else { return false }" in CORE
    assert "case .activeOrUnknown: return false" in CORE
    assert "statuses.allSatisfy { $0 == .disconnected }" in CORE


def test_product_launch_receipt_distinguishes_failure_phase_without_secrets():
    section=product()
    assert "var phase = NativeProductStartPhase.managerCensus" in section
    for phase in ("managerReconcile","managerReadback","credentialTicket","osSubmission"):
        assert "phase = ."+phase in section
    assert "TelemetryStore().append(TunnelEvent(type:\"native start blocked\"" in section
    assert "detail:phase.rawValue" in section
    assert "throw error" in section
    assert "NativeProductStartSubmission.attempt" in section
    assert "try session.startTunnel(options:launch.options)" in section
    assert "try store.revokeNativeProductLaunch(launch)" in section
    assert "TelemetryStore().append(TunnelEvent(type:\"native start submitted\"" in section
    assert "error.localizedDescription" not in section


def test_disabled_owned_product_manager_is_not_reclassified_as_legacy():
    identity=CTRL.split("private func productManagerMatchesOwner",1)[1].split("private func splitProductManagers",1)[0]
    assert "proto.providerBundleIdentifier==AppShared.providerBundleIdentifier" in identity
    assert "NativeProductStartRequest.ownsConfiguration(proto.providerConfiguration,owner:owner)" in identity
    assert "!item.isOnDemandEnabled" in identity
    assert "proto.identityReference==nil" in identity
    assert "private func ownsProductManager" in identity
    assert "productManagerMatchesOwner(item,owner:owner) && item.isEnabled" in identity
    split=CTRL.split("private func splitProductManagers",1)[1].split("private func isDormantProductManager",1)[0]
    assert "productManagerMatchesOwner(item,owner:owner)" in split
    assert "try requireLegacyManager(item)" in split


def test_one_owner_scoped_inactive_reenable_and_strict_readback():
    section=product()
    assert "if let prior=initial.product" in section
    assert section.index("try await reload(target)") < section.index("if !target.isEnabled")
    assert "NativeProductManagerPreflight.permitsOwnedReenable(" in section
    assert "ownerMatches:productManagerMatchesOwner(target,owner:owner)" in section
    assert "onDemandOff:!target.isOnDemandEnabled && (target.onDemandRules ?? []).isEmpty" in section
    assert "target.isEnabled=true" in section
    assert section.index("target.isEnabled=true") < section.index("try await save(target)")
    assert section.index("try await save(target)") < section.index("let refreshed=try await loadAllManagers")
    assert section.index("let refreshed=try await loadAllManagers") < section.index("allOff(refreshed)")
    assert section.index("allOff(refreshed)") < section.index("store.issueNativeProductLaunch")
    assert "removeFromPreferences" not in section
