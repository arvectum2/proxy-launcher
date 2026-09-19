import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
GUI = (ROOT / "proxy_gui.py").read_text(encoding="utf-8")


class MacOSVisualContractTests(unittest.TestCase):
    def test_macos_keeps_native_aqua_theme(self):
        self.assertIn('style.theme_use("aqua")', GUI)
        self.assertIn('root.configure(bg="systemWindowBackgroundColor")', GUI)
        self.assertIn('style="Mac.TCheckbutton"', GUI)

    def test_macos_main_layout_is_separate_from_classic_layout(self):
        self.assertIn("def _build_macos_main(self):", GUI)
        self.assertIn("def _build_classic_main(self):", GUI)
        self.assertIn('style="MacStatus.TLabel"', GUI)
        self.assertIn('style="MacPorts.TLabel"', GUI)

    def test_secondary_windows_use_semantic_macos_colors(self):
        self.assertIn('"systemControlBackgroundColor" if _is_macos()', GUI)
        self.assertIn('"systemSelectedContentBackgroundColor" if _is_macos()', GUI)
        self.assertIn("def _button_style(", GUI)

    def test_doctor_pass_does_not_claim_external_connectivity(self):
        self.assertIn("Диагностика: локальных проблем не обнаружено.", GUI)
        self.assertIn("Доступность внешнего proxy и целевого сайта здесь не проверяется.", GUI)
        self.assertIn("Для end-to-end проверки используйте «Проверка соединения».", GUI)


if __name__ == "__main__":
    unittest.main()
