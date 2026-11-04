"""Source safety invariants for split iOS 0.2 profile library."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'mobile/ios/App'
CORE = ROOT / 'mobile/ios/SharedCore'

class ProfilesRefactor(unittest.TestCase):
    def test_main_view_keeps_only_one_model_and_existing_sheets(self):
        main = (APP / 'ContentView.swift').read_text(encoding='utf-8')
        library = (APP / 'ProfilesScreenView.swift').read_text(encoding='utf-8')
        self.assertIn('ProfilesScreenView(', main)
        self.assertIn('onImport: { importRequest = ProxyImportRequest(source: "") }', main)
        self.assertIn('editorProfile: $editorProfile', main)
        self.assertIn('showProfileBackup: $showProfileBackup', main)
        self.assertIn('ProfileEditorView(profile: profile)', main)
        self.assertIn('ProxyImportView(initialSource: request.source)', main)
        self.assertIn('ProfileBackupView()', main)
        for fragment in ('ProfileStore()', 'VPNController()', 'SecItem', 'Keychain('):
            self.assertNotIn(fragment, library)
        self.assertIn('@ObservedObject var model: AppViewModel', library)
        self.assertLess(len(main.splitlines()), 900)

    def test_policy_filters_without_secret_access(self):
        policy = (CORE / 'ProfileLibrarySelectionPolicy.swift').read_text(encoding='utf-8')
        for fragment in ('localizedCaseInsensitiveContains(search)',
                         'switch groupFilter', 'case "favorites":',
                         'group(for: profile.id)', 'leftFavorite != rightFavorite',
                         'selection.intersection(Set(profiles.map(\\.id)))'):
            self.assertIn(fragment, policy)
        self.assertNotIn('ProfileStore(', policy)
        self.assertNotIn('password', policy.lower())
        tests=(ROOT/'mobile/ios/Tests/CoreTests/ProfileLibrarySelectionPolicyTests.swift').read_text(encoding='utf-8')
        for fragment in ('testFavoritesFirstWithoutChangingStorageOrder',
                         'testSearchMatchesCaseInsensitiveNameOrHost',
                         'testFavoritesGroupAndCombinedSearch',
                         'testSelectionNeverIncludesFilteredOrDeletedProfiles'):
            self.assertIn(fragment, tests)

    def test_visible_selection_and_fail_safe_delete_guards(self):
        library = (APP / 'ProfilesScreenView.swift').read_text(encoding='utf-8')
        bulk = (APP / 'ProfileLibraryBulkActionsView.swift').read_text(encoding='utf-8')
        self.assertIn('ProfileLibrarySelectionPolicy.selectedVisibleIDs(bulkSelectedIDs, from: visibleProfiles)', library)
        self.assertIn('model.deleteProfiles(ids: selectedVisibleIDs)', library)
        self.assertIn('guard !model.vpn.isConnectedOrConnecting else { return }', library)
        self.assertIn('.onChange(of: profileSearch)', library)
        self.assertIn('.onChange(of: profileGroupFilter)', library)
        self.assertIn('bulkSelectedIDs.formIntersection(Set(liveIDs))', library)
        self.assertIn('selectedVisibleIDs.count > 10', bulk)
        self.assertIn('.disabled(selectedVisibleIDs.isEmpty || model.vpn.isConnectedOrConnecting)',bulk)
        self.assertIn('specificIDs: selectedVisibleIDs', bulk)

    def test_accessibility_rows_groups_favorites_filter(self):
        row = (APP/'ProfileLibraryRowView.swift').read_text(encoding='utf-8')
        filters=(APP/'ProfileLibraryFiltersView.swift').read_text(encoding='utf-8')
        library=(APP/'ProfilesScreenView.swift').read_text(encoding='utf-8')
        for id_ in ('profiles.row.', 'profiles.favorite.', 'Группа профиля'):
            self.assertIn(id_, row)
        for id_ in ('profiles.search', 'profiles.groupFilter', 'profiles.bulk.toggle'):
            self.assertIn(id_, filters)
        self.assertIn('.environment(\\.layoutDirection, .leftToRight)', row)
        self.assertIn('.frame(minWidth: 44, minHeight: 44)', row)
        self.assertIn('.keyboardDismissOnSwipeUp()', library)
        self.assertIn('ProfileLibraryGroupMenu(model: model, ids: selectedVisibleIDs', (APP/'ProfileLibraryBulkActionsView.swift').read_text(encoding='utf-8'))

    def test_large_text_profile_actions_are_full_width_not_clipped(self):
        library=(APP/'ProfilesScreenView.swift').read_text(encoding='utf-8')
        filters=(APP/'ProfileLibraryFiltersView.swift').read_text(encoding='utf-8')
        bulk=(APP/'ProfileLibraryBulkActionsView.swift').read_text(encoding='utf-8')
        self.assertIn('if dynamicTypeSize.isAccessibilitySize {',library)
        self.assertIn('VStack(spacing: 8) { profileActionLabels }',library)
        self.assertIn('HStack(spacing: 8) { profileActionLabels }',library)
        self.assertIn('selectModeButton.frame(maxWidth: .infinity, alignment: .trailing)',filters)
        self.assertIn('if dynamicTypeSize.isAccessibilitySize {',bulk)
        self.assertIn('VStack(alignment: .leading, spacing: 9)',bulk)

    def test_no_localization_or_release_metadata_rewrites(self):
        project=(ROOT/'mobile/ios/project.yml').read_text(encoding='utf-8')
        self.assertIn('MARKETING_VERSION: "0.2.0"', project)
        self.assertIn('CURRENT_PROJECT_VERSION: "48"',project)
        self.assertIn('YandexMobileAds',project)
        for module in ('ProfilesScreenView.swift','ProfileLibraryFiltersView.swift','ProfileLibraryRowView.swift','ProfileLibraryBulkActionsView.swift'):
            self.assertIn('AppL10n.tr(', (APP/module).read_text(encoding='utf-8'))

if __name__=='__main__':
    unittest.main()
