import pathlib
import tempfile
import unittest
from unittest import mock

import proxy_core as core


class RoutingPolicyExtractionTests(unittest.TestCase):
    def test_canonical_module_owns_public_policy_seams(self):
        for name in (
            "load_no_proxy",
            "save_no_proxy",
            "clean_domain",
            "_normalize_host",
            "host_bypasses_proxy",
            "build_pac",
        ):
            self.assertEqual(getattr(core, name).__module__, "routing_policy")

    def test_load_no_proxy_ignores_comments_and_blank_lines(self):
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "no_proxy.txt"
            path.write_text(
                "# comment\n\nExample.COM\n*.internal\n  10.*  \n",
                encoding="utf-8",
            )
            with mock.patch.object(core, "no_proxy_path", return_value=str(path)):
                self.assertEqual(
                    core.load_no_proxy(),
                    ["Example.COM", "*.internal", "10.*"],
                )

    def test_save_no_proxy_keeps_atomic_writer_and_normalizes_once(self):
        with mock.patch.object(core, "no_proxy_path", return_value="/tmp/no_proxy.txt"), \
             mock.patch.object(core, "_atomic_write_text") as writer, \
             mock.patch.object(core, "_log"):
            self.assertTrue(core.save_no_proxy([
                "https://Example.COM/path",
                "example.com:443",
                "*.LOCAL",
                "10.* # private",
            ]))

        writer.assert_called_once()
        payload = writer.call_args.args[1]
        self.assertEqual(payload.count("example.com\n"), 1)
        self.assertIn("*.local\n", payload)
        self.assertIn("10.*\n", payload)

    def test_clean_domain_preserves_sealed_ipv6_and_wildcard_contract(self):
        cases = {
            "https://Example.COM:443/path?q=1": "example.com",
            "example.com:8443": "example.com",
            "[2001:db8::1]:443/path": "2001:db8::1",
            "2001:db8::2": "2001:db8::2",
            "*.LOCAL": "*.local",
            "10.* # private": "10.*",
            "": "",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(core.clean_domain(raw), expected)

    def test_host_bypass_matching_is_boundary_safe_and_dynamic(self):
        with mock.patch.object(
            core,
            "load_no_proxy",
            return_value=["zakupki.gov.ru", ".corp.example", "10.*"],
        ):
            self.assertTrue(core.host_bypasses_proxy("zakupki.gov.ru"))
            self.assertTrue(core.host_bypasses_proxy("sub.zakupki.gov.ru."))
            self.assertFalse(core.host_bypasses_proxy("evilzakupki.gov.ru"))
            self.assertTrue(core.host_bypasses_proxy("corp.example"))
            self.assertTrue(core.host_bypasses_proxy("api.corp.example"))
            self.assertTrue(core.host_bypasses_proxy("10.2.3.4"))
            self.assertFalse(core.host_bypasses_proxy("11.2.3.4"))

        # Built-in loopback policy remains effective independently of the file.
        with mock.patch.object(core, "load_no_proxy", return_value=[]):
            self.assertTrue(core.host_bypasses_proxy("localhost"))
            self.assertTrue(core.host_bypasses_proxy("[::1]"))

    def test_critical_apple_connectivity_bypasses_survive_user_file_damage(self):
        with mock.patch.object(
            core,
            "load_no_proxy",
            return_value=["gsp1.apple.comapl-mac-008.invalid"],
        ):
            self.assertTrue(core.host_bypasses_proxy("gsp1.apple.com"))
            self.assertTrue(core.host_bypasses_proxy("captive.apple.com"))
            self.assertIn("gsp1.apple.com", core.DEFAULT_NO_PROXY)
            self.assertIn("captive.apple.com", core.DEFAULT_NO_PROXY)

    def test_bypass_evaluator_resolves_load_no_proxy_through_core_seam(self):
        with mock.patch.object(core, "load_no_proxy", return_value=["dynamic.invalid"]) as loader:
            self.assertTrue(core.host_bypasses_proxy("sub.dynamic.invalid"))
        loader.assert_called_once_with()

    def test_pac_generation_uses_current_policy_and_http_port(self):
        with mock.patch.object(
            core,
            "load_no_proxy",
            return_value=["example.invalid", "localhost"],
        ) as loader, mock.patch.object(
            core,
            "load_settings",
            return_value={"local_http_port": 8123},
        ) as settings:
            pac = core.build_pac()

        loader.assert_called_once_with()
        settings.assert_called_once_with()
        self.assertIn('"example.invalid",', pac)
        self.assertEqual(pac.count('"localhost",'), 1)
        self.assertIn("return 'PROXY 127.0.0.1:8123';", pac)
        self.assertIn("shExpMatch(host, d)", pac)
        self.assertIn("return 'DIRECT'", pac)


if __name__ == "__main__":
    unittest.main()
