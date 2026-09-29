import json
import os
import tempfile
import unittest

from routing_ownership import RoutingOwnershipStore
from routing_rules import ApplicationIdentity, DestinationKind, DestinationSelector, RoutingAction, RoutingRule
from windows_app_routing import compile_windows_filter_plan
from windows_routing_controller import WindowsRoutingController
from windows_routing_service_contract import (
    OWNED_RESOURCES,
    WindowsRoutingContractError,
    build_apply_request,
    canonical_plan_json,
)


def plan_for(kind=DestinationKind.ALL, value=""):
    rule = RoutingRule(
        "browser-proxy",
        RoutingAction.PROXY,
        (DestinationSelector(kind, value),),
        ApplicationIdentity("windows", executable_path=r"C:\\Browser\\browser.exe"),
    )
    return compile_windows_filter_plan([rule], app_id_resolver=lambda path: b"\x01\x02")
class FakeService:
    def __init__(self):
        self.requests = []

    def request(self, payload):
        self.requests.append(payload)
        resources = payload["owned_resources"]
        if payload["command"] == "apply_plan":
            return {
                "protocol_version": payload["protocol_version"],
                "command": "apply_plan",
                "session_id": payload["session_id"],
                "plan_digest": payload["plan_digest"],
                "status": "ok",
                "applied_resources": resources,
            }
        return {
            "protocol_version": payload["protocol_version"],
            "command": "restore",
            "session_id": payload["session_id"],
            "plan_digest": payload["plan_digest"],
            "status": "ok",
            "removed_resources": resources,
            "remaining_owned_resources": [],
        }
class WindowsRoutingProductionTests(unittest.TestCase):
    def test_contract_admits_all_and_cidr_only(self):
        all_payload = json.loads(canonical_plan_json(plan_for()))
        self.assertEqual(all_payload["filters"][0]["address_families"], [4, 6])
        cidr_payload = json.loads(
            canonical_plan_json(plan_for(DestinationKind.CIDR, "203.0.113.7/24"))
        )
        self.assertEqual(cidr_payload["filters"][0]["destination_value"], "203.0.113.0/24")
        self.assertEqual(cidr_payload["filters"][0]["address_families"], [4])

    def test_domain_plan_is_rejected_by_production_protocol(self):
        plans = plan_for(DestinationKind.DOMAIN, "example.com")
        with self.assertRaises(WindowsRoutingContractError):
            canonical_plan_json(plans)

    def test_request_has_fixed_owned_resource_namespace(self):
        plans = plan_for()
        request = build_apply_request(
            plans,
            session_id="11111111-1111-4111-8111-111111111111",
            plan_digest="a" * 64,
            proxy_pid=1234,
            proxy_port=49152,
        )
        self.assertEqual(
            set(request["owned_resources"]),
            {item.resource_id for item in OWNED_RESOURCES},
        )
        self.assertTrue(
            all(x.startswith("Arvectum.ProxyLauncher.") for x in request["owned_resources"])
        )
        self.assertEqual(request["protocol_version"], 2)
        self.assertEqual(request["proxy"], {"pid": 1234, "port": 49152})

    def test_request_rejects_invalid_proxy_endpoint(self):
        for pid, port in ((0, 49152), (-1, 49152), (1234, 0), (1234, 65536), (True, 49152)):
            with self.subTest(pid=pid, port=port):
                with self.assertRaises(WindowsRoutingContractError):
                    build_apply_request(
                        plan_for(),
                        session_id="11111111-1111-4111-8111-111111111111",
                        plan_digest="a" * 64,
                        proxy_pid=pid,
                        proxy_port=port,
                    )

    def test_controller_journals_before_apply_and_clears_only_after_verified_restore(self):
        with tempfile.TemporaryDirectory() as temp:
            store = RoutingOwnershipStore(os.path.join(temp, "routing.json"))
            service = FakeService()
            controller = WindowsRoutingController(store, service)
            state = controller.activate(plan_for(), proxy_pid=1234, proxy_port=49152)
            self.assertEqual(state.phase, "applied")
            self.assertTrue(store.exists())
            self.assertEqual(service.requests[0]["command"], "apply_plan")
            self.assertTrue(controller.restore())
            self.assertFalse(store.exists())
            self.assertEqual(service.requests[1]["command"], "restore")
    def test_apply_failure_leaves_recovery_evidence(self):
        class RejectingService:
            def request(self, payload):
                return {
                    "protocol_version": payload["protocol_version"],
                    "command": payload["command"],
                    "session_id": payload["session_id"],
                    "plan_digest": payload["plan_digest"],
                    "status": "error",
                    "error": "simulated native failure",
                }

        with tempfile.TemporaryDirectory() as temp:
            store = RoutingOwnershipStore(os.path.join(temp, "routing.json"))
            controller = WindowsRoutingController(store, RejectingService())
            with self.assertRaises(WindowsRoutingContractError):
                controller.activate(plan_for(), proxy_pid=1234, proxy_port=49152)
            self.assertTrue(store.exists())
            self.assertEqual(store.load().phase, "restoring")
    def test_service_cannot_claim_partial_resource_set(self):
        class PartialService(FakeService):
            def request(self, payload):
                response = super().request(payload)
                response["applied_resources"] = payload["owned_resources"][:-1]
                return response

        with tempfile.TemporaryDirectory() as temp:
            store = RoutingOwnershipStore(os.path.join(temp, "routing.json"))
            controller = WindowsRoutingController(store, PartialService())
            with self.assertRaises(WindowsRoutingContractError):
                controller.activate(plan_for(), proxy_pid=1234, proxy_port=49152)
            self.assertEqual(store.load().phase, "restoring")


if __name__ == "__main__":
    unittest.main()
