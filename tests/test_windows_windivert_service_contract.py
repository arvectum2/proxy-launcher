import json
import os
import tempfile

import unittest

_ASSERTIONS = unittest.TestCase()

from routing_ownership import RoutingOwnershipStore
from routing_rules import ApplicationIdentity
from windows_windivert_backend import (
    compile_windivert_application_plan,
    windows_executable_path_sha256,
)
from windows_windivert_controller import WindowsWinDivertController
from windows_windivert_service_contract import (
    OWNED_RESOURCES,
    PROTOCOL_VERSION,
    WindowsWinDivertContractError,
    build_apply_request,
    canonical_plan_json,
)


SESSION_ID = "11111111-1111-4111-8111-111111111111"
DIGEST = "a" * 64


def _plans(paths=(r"C:\Apps\A.exe",), port=8080):
    identities = tuple(
        ApplicationIdentity("windows", executable_path=path)
        for path in paths
    )
    return compile_windivert_application_plan(
        identities,
        local_proxy_port=port,
    )
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


def test_contract_serializes_path_hashes_and_one_proxy_port():
    payload = json.loads(
        canonical_plan_json(
            _plans((r"C:\Apps\B.exe", r"C:\Apps\A.exe"))
        )
    )
    assert payload["protocol_version"] == PROTOCOL_VERSION
    assert payload["backend"] == "windivert"
    assert {
        item["application_path_sha256"]
        for item in payload["applications"]
    } == {
        windows_executable_path_sha256(r"C:\Apps\A.exe"),
        windows_executable_path_sha256(r"C:\Apps\B.exe"),
    }
    assert all(
        set(item) == {
            "application_path_sha256",
            "local_proxy_port",
            "rule_id",
        }
        for item in payload["applications"]
    )
    assert {item["local_proxy_port"] for item in payload["applications"]} == {
        8080
    }


def test_apply_request_has_ephemeral_owned_resource_namespace():
    request = build_apply_request(
        _plans(),
        session_id=SESSION_ID,
        plan_digest=DIGEST,
        proxy_pid=1234,
        direct_listener_port=49152,
    )
    assert request["protocol_version"] == PROTOCOL_VERSION
    assert request["proxy"] == {
        "pid": 1234,
        "direct_listener_port": 49152,
    }
    assert set(request["owned_resources"]) == {
        item.resource_id for item in OWNED_RESOURCES
    }
    assert all(
        item.startswith("Arvectum.ProxyLauncher.WinDivert.")
        for item in request["owned_resources"]
    )


def test_apply_request_rejects_invalid_proxy_pid():
    for pid in (0, -1, True):
        with _ASSERTIONS.assertRaises(WindowsWinDivertContractError):
            build_apply_request(
                _plans(),
                session_id=SESSION_ID,
                plan_digest=DIGEST,
                proxy_pid=pid,
                direct_listener_port=49152,
            )


def test_apply_request_rejects_invalid_direct_listener_port():
    for port in (0, 65536, True):
        with _ASSERTIONS.assertRaises(WindowsWinDivertContractError):
            build_apply_request(
                _plans(),
                session_id=SESSION_ID,
                plan_digest=DIGEST,
                proxy_pid=1234,
                direct_listener_port=port,
            )


def test_apply_request_rejects_proxy_direct_port_collision():
    with _ASSERTIONS.assertRaisesRegex(
        WindowsWinDivertContractError, "must differ"
    ):
        build_apply_request(
            _plans(port=8080),
            session_id=SESSION_ID,
            plan_digest=DIGEST,
            proxy_pid=1234,
            direct_listener_port=8080,
        )
def test_controller_journals_and_restores_verified_resources():
    with tempfile.TemporaryDirectory() as temp:
        store = RoutingOwnershipStore(
            os.path.join(temp, "windivert-routing.json")
        )
        service = FakeService()
        controller = WindowsWinDivertController(store, service)
        state = controller.activate(
            _plans(),
            proxy_pid=1234,
            direct_listener_port=49152,
        )
        assert state.phase == "applied"
        assert store.exists()
        assert service.requests[0]["command"] == "apply_plan"
        assert controller.restore() is True
        assert not store.exists()
        assert service.requests[1]["command"] == "restore"


def test_apply_failure_leaves_restoring_evidence():
    class RejectingService:
        def request(self, payload):
            return {
                "protocol_version": payload["protocol_version"],
                "command": payload["command"],
                "session_id": payload["session_id"],
                "plan_digest": payload["plan_digest"],
                "status": "error",
                "error": "simulated WinDivert failure",
            }
    with tempfile.TemporaryDirectory() as temp:
        store = RoutingOwnershipStore(
            os.path.join(temp, "windivert-routing.json")
        )
        controller = WindowsWinDivertController(
            store,
            RejectingService(),
        )
        with _ASSERTIONS.assertRaises(WindowsWinDivertContractError):
            controller.activate(
                _plans(),
                proxy_pid=1234,
                direct_listener_port=49152,
            )
        assert store.exists()
        assert store.load().phase == "restoring"


def test_service_cannot_claim_partial_resource_set():
    class PartialService(FakeService):
        def request(self, payload):
            response = super().request(payload)
            if payload["command"] == "apply_plan":
                response["applied_resources"] = payload[
                    "owned_resources"
                ][:-1]
            return response

    with tempfile.TemporaryDirectory() as temp:
        store = RoutingOwnershipStore(
            os.path.join(temp, "windivert-routing.json")
        )
        controller = WindowsWinDivertController(
            store,
            PartialService(),
        )
        with _ASSERTIONS.assertRaises(WindowsWinDivertContractError):
            controller.activate(
                _plans(),
                proxy_pid=1234,
                direct_listener_port=49152,
            )
        assert store.load().phase == "restoring"
