"""Guard against SwiftUI localizing a network port as a grouped number."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProxyPreviewFormat(unittest.TestCase):
    def test_proxy_endpoint_is_rendered_verbatim(self):
        source = (ROOT / "mobile/ios/App/ProxyImportView.swift").read_text(encoding="utf-8")
        self.assertIn('Text(verbatim: "\\(item.type.rawValue) · \\(item.host):\\(item.port)")', source)
        self.assertNotIn('Text("\\(item.type.rawValue) · \\(item.host):\\(item.port)")', source)


if __name__ == "__main__":
    unittest.main()
