import unittest
from unittest import mock

import backend_runtime
import linux_policykit_ux as ux
import proxy_core as core


class PolicyKitBoundaryTests(unittest.TestCase):
    def test_interaction_marker_is_linux_only_and_explicit(self):
        env = {ux.POLKIT_INTERACTIVE_ENV: "1"}
        self.assertTrue(ux.policykit_interaction_requested("linux", env))
        self.assertTrue(ux.policykit_interaction_requested("linux-gnu", env))
        self.assertFalse(ux.policykit_interaction_requested("win32", env))
        self.assertFalse(ux.policykit_interaction_requested("linux", {}))

    def test_child_marker_never_leaks_from_parent_by_default(self):
        parent = {ux.POLKIT_INTERACTIVE_ENV: "1", "HOME": "/tmp/user"}
        child = ux.child_environment_for_policykit(
            "linux", interactive=False, environ=parent
        )
        self.assertNotIn(ux.POLKIT_INTERACTIVE_ENV, child)
        self.assertEqual(child["HOME"], "/tmp/user")

    def test_explicit_linux_child_gets_one_shot_marker(self):
        child = ux.child_environment_for_policykit(
            "linux", interactive=True, environ={"HOME": "/tmp/user"}
        )
        self.assertEqual(child[ux.POLKIT_INTERACTIVE_ENV], "1")
        self.assertNotIn(
            ux.POLKIT_INTERACTIVE_ENV,
            ux.child_environment_for_policykit(
                "darwin", interactive=True, environ={"HOME": "/tmp/user"}
            ),
        )

    def test_nmcli_ask_is_added_only_to_networkmanager_mutations(self):
        modify = ux.interactive_nmcli_arguments(
            ("/usr/bin/nmcli", "connection", "modify", "uuid", "abc")
        )
        reapply = ux.interactive_nmcli_arguments(
            ("/usr/bin/nmcli", "device", "reapply", "eth0")
        )
        readonly = ux.interactive_nmcli_arguments(
            ("/usr/bin/nmcli", "connection", "show", "--active")
        )
        self.assertEqual(modify[1], "--ask")
        self.assertEqual(reapply[1], "--ask")
        self.assertNotIn("--ask", readonly)

    def test_existing_ask_is_not_duplicated(self):
        args = ("/usr/bin/nmcli", "--ask", "connection", "modify", "uuid", "abc")
        self.assertEqual(ux.interactive_nmcli_arguments(args), args)

    def test_runner_preserves_subprocess_contract(self):
        completed = object()
        with mock.patch.object(ux.subprocess, "run", return_value=completed) as run:
            result = ux.run_nmcli_with_policykit(
                ["nmcli", "connection", "modify", "uuid", "abc"],
                text=True,
                check=False,
            )
        self.assertIs(result, completed)
        self.assertEqual(run.call_args.args[0][1], "--ask")
        self.assertTrue(run.call_args.kwargs["text"])
        self.assertFalse(run.call_args.kwargs["check"])


class LinuxCapabilityViewTests(unittest.TestCase):
    def test_auth_required_is_actionable_but_not_ready(self):
        view = ux.linux_capability_view(
            {"state": "auth_required", "message": "permission needed"}
        )
        self.assertEqual(view["key"], "linux_auth_required")
        self.assertTrue(view["can_on"])
        self.assertTrue(view["authorization_required"])
        self.assertIn("PolicyKit", view["hint"])

    def test_unavailable_disables_new_enable(self):
        view = ux.linux_capability_view(
            {"state": "unavailable", "message": "Сеть оставлена без изменений."}
        )
        self.assertFalse(view["can_on"])
        self.assertFalse(view["authorization_required"])
        self.assertIn("Сеть оставлена", view["hint"])

    def test_unavailable_fallback_uses_runtime_platform_label(self):
        view = ux.linux_capability_view(
            {"state": "unavailable", "message": ""},
            platform_label="Linux / RED OS",
        )
        self.assertIn("Linux / RED OS", view["hint"])
        self.assertNotIn("Linux/Astra", view["hint"])

    def test_ready_allows_enable_without_authorization_prompt(self):
        view = ux.linux_capability_view(
            {"state": "ready", "message": "ready"}, running=True
        )
        self.assertTrue(view["can_on"])
        self.assertTrue(view["can_off"])
        self.assertFalse(view["authorization_required"])


class CoreInteractiveGateTests(unittest.TestCase):
    def setUp(self):
        core._reset_proxy_backend_for_tests()
        self.facade_globals = core._require_new_mutation_operational.__globals__

    def tearDown(self):
        core._reset_proxy_backend_for_tests()

    @staticmethod
    def auth_status():
        return backend_runtime.BackendOperationalStatus(
            backend_id="linux",
            platform_label="Linux / Astra Linux",
            state=backend_runtime.OperationalState.AUTH_REQUIRED,
            can_enable=False,
            title="auth",
            message="auth",
            reasons=(),
        )

    def test_unmarked_auth_required_stays_fail_closed(self):
        replacements = {
            "_effective_runtime_platform": lambda: "linux",
            "_interactive_policykit_context": lambda: False,
        }
        with mock.patch.dict(self.facade_globals, replacements), mock.patch.object(
            backend_runtime,
            "require_enable_operational",
            side_effect=backend_runtime.BackendOperationalError(self.auth_status()),
        ):
            with self.assertRaises(backend_runtime.BackendOperationalError):
                core._require_new_mutation_operational()

    def test_marked_auth_required_can_reach_real_networkmanager_authority(self):
        replacements = {
            "_effective_runtime_platform": lambda: "linux",
            "_interactive_policykit_context": lambda: True,
        }
        with mock.patch.dict(self.facade_globals, replacements), mock.patch.object(
            backend_runtime,
            "operational_status_for_platform",
            return_value=self.auth_status(),
        ):
            status = core._require_new_mutation_operational()
        self.assertEqual(status.state, backend_runtime.OperationalState.AUTH_REQUIRED)
        self.assertFalse(status.can_enable)

    def test_interactive_backend_receives_policykit_runner(self):
        backend = mock.Mock()
        backend.backend_id = "linux"
        replacements = {
            "_effective_runtime_platform": lambda: "linux",
            "_interactive_policykit_context": lambda: True,
        }
        with mock.patch.dict(self.facade_globals, replacements), mock.patch.object(
            backend_runtime, "create_backend", return_value=backend
        ) as create:
            self.assertIs(core.get_proxy_backend(), backend)
        self.assertIs(
            create.call_args.kwargs["linux_runner"],
            ux.run_nmcli_with_policykit,
        )


if __name__ == "__main__":
    unittest.main()
