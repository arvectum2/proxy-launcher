"""Focused source invariants for iOS 0.2 candidate; no device or network needed."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / 'mobile' / 'ios'


class IOS020ReleaseContract(unittest.TestCase):
    def test_version_and_ad_supported_primary_connection(self):
        spec = (IOS / 'project.yml').read_text(encoding="utf-8")
        home = (IOS / 'App' / 'ContentView.swift').read_text(encoding="utf-8")
        ads = (IOS / 'App' / 'SettingsBannerView.swift').read_text(encoding="utf-8")
        self.assertIn('MARKETING_VERSION: "0.2.0"', spec)
        self.assertIn('CURRENT_PROJECT_VERSION: "48"', spec)
        self.assertIn('SettingsBannerView()', home)
        self.assertIn('Task { await model.toggleVPN() }', home)
        self.assertIn('productionBannerUnitID = "R-M-20288304-1"', ads)
        self.assertIn('static let isEnabled = true', ads)
        self.assertNotIn('WidgetKit', home)

    def test_secrets_are_written_before_profiles_and_not_deleted_before_update(self):
        store = (IOS / 'Shared' / 'ProfileStore.swift').read_text(encoding="utf-8")
        save = store.split('func save(_ profile:', 1)[1].split('func delete(id:', 1)[0]
        self.assertLess(save.index('try setPassword(password, for: profile.id)'),
                        save.index('defaults.set(data, forKey: Key.profiles)'))
        secret = store.split('private func setPassword(', 1)[1].split('private func baseKeychainQuery', 1)[0]
        self.assertIn('SecItemUpdate(', secret)
        self.assertIn('errSecItemNotFound', secret)
        self.assertIn('throw ProfileStoreError.keychain(status)', secret)
        self.assertIn('profile_organization.v1', store)
        self.assertIn('profile_quality.v1', store)

    def test_bounded_scans_auto_candidates_and_cancel_on_stop(self):
        model = (IOS / 'App' / 'AppViewModel.swift').read_text(encoding="utf-8")
        tunnel = (IOS / 'PacketTunnel' / 'PacketTunnelProvider.swift').read_text(encoding="utf-8")
        policy = (IOS / 'SharedCore' / 'FailoverPolicy.swift').read_text(encoding="utf-8")
        importer = (IOS / 'App' / 'ProxyImportView.swift').read_text(encoding="utf-8")
        self.assertIn('automaticLimit = 3', (IOS / 'SharedCore' / 'ProfileScanPolicy.swift').read_text(encoding="utf-8"))
        self.assertIn('manualLimit = 10', (IOS / 'SharedCore' / 'ProfileScanPolicy.swift').read_text(encoding="utf-8"))
        self.assertIn('guard !isScanningProfiles else { return }', model)
        self.assertIn('scanAfterSave: false', importer)
        self.assertIn('maxConnectionCandidates = 6', policy)
        self.assertIn('shouldProbePrimary(', tunnel)
        self.assertIn('policy.connectionCandidates(', tunnel)
        self.assertIn('startTask?.cancel()', tunnel)
        self.assertIn('guard !stopping', tunnel)

    def test_safe_scoped_bulk_actions_and_import_preserves_active_choice(self):
        home = (IOS / 'App' / 'ContentView.swift').read_text(encoding='utf-8')
        model = (IOS / 'App' / 'AppViewModel.swift').read_text(encoding='utf-8')
        importer = (IOS / 'App' / 'ProxyImportView.swift').read_text(encoding='utf-8')
        tunnel = (IOS / 'PacketTunnel' / 'PacketTunnelProvider.swift').read_text(encoding='utf-8')
        self.assertIn('private var selectedVisibleIDs: Set<UUID>', home)
        self.assertIn('model.deleteProfiles(ids: selectedVisibleIDs)', home)
        self.assertIn('profileGroupMenu(ids: selectedVisibleIDs)', home)
        self.assertIn('model.setFavorites(selectedVisibleIDs, enabled: true)', home)
        self.assertIn(r'bulkSelectedIDs = Set(visibleProfiles.map(\.id))', home)
        self.assertIn('activateOnCreate: noExistingProfiles && added.isEmpty', importer)
        self.assertIn('rollbackImportedProfiles(ids: Set(added))', importer)
        self.assertIn('activateOnCreate: Bool = true', model)
        # Last-good is committed after the engine is applied, not after a probe.
        prepare_loop = tunnel.split('private func selectProxy()', 1)[1].split('private func prepare(', 1)[0]
        self.assertNotIn('store.lastAutoProfileID =', prepare_loop)
        self.assertIn('store?.lastAutoProfileID = prepared.storedProfile.id', tunnel)
        self.assertIn('cancelTunnelWithError(ProxyDiagnosticError(ProxyFailureReason.classify(error)))', tunnel)

    def test_persisted_tunnel_events_exclude_proxy_urls_and_arbitrary_errors(self):
        tunnel = (IOS / 'PacketTunnel' / 'PacketTunnelProvider.swift').read_text(encoding='utf-8')
        self.assertNotIn('detail: error.localizedDescription', tunnel)
        self.assertNotIn(r'failures.append("\(profile.name): \(error.localizedDescription)', tunnel)
        self.assertNotIn('prepared.storedProfile.host):', tunnel)
        self.assertIn('ProxyFailureReason.classify(error).code', tunnel)
        self.assertIn(r'detail: "\(prepared.resolvedProfile.type.label) · \(prepared.latencyMs) мс"', tunnel)

    def test_encrypted_backup_never_exports_plaintext_and_restores_additively(self):
        codec = (IOS / 'SharedCore' / 'ProfileBackup.swift').read_text(encoding='utf-8')
        restored = (IOS / 'SharedCore' / 'ProfileBackupRestorePlan.swift').read_text(encoding='utf-8')
        view = (IOS / 'App' / 'ProfileBackupView.swift').read_text(encoding='utf-8')
        model = (IOS / 'App' / 'AppViewModel.swift').read_text(encoding='utf-8')
        info = (IOS / 'Config' / 'App-Info.plist').read_text(encoding='utf-8')
        self.assertIn('AES.GCM.seal(', codec)
        self.assertIn('AES.GCM.open(', codec)
        self.assertIn('CCKeyDerivationPBKDF(', codec)
        self.assertIn('PBKDF2-HMAC-SHA256', codec)
        self.assertIn('envelope.iterations == iterations', codec)
        self.assertIn('FileWrapper(regularFileWithContents: encryptedData)', view)
        self.assertIn('allowedContentTypes: [.aplBackup, .json]', view)
        self.assertIn('UTExportedTypeDeclarations', info)
        self.assertIn('ru.arvectum.proxylauncher.aplbackup', info)
        self.assertIn('var seen = Set(existing.map(fingerprint))', restored)
        self.assertIn('guard !vpn.isConnectedOrConnecting', model)
        self.assertIn('store.save(entry.profile, password: entry.password, makeActive: false)', model)

    def test_specific_proxy_scan_is_opt_in_and_capped_at_ten(self):
        policy = (IOS / 'SharedCore' / 'ProfileScanPolicy.swift').read_text(encoding='utf-8')
        model = (IOS / 'App' / 'AppViewModel.swift').read_text(encoding='utf-8')
        ui = (IOS / 'App' / 'ContentView.swift').read_text(encoding='utf-8')
        self.assertIn('func selectedBatch(ids: [UUID], selected: Set<UUID>)', policy)
        self.assertIn('selected.count <= manualLimit', policy)
        self.assertIn('specificIDs: Set<UUID>? = nil', model)
        self.assertIn('if specificIDs == nil { manualScanCursor', model)
        self.assertIn('specificIDs: selectedVisibleIDs', ui)
        self.assertIn('selectedVisibleIDs.count > 10', ui)

    def test_old_localizations_stay_unchanged_new_copy_is_isolated(self):
        pattern = re.compile(r'^".*" = ".*";$', re.M)
        for language in ['ru', 'en']:
            old = (IOS / 'Resources' / f'{language}.lproj' / 'Localizable.strings').read_text(encoding="utf-8")
            extra = (IOS / 'Resources' / f'{language}.lproj' / 'ProfileManagement.strings').read_text(encoding="utf-8")
            self.assertEqual(len(pattern.findall(old)), 155)
            self.assertGreaterEqual(len(pattern.findall(extra)), 25)
        localizer = (IOS / 'App' / 'AppLocalization.swift').read_text(encoding="utf-8")
        self.assertIn('"ProfileManagement"', localizer)
        self.assertTrue((ROOT / 'docs' / 'APL_IOS_020_RELEASE_NOTES_2026-11-01.md').exists())


if __name__ == '__main__':
    unittest.main()
