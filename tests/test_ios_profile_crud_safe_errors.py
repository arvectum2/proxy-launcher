"""Hermetic iOS profile CRUD error privacy and 64-language source contract."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "mobile/ios"
MODEL = (IOS / "App/AppViewModel.swift").read_text()
UX = (IOS / "App/ProfileMutationUX.swift").read_text()
RES = IOS / "Resources"


class ProfileCRUDPrivacyTests(unittest.TestCase):
    def test_save_failure_cannot_show_keychain_error(self):
        save = MODEL.split("func saveProfile(", 1)[1].split("func shareProxyLink(", 1)[0]
        self.assertIn("errorMessage = ProfileMutationUX.saveFailed", save)
        self.assertIn('AppL10n.tr("Проверьте адрес и порт прокси")', save)
        self.assertNotIn("error.localizedDescription", save)
        self.assertIn("try store.save(", save)
        self.assertIn("refresh()", save)

    def test_bulk_delete_is_partial_and_hides_first_error(self):
        delete = MODEL.split("func deleteProfiles(ids:", 1)[1].split("func deleteProfile(id:", 1)[0]
        self.assertIn("try store.delete(id: id)", delete)
        self.assertIn("removed.insert(id)", delete)
        self.assertIn("if firstError != nil", delete)
        self.assertIn("ProfileMutationUX.bulkDeleteFailed", delete)
        self.assertIn("return removed", delete)
        self.assertNotIn("localizedDescription", delete)
        self.assertIn("ProfileMutationUX.disconnectVPNBeforeDelete", delete)

    def test_single_delete_remains_vpn_guarded_and_safe(self):
        delete = MODEL.split("func deleteProfile(id:", 1)[1].split("func delete(_ profile:", 1)[0]
        self.assertIn("try store.delete(id: id); refresh()", delete)
        self.assertIn("ProfileMutationUX.disconnectVPNBeforeDelete", delete)
        self.assertIn("ProfileMutationUX.singleDeleteFailed", delete)
        self.assertNotIn("localizedDescription", delete)

    def test_64_translations_are_from_correct_tables(self):
        catalog = {
            "Localizable": "Не удалось сохранить профиль",
            "Localizable2": "Проверьте адрес и порт прокси",
            "ProfileManagement": "Не все профили удалены:",
            "ProfileManagement2": "Отключите VPN перед удалением профилей",
        }
        for kind, key in catalog.items():
            table = kind.rstrip("2")
            files = sorted(RES.glob(f"*.lproj/{table}.strings"))
            self.assertEqual(len(files), 64)
            for file in files:
                with self.subTest(locale=file.parent.name, key=key):
                    self.assertIn('"' + key + '" = ', file.read_text())

    def test_helper_never_echoes_native_errors(self):
        self.assertIn('AppL10n.tr("Не удалось сохранить профиль")', UX)
        self.assertIn('AppL10n.tr("Не все профили удалены:", table: "ProfileManagement")', UX)
        self.assertIn('AppL10n.tr("Отключите VPN перед удалением профилей", table: "ProfileManagement")', UX)
        self.assertIn('"Could not delete the proxy profile."', UX)
        self.assertIn('"Не удалось удалить профиль."', UX)
        self.assertNotIn("localizedDescription", UX)
        self.assertNotIn("Logger(", UX)
        self.assertNotIn("print(", UX)


if __name__ == "__main__":
    unittest.main()
