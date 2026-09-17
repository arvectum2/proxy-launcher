# -*- coding: utf-8 -*-

import unittest

import backend_runtime
from capability_model import (
    CapabilityState,
    Feature,
    UnsupportedFeatureError,
    capabilities_for_backend,
    declared_backend_ids,
    require_feature,
    unsupported_feature_view,
)


class CapabilityModelTests(unittest.TestCase):
    def test_all_governed_backends_are_declared(self):
        self.assertEqual(declared_backend_ids(), ("linux", "macos", "windows"))

    def test_runtime_platform_selection_and_capability_selection_match(self):
        cases = {
            "win32": ("windows", "Windows"),
            "darwin": ("macos", "macOS"),
            "linux": ("linux", "Linux"),
            "linux2": ("linux", "Linux"),
        }
        for platform, expected in cases.items():
            with self.subTest(platform=platform):
                capabilities = backend_runtime.capabilities_for_platform(platform)
                self.assertEqual((capabilities.backend_id, capabilities.platform_label), expected)

    def test_common_backend_safety_features_are_supported_everywhere(self):
        for backend_id in declared_backend_ids():
            capabilities = capabilities_for_backend(backend_id)
            for feature in (Feature.SYSTEM_PROXY, Feature.BYPASS_RULES, Feature.SAFE_ROLLBACK):
                with self.subTest(backend=backend_id, feature=feature.value):
                    self.assertTrue(capabilities.supports(feature))
                    self.assertEqual(capabilities.get(feature).state, CapabilityState.SUPPORTED)

    def test_autostart_is_explicitly_platform_specific(self):
        self.assertTrue(capabilities_for_backend("windows").supports(Feature.AUTOSTART))
        self.assertFalse(capabilities_for_backend("macos").supports(Feature.AUTOSTART))
        self.assertTrue(capabilities_for_backend("linux").supports(Feature.AUTOSTART))

    def test_application_routing_is_planned_not_accidentally_enabled(self):
        for backend_id in declared_backend_ids():
            capability = capabilities_for_backend(backend_id).get(Feature.APPLICATION_ROUTING)
            self.assertEqual(capability.state, CapabilityState.PLANNED)
            self.assertFalse(capability.supported)

    def test_unsupported_feature_ux_is_visible_explained_and_disabled(self):
        view = unsupported_feature_view("macos", Feature.AUTOSTART)
        self.assertTrue(view["visible"])
        self.assertFalse(view["enabled"])
        self.assertEqual(view["badge"], "Недоступно")
        self.assertIn("macOS", view["message"])

    def test_planned_feature_ux_is_visible_explained_and_disabled(self):
        view = unsupported_feature_view("windows", Feature.APPLICATION_ROUTING)
        self.assertTrue(view["visible"])
        self.assertFalse(view["enabled"])
        self.assertEqual(view["badge"], "Запланировано")
        self.assertEqual(view["state"], "planned")

    def test_supported_feature_ux_is_enabled(self):
        view = unsupported_feature_view("linux", Feature.AUTOSTART)
        self.assertTrue(view["visible"])
        self.assertTrue(view["enabled"])
        self.assertEqual(view["badge"], "Доступно")
        self.assertIn("XDG", view["message"])

    def test_require_feature_fails_closed_with_structured_context(self):
        with self.assertRaises(UnsupportedFeatureError) as caught:
            require_feature("macos", Feature.AUTOSTART)
        self.assertEqual(caught.exception.backend_id, "macos")
        self.assertEqual(caught.exception.capability.feature, Feature.AUTOSTART)

    def test_linux_autostart_requirement_is_supported(self):
        capability = require_feature("linux", Feature.AUTOSTART)
        self.assertEqual(capability.state, CapabilityState.SUPPORTED)

    def test_unknown_backend_and_undeclared_feature_fail_closed(self):
        with self.assertRaises(ValueError):
            capabilities_for_backend("freebsd")
        with self.assertRaises(ValueError):
            capabilities_for_backend("")


if __name__ == "__main__":
    unittest.main()
