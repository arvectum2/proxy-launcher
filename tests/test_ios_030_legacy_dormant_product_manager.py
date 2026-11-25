"""Legacy VPN must remain usable beside a clearly marked *inactive* native manager."""
from pathlib import Path

IOS = Path(__file__).resolve().parents[1] / "mobile/ios"
SOURCE = (IOS / "App/VPNController.swift").read_text()

def section(start, end):
    return SOURCE.split(start, 1)[1].split(end, 1)[0]

def test_idle_native_product_recognition_requires_three_identity_markers_and_offline():
    block=section("private func isDormantProductManager", "private func legacyManagersExcludingDormantProduct")
    assert "proto.providerBundleIdentifier==AppShared.providerBundleIdentifier" in block
    assert "item.localizedDescription==Self.productConfigurationName" in block
    assert "proto.serverAddress==Self.productConfigurationName" in block
    assert "(item.connection.status == .disconnected || item.connection.status == .invalid)" in block
    assert "!item.isOnDemandEnabled" in block and "(item.onDemandRules ?? []).isEmpty" in block
    assert "proto.username==nil" in block and "proto.passwordReference==nil" in block
    assert "proto.identityReference==nil" in block and "proto.proxySettings==nil" in block
    assert "!proto.includeAllNetworks && !proto.enforceRoutes" in block

def test_legacy_skips_only_one_inert_marker_never_adopts_or_modifies_it():
    block=section("private func legacyManagersExcludingDormantProduct", "private func prepareProductManager")
    assert "for item in all.filter(isArvectumManager)" in block
    assert "if isDormantProductManager(item)" in block
    assert "guard dormantCount==1 else{throw NativeCredentialReceiver.Failure.invalidIdentity}" in block
    assert "continue // Never reload, save, start or remove the native manager." in block
    assert "try requireLegacyManager(item)" in block
    assert "legacy.append(item)" in block

def test_no_native_selection_uses_safe_legacy_census_and_active_product_still_blocks():
    prepare=section("private func prepareProductManager", "private func connectProduct")
    assert prepare.index("if try store.nativeProductSelection() == nil") < prepare.index("splitProductManagers")
    assert "_=try legacyManagersExcludingDormantProduct(all)" in prepare
    assert "let split=try splitProductManagers(all,owner:store.nativeProductOwner())" in prepare
    legacy=section("private func loadOrCreateManager", "private func loadAllManagers")
    assert "let matching=try legacyManagersExcludingDormantProduct(managers)" in legacy
    assert "matching.first(where: { $0.isEnabled }) ?? matching.first ?? NETunnelProviderManager()" in legacy
    assert "try requireLegacyManager(manager)" in legacy
    assert "try await save(manager)" in legacy
    strict=section("private func splitProductManagers", "private func isDormantProductManager")
    assert "productManagerMatchesOwner(item,owner:owner)" in strict
    assert "guard product==nil else{throw NativeCredentialReceiver.Failure.invalidIdentity}" in strict
    assert "try requireLegacyManager(item)" in strict

def test_native_product_start_remains_strict_and_no_cross_manager_repair():
    product=section("private func connectProduct", "private func connectWithLease")
    assert "let initial=try splitProductManagers(all,owner:store.nativeProductOwner())" in product
    assert "let exact=try splitProductManagers(refreshed,owner:owner)" in product
    assert "ownsProductManager(readback,owner:owner)" in product
    assert "store.issueNativeProductLaunch(selection,owner:owner)" in product
    assert "legacyManagersExcludingDormantProduct" not in product
    block=section("private func legacyManagersExcludingDormantProduct", "private func prepareProductManager")
    ordinary, marker, qa = block.partition("#if APL_PRODUCT_OWNER_QA")
    assert marker and qa.rstrip().endswith("#endif")
    assert "removeFromPreferences" not in ordinary
    assert "owned.allSatisfy({productManagerMatchesOwner($0,owner:owner)})" in qa
    assert "for item in owned {try await item.removeFromPreferences()}" in qa
    assert qa.count("removeFromPreferences")==1
    assert "APL_PRODUCT_OWNER_QA" not in (IOS/"project.yml").read_text()
