import json
import os
import tempfile
import unittest

from routing_rules import ApplicationIdentity
from windows_per_app_routing import (
    PLAN_SCHEMA,
    PROTOCOL_SCHEMA,
    WindowsPerAppRoutingController,
    WindowsPerAppRoutingError,
    WindowsRoutingServiceClient,
    compile_windows_application_exclusion_enforcement_plan,
    owned_resources,
)


class FakeService:
    def __init__(self):
        self.requests = []
        self.fail_apply = False
        self.remaining = 0

    def transport(self, request):
        self.requests.append(request)
        if request["command"] == "apply":
            if self.fail_apply:
                return {"schema": PROTOCOL_SCHEMA, "ok": False, "error": "apply rejected"}
            return {"schema": PROTOCOL_SCHEMA, "ok": True}
        if request["command"] == "restore":
            return {
                "schema": PROTOCOL_SCHEMA,
                "ok": self.remaining == 0,
                "remaining_resources": self.remaining,
            }
        if request["command"] == "status":
            return {"schema": PROTOCOL_SCHEMA, "ok": True, "state": "ready"}
        raise AssertionError(request)


class WindowsPerAppRoutingTests(unittest.TestCase):
    def _plan(self):
        apps = [
            ApplicationIdentity("windows", executable_path=r"C:\Apps\Browser.exe"),
            ApplicationIdentity("windows", executable_path=r"C:\Apps\Chat.exe"),
        ]
        ids = {
            r"C:\Apps\Browser.exe": b"browser-app-id",
            r"C:\Apps\Chat.exe": b"chat-app-id",
        }
        return compile_windows_application_exclusion_enforcement_plan(
            apps,
            {"local_http_port": 8080, "local_socks_port": 1080},
            {"http": 49101, "socks5": 49102},
            app_id_resolver=lambda path: ids[path],
        )

    def test_plan_contains_only_bounded_loopback_proxy_redirects(self):
        plan = self._plan()
        payload = plan.to_dict()
        self.assertEqual(payload["schema"], PLAN_SCHEMA)
        self.assertEqual(payload["mode"], "application_exclusion_direct")
        self.assertEqual(len(payload["redirects"]), 4)
        self.assertEqual(
            {(x["proxy_kind"], x["source_proxy_port"], x["direct_port"]) for x in payload["redirects"]},
            {("http", 8080, 49101), ("socks5", 1080, 49102)},
        )
        self.assertTrue(all(x["remote_address"] == "127.0.0.1" for x in payload["redirects"]))
        self.assertTrue(all(x["transport"] == "tcp" for x in payload["redirects"]))
        self.assertTrue(all(x["family"] == "ipv4" for x in payload["redirects"]))
        self.assertTrue(all(x["resource_id"].startswith("Arvectum.ProxyLauncher.") for x in payload["redirects"]))
        self.assertNotIn(r"C:\Apps", plan.canonical_json())

    def test_plan_is_deterministic_and_deduplicates_application_identity(self):
        app = ApplicationIdentity("windows", executable_path=r"C:\Apps\Browser.exe")
        kwargs = dict(
            settings={"local_http_port": 8080, "local_socks_port": 1080},
            direct_ports={"http": 49101, "socks5": 49102},
            app_id_resolver=lambda path: b"same",
        )
        one = compile_windows_application_exclusion_enforcement_plan([app, app], **kwargs)
        two = compile_windows_application_exclusion_enforcement_plan([app], **kwargs)
        self.assertEqual(one.canonical_json(), two.canonical_json())
        self.assertEqual(len(one.redirects), 2)

    def test_non_windows_identity_is_rejected(self):
        app = ApplicationIdentity("linux", executable_path="/usr/bin/browser")
        with self.assertRaises(WindowsPerAppRoutingError):
            compile_windows_application_exclusion_enforcement_plan(
                [app],
                {"local_http_port": 8080, "local_socks_port": 1080},
                {"http": 49101, "socks5": 49102},
                app_id_resolver=lambda path: b"id",
            )

    def test_proxy_direct_port_collision_is_rejected(self):
        app = ApplicationIdentity("windows", executable_path=r"C:\Apps\Browser.exe")
        with self.assertRaises(WindowsPerAppRoutingError):
            compile_windows_application_exclusion_enforcement_plan(
                [app],
                {"local_http_port": 8080, "local_socks_port": 1080},
                {"http": 8080, "socks5": 49102},
                app_id_resolver=lambda path: b"id",
            )

    def test_resources_are_exactly_filter_resources_from_plan(self):
        plan = self._plan()
        resources = owned_resources(plan)
        self.assertEqual(len(resources), 4)
        self.assertTrue(all(item.resource_type == "wfp_filter" for item in resources))
        self.assertEqual(
            {item.resource_id for item in resources},
            {item.resource_id for item in plan.redirects},
        )

    def test_controller_journals_before_apply_and_clears_after_verified_restore(self):
        service = FakeService()
        client = WindowsRoutingServiceClient(service.transport)
        app = ApplicationIdentity("windows", executable_path=r"C:\Apps\Browser.exe")
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "routing.json")
            controller = WindowsPerAppRoutingController(
                path, client=client, app_id_resolver=lambda exe: b"id"
            )
            self.assertTrue(
                controller.apply_exclusions(
                    [app],
                    {"local_http_port": 8080, "local_socks_port": 1080},
                    {"http": 49101, "socks5": 49102},
                )
            )
            self.assertTrue(os.path.exists(path))
            state = controller.store.load()
            self.assertEqual(state.phase, "applied")
            self.assertEqual(service.requests[0]["command"], "apply")
            self.assertEqual(service.requests[0]["session_id"], state.session_id)

            self.assertTrue(controller.restore())
            self.assertFalse(os.path.exists(path))
            self.assertEqual(service.requests[-1]["command"], "restore")

    def test_failed_apply_leaves_restoring_evidence_for_retry(self):
        service = FakeService()
        service.fail_apply = True
        client = WindowsRoutingServiceClient(service.transport)
        app = ApplicationIdentity("windows", executable_path=r"C:\Apps\Browser.exe")
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "routing.json")
            controller = WindowsPerAppRoutingController(
                path, client=client, app_id_resolver=lambda exe: b"id"
            )
            with self.assertRaises(WindowsPerAppRoutingError):
                controller.apply_exclusions(
                    [app],
                    {"local_http_port": 8080, "local_socks_port": 1080},
                    {"http": 49101, "socks5": 49102},
                )
            self.assertEqual(controller.store.load().phase, "restoring")

    def test_unverified_restore_keeps_ownership_evidence(self):
        service = FakeService()
        client = WindowsRoutingServiceClient(service.transport)
        app = ApplicationIdentity("windows", executable_path=r"C:\Apps\Browser.exe")
        with tempfile.TemporaryDirectory() as temp:
            path = os.path.join(temp, "routing.json")
            controller = WindowsPerAppRoutingController(
                path, client=client, app_id_resolver=lambda exe: b"id"
            )
            controller.apply_exclusions(
                [app],
                {"local_http_port": 8080, "local_socks_port": 1080},
                {"http": 49101, "socks5": 49102},
            )
            service.remaining = 1
            self.assertFalse(controller.restore())
            self.assertTrue(os.path.exists(path))
            self.assertEqual(controller.store.load().phase, "restoring")


if __name__ == "__main__":
    unittest.main()
