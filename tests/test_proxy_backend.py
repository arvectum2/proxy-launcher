import unittest

from proxy_backend import ProxyBackend, ProxyBackendConfig


class _FakeBackend(ProxyBackend):
    def __init__(self):
        self.enabled_config = None
        self.disabled = False
        self.synced_config = None
        self.pending = False

    @property
    def backend_id(self):
        return "fake"

    def enable(self, config):
        self.enabled_config = config
        return True

    def disable(self):
        self.disabled = True
        return True

    def is_enabled(self, config):
        return self.enabled_config == config and not self.disabled

    def restore_pending(self):
        return self.pending

    def sync_no_proxy(self, config):
        self.synced_config = config
        return True


class ProxyBackendContractTests(unittest.TestCase):
    def test_backend_interface_is_abstract(self):
        with self.assertRaises(TypeError):
            ProxyBackend()

    def test_incomplete_backend_cannot_be_instantiated(self):
        class IncompleteBackend(ProxyBackend):
            @property
            def backend_id(self):
                return "incomplete"

        with self.assertRaises(TypeError):
            IncompleteBackend()

    def test_config_is_immutable_and_contains_only_resolved_os_values(self):
        config = ProxyBackendConfig(
            pac_url="http://127.0.0.1:8082/proxy.pac",
            http_proxy_url="http://127.0.0.1:8080",
            no_proxy=("localhost", "127.0.0.1", "example.internal"),
        )
        self.assertEqual(config.pac_url, "http://127.0.0.1:8082/proxy.pac")
        self.assertEqual(config.http_proxy_url, "http://127.0.0.1:8080")
        self.assertEqual(config.no_proxy[-1], "example.internal")
        self.assertEqual(config.socks_proxy_url, "")
        with self.assertRaises(Exception):
            config.pac_url = "http://foreign.example/proxy.pac"

    def test_complete_backend_obeys_common_lifecycle_contract(self):
        config = ProxyBackendConfig(
            pac_url="http://127.0.0.1:8082/proxy.pac",
            http_proxy_url="http://127.0.0.1:8080",
            no_proxy=("localhost",),
        )
        backend = _FakeBackend()

        self.assertEqual(backend.backend_id, "fake")
        self.assertFalse(backend.is_enabled(config))
        self.assertFalse(backend.restore_pending())
        self.assertTrue(backend.enable(config))
        self.assertTrue(backend.is_enabled(config))
        self.assertTrue(backend.sync_no_proxy(config))
        self.assertIs(backend.synced_config, config)
        self.assertTrue(backend.disable())
        self.assertFalse(backend.is_enabled(config))

    def test_enabled_check_is_configuration_specific(self):
        first = ProxyBackendConfig(
            pac_url="http://127.0.0.1:8082/proxy.pac",
            http_proxy_url="http://127.0.0.1:8080",
        )
        second = ProxyBackendConfig(
            pac_url="http://127.0.0.1:9082/proxy.pac",
            http_proxy_url="http://127.0.0.1:9080",
        )
        backend = _FakeBackend()
        backend.enable(first)

        self.assertTrue(backend.is_enabled(first))
        self.assertFalse(backend.is_enabled(second))


if __name__ == "__main__":
    unittest.main()
