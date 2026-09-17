import unittest
from types import SimpleNamespace
from unittest import mock

import backend_runtime
import proxy_core as core
from linux_networkmanager_preflight import PreflightStatus


class LinuxOperationalStatusTests(unittest.TestCase):
    def fake(self, status, reasons=()):
        return SimpleNamespace(status=status, reasons=tuple(reasons))

    def test_ready_preflight_allows_enable_and_has_user_view(self):
        status = backend_runtime.operational_status_for_platform(
            "linux",
            linux_preflight=self.fake(PreflightStatus.READY),
        )
        self.assertEqual(status.state, backend_runtime.OperationalState.READY)
        self.assertTrue(status.can_enable)
        view = backend_runtime.operational_status_view(status)
        self.assertTrue(view["enabled"])
        self.assertEqual(view["badge"], "Доступно")
        self.assertEqual(view["platform_label"], "Linux")


    def test_redos_runtime_uses_distinct_platform_signature(self):
        status = backend_runtime.operational_status_for_platform(
            "linux",
            linux_preflight=self.fake(PreflightStatus.READY),
            linux_runtime=SimpleNamespace(platform_label="Linux / RED OS"),
        )
        self.assertEqual(status.platform_label, "Linux / RED OS")
        self.assertIn("Linux / RED OS", status.message)

    def test_auth_required_is_not_misreported_as_ready(self):
        status = backend_runtime.operational_status_for_platform(
            "linux2",
            linux_preflight=self.fake(
                PreflightStatus.AUTH_REQUIRED,
                ("NetworkManager modification requires PolicyKit authorization",),
            ),
        )
        self.assertEqual(status.state, backend_runtime.OperationalState.AUTH_REQUIRED)
        self.assertFalse(status.can_enable)
        view = backend_runtime.operational_status_view(status)
        self.assertEqual(view["badge"], "Нужно разрешение")
        self.assertIn("PolicyKit", view["message"])
        self.assertEqual(len(view["reasons"]), 1)

    def test_unavailable_blocks_enable_with_actionable_ux(self):
        status = backend_runtime.operational_status_for_platform(
            "linux",
            linux_preflight=self.fake(
                PreflightStatus.UNAVAILABLE,
                ("nmcli client is not installed or not discoverable",),
            ),
        )
        self.assertEqual(status.state, backend_runtime.OperationalState.UNAVAILABLE)
        self.assertFalse(status.can_enable)
        view = backend_runtime.operational_status_view(status)
        self.assertEqual(view["badge"], "Недоступно")
        self.assertIn("Сеть оставлена без изменений", view["message"])

    def test_require_enable_operational_raises_governed_error(self):
        preflight = self.fake(PreflightStatus.AUTH_REQUIRED)
        with self.assertRaises(backend_runtime.BackendOperationalError) as caught:
            backend_runtime.require_enable_operational(
                "linux", linux_preflight=preflight
            )
        self.assertEqual(
            caught.exception.status.state,
            backend_runtime.OperationalState.AUTH_REQUIRED,
        )

    def test_windows_keeps_existing_runtime_behavior(self):
        status = backend_runtime.operational_status_for_platform("win32")
        self.assertEqual(status.state, backend_runtime.OperationalState.READY)
        self.assertTrue(status.can_enable)


class CoreMutationGateTests(unittest.TestCase):
    def setUp(self):
        core._reset_proxy_backend_for_tests()

    def tearDown(self):
        core._reset_proxy_backend_for_tests()

    def test_enable_is_blocked_before_backend_creation_when_preflight_fails(self):
        error_status = backend_runtime.BackendOperationalStatus(
            backend_id="linux",
            platform_label="Linux / Astra Linux",
            state=backend_runtime.OperationalState.UNAVAILABLE,
            can_enable=False,
            title="Недоступно",
            message="blocked",
            reasons=("test",),
        )
        with mock.patch.object(
            backend_runtime,
            "require_enable_operational",
            side_effect=backend_runtime.BackendOperationalError(error_status),
        ), mock.patch.object(backend_runtime, "create_backend") as create:
            self.assertFalse(core.enable_system_proxy())
        create.assert_not_called()

    def test_sync_no_proxy_is_blocked_before_backend_creation(self):
        with mock.patch.object(
            backend_runtime,
            "require_enable_operational",
            side_effect=RuntimeError("preflight blocked"),
        ), mock.patch.object(backend_runtime, "create_backend") as create:
            self.assertFalse(core.sync_client_no_proxy())
        create.assert_not_called()

    def test_disable_remains_available_when_enable_preflight_would_fail(self):
        backend = mock.Mock()
        backend.backend_id = "linux"
        backend.disable.return_value = True
        with mock.patch.object(
            backend_runtime,
            "require_enable_operational",
            side_effect=AssertionError("disable must not call preflight gate"),
        ), mock.patch.object(backend_runtime, "create_backend", return_value=backend):
            self.assertTrue(core.disable_system_proxy())
        backend.disable.assert_called_once_with()

    def test_restore_pending_remains_available_when_preflight_degrades(self):
        backend = mock.Mock()
        backend.backend_id = "linux"
        backend.restore_pending.return_value = True
        with mock.patch.object(
            backend_runtime,
            "require_enable_operational",
            side_effect=AssertionError("restore inspection must not call preflight gate"),
        ), mock.patch.object(backend_runtime, "create_backend", return_value=backend):
            self.assertTrue(core.network_restore_pending())
        backend.restore_pending.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
