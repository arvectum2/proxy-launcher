import json
import unittest
import uuid
from urllib.parse import parse_qs, urlparse

from managed_nodes import (
    ExitClass,
    ManagedNode,
    NoCapacityError,
    RealityServerSecrets,
    Transport,
    issue_access,
    render_client_uri,
    render_server_config,
    select_node,
)


PUBLIC_KEY = "TEST_PUBLIC_KEY_NOT_SECRET"
PRIVATE_KEY = "TEST_PRIVATE_KEY_SERVER_ONLY"
SHORT_ID = "a1b2c3d4e5f60708"


def node(
    node_id="nl-01",
    *,
    country="NL",
    active=0,
    capacity=50,
    healthy=True,
):
    return ManagedNode(
        node_id=node_id,
        country_code=country,
        host=f"{node_id}.managed.arvectum.test",
        port=443,
        transport=Transport.VLESS_REALITY,
        capacity_users=capacity,
        active_users=active,
        server_name="www.microsoft.com",
        reality_public_key=PUBLIC_KEY,
        reality_short_id=SHORT_ID,
        healthy=healthy,
    )


class ManagedNodeContractTests(unittest.TestCase):
    def test_allocator_selects_least_utilized_healthy_node_deterministically(self):
        selected = select_node(
            [
                node("nl-03", active=10, capacity=50),
                node("nl-02", active=5, capacity=50),
                node("nl-01", active=5, capacity=50),
                node("nl-dead", active=0, capacity=50, healthy=False),
                node("de-01", country="DE", active=0, capacity=50),
            ],
            country_code="nl",
        )
        self.assertEqual(selected.node_id, "nl-01")

    def test_allocator_rejects_full_pool(self):
        with self.assertRaises(NoCapacityError):
            select_node([node(active=50, capacity=50)], country_code="NL")

    def test_issue_access_uses_unique_uuid_and_public_parameters_only(self):
        first = issue_access(node(), user_id="user-1", exit_class=ExitClass.SHARED_DATACENTER)
        second = issue_access(node(), user_id="user-2", exit_class=ExitClass.SHARED_DATACENTER)
        self.assertNotEqual(first.credential_id, second.credential_id)
        uuid.UUID(first.credential_id)
        rendered = json.dumps(first.client_payload(), sort_keys=True)
        self.assertIn(PUBLIC_KEY, rendered)
        self.assertNotIn(PRIVATE_KEY, rendered)
        self.assertNotIn("supplier", rendered.lower())

    def test_issue_access_can_be_deterministic_for_control_plane_tests(self):
        expected = uuid.UUID("11111111-2222-3333-4444-555555555555")
        access = issue_access(
            node(),
            user_id="user-1",
            exit_class=ExitClass.DEDICATED_DATACENTER,
            exit_id="ipv4-203.0.113.10",
            credential_factory=lambda: expected,
        )
        self.assertEqual(access.credential_id, str(expected))
        self.assertEqual(access.exit_id, "ipv4-203.0.113.10")

    def test_vless_uri_contains_only_client_visible_reality_parameters(self):
        access = issue_access(
            node(),
            user_id="user-1",
            exit_class=ExitClass.SHARED_DATACENTER,
            credential_factory=lambda: uuid.UUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        )
        uri = render_client_uri(access, label="APL Netherlands")
        parsed = urlparse(uri)
        query = parse_qs(parsed.query)
        self.assertEqual(parsed.scheme, "vless")
        self.assertIn(access.credential_id, parsed.netloc)
        self.assertEqual(query["security"], ["reality"])
        self.assertEqual(query["flow"], ["xtls-rprx-vision"])
        self.assertEqual(query["pbk"], [PUBLIC_KEY])
        self.assertEqual(query["sid"], [SHORT_ID])
        self.assertNotIn(PRIVATE_KEY, uri)

    def test_xray_config_supports_many_users_on_one_node(self):
        first = issue_access(
            node(),
            user_id="user-1",
            exit_class=ExitClass.SHARED_DATACENTER,
            credential_factory=lambda: uuid.UUID("11111111-1111-1111-1111-111111111111"),
        )
        second = issue_access(
            node(),
            user_id="user-2",
            exit_class=ExitClass.SHARED_DATACENTER,
            credential_factory=lambda: uuid.UUID("22222222-2222-2222-2222-222222222222"),
        )
        config = render_server_config(
            node(),
            secrets=RealityServerSecrets(
                private_key=PRIVATE_KEY,
                destination="www.microsoft.com:443",
            ),
            users=[first, second],
        )
        clients = config["inbounds"][0]["settings"]["clients"]
        self.assertEqual([item["id"] for item in clients], [first.credential_id, second.credential_id])
        self.assertEqual(config["inbounds"][0]["streamSettings"]["realitySettings"]["privateKey"], PRIVATE_KEY)
        self.assertNotIn(PRIVATE_KEY, json.dumps(first.client_payload()))

    def test_xray_config_rejects_cross_node_and_duplicate_credentials(self):
        access = issue_access(
            node("nl-01"),
            user_id="user-1",
            exit_class=ExitClass.SHARED_DATACENTER,
            credential_factory=lambda: uuid.UUID("33333333-3333-3333-3333-333333333333"),
        )
        secrets = RealityServerSecrets(PRIVATE_KEY, "www.microsoft.com:443")
        with self.assertRaises(ValueError):
            render_server_config(node("nl-02"), secrets=secrets, users=[access])
        with self.assertRaises(ValueError):
            render_server_config(node("nl-01"), secrets=secrets, users=[access, access])

    def test_managed_contract_does_not_remove_manual_proxy_codepath(self):
        # APL-NODE-001 is additive. The existing manual profile model remains
        # separate from managed-node contracts during Phase A.
        from free_gateway.config import UpstreamProxy

        manual = UpstreamProxy(
            location_id="manual-fixture",
            label="Manual fixture",
            country_code="DE",
            host="proxy.example.test",
            port=8080,
            username="user",
            password="password",
        )
        self.assertEqual(manual.host, "proxy.example.test")
        self.assertEqual(manual.port, 8080)


if __name__ == "__main__":
    unittest.main()
