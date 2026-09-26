import json
import os
import tempfile
import unittest
from unittest import mock

import proxy_core as core
from application_exclusions import (
    ApplicationExclusionError,
    application_exclusion_capability,
    application_exclusion_rule,
    compile_application_exclusion_rules,
    compile_windows_application_exclusion_plan,
    load_application_exclusions,
    save_application_exclusions,
)
from routing_rules import ApplicationIdentity, DestinationKind, RoutingAction
from windows_app_routing import WindowsAppRoutingError


class ApplicationExclusionTests(unittest.TestCase):
    def test_rule_is_direct_for_all_destinations_and_deterministic(self):
        app = ApplicationIdentity(
            "windows",
            executable_path=r"C:\Program Files\Browser\browser.exe",
            display_name="Browser",
        )
        first = application_exclusion_rule(app)
        second = application_exclusion_rule(app)
        self.assertEqual(first.rule_id, second.rule_id)
        self.assertEqual(first.action, RoutingAction.DIRECT)
        self.assertEqual(len(first.destinations), 1)
        self.assertEqual(first.destinations[0].kind, DestinationKind.ALL)
        self.assertEqual(first.destinations[0].value, "*")
        self.assertEqual(first.application, app)

    def test_rule_compilation_deduplicates_and_sorts_by_stable_identity(self):
        b = ApplicationIdentity("windows", executable_path=r"C:\b.exe", display_name="B")
        a = ApplicationIdentity("windows", executable_path=r"C:\a.exe", display_name="A")
        rules = compile_application_exclusion_rules([b, a, b])
        self.assertEqual([r.application.stable_id for r in rules], [a.stable_id, b.stable_id])

    def test_save_and_load_round_trip_is_canonical(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "app_exclusions.json")
            a = ApplicationIdentity("windows", executable_path=r"C:\a.exe", display_name="A")
            b = ApplicationIdentity("linux", executable_path="/usr/bin/b", display_name="B")
            with mock.patch.object(core, "app_exclusions_path", return_value=path):
                self.assertTrue(save_application_exclusions([b, a, a]))
                loaded = load_application_exclusions()
            self.assertEqual([x.stable_id for x in loaded], sorted([a.stable_id, b.stable_id]))
            payload = json.loads(open(path, encoding="utf-8").read())
            self.assertEqual(payload["schema_version"], 1)
            self.assertEqual(len(payload["applications"]), 2)

    def test_corrupt_state_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "app_exclusions.json")
            with open(path, "w", encoding="utf-8") as stream:
                stream.write("{not-json")
            with mock.patch.object(core, "app_exclusions_path", return_value=path):
                with self.assertRaises(ApplicationExclusionError):
                    load_application_exclusions()

    def test_duplicate_state_fails_closed_instead_of_silently_rewriting(self):
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "app_exclusions.json")
            identity = {
                "platform": "windows",
                "executable_path": r"C:\x.exe",
                "bundle_id": "",
                "package_id": "",
                "display_name": "X",
            }
            with open(path, "w", encoding="utf-8") as stream:
                json.dump({"schema_version": 1, "applications": [identity, identity]}, stream)
            with mock.patch.object(core, "app_exclusions_path", return_value=path):
                with self.assertRaises(ApplicationExclusionError):
                    load_application_exclusions()

    def test_capability_never_claims_live_enforcement(self):
        windows = application_exclusion_capability("win32")
        linux = application_exclusion_capability("linux")
        macos = application_exclusion_capability("darwin")
        self.assertTrue(windows["configuration_supported"])
        self.assertTrue(windows["plan_compilation_supported"])
        self.assertFalse(windows["live_enforcement_supported"])
        self.assertEqual(windows["state"], "owner_gate")
        self.assertFalse(linux["live_enforcement_supported"])
        self.assertEqual(linux["state"], "native_adapter_pending")
        self.assertFalse(macos["configuration_supported"])
        self.assertEqual(macos["state"], "managed_only")

    def test_windows_plan_is_read_only_direct_bypass_plan(self):
        app = ApplicationIdentity("windows", executable_path=r"C:\Browser\browser.exe")
        plans = compile_windows_application_exclusion_plan(
            [app], app_id_resolver=lambda path: b"\x01\x02"
        )
        self.assertEqual(len(plans), 1)
        plan = plans[0]
        self.assertEqual(plan.operation, "permit_bypass_arvectum_redirect")
        self.assertEqual(plan.destination_kind, "all")
        self.assertTrue(plan.enforcement_ready)
        self.assertEqual(plan.application_wfp_id_hex, "0102")

    def test_windows_plan_rejects_non_windows_identity(self):
        app = ApplicationIdentity("linux", executable_path="/usr/bin/browser")
        with self.assertRaises(WindowsAppRoutingError):
            compile_windows_application_exclusion_plan(
                [app], app_id_resolver=lambda path: b"app"
            )

    def test_canonical_state_file_is_registered_for_migration(self):
        self.assertIn("app_exclusions.json", core._STATE_FILES)
        self.assertTrue(core.app_exclusions_path().endswith("app_exclusions.json"))


if __name__ == "__main__":
    unittest.main()
