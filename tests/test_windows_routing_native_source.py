from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (
    ROOT / "native" / "windows_routing" / "routing_service_main.cpp"
).read_text(encoding="utf-8")
RESOURCES = (
    ROOT / "native" / "windows_routing" / "wfp_resources.cpp"
).read_text(encoding="utf-8")


class WindowsRoutingNativeSourceTests(unittest.TestCase):
    def test_service_pipe_rejects_remote_clients_and_bounds_frames(self):
        self.assertIn("PIPE_REJECT_REMOTE_CLIENTS", SERVICE)
        self.assertIn("kMaxFrameBytes = 1024 * 1024", SERVICE)
        self.assertIn("length > kMaxFrameBytes", SERVICE)

    def test_service_pipe_has_explicit_local_acl(self):
        self.assertIn("ConvertStringSecurityDescriptorToSecurityDescriptorW", SERVICE)
        self.assertIn("(A;;GA;;;SY)", SERVICE)
        self.assertIn("(A;;GA;;;BA)", SERVICE)
        self.assertIn("(A;;GRGW;;;IU)", SERVICE)

    def test_phase_one_service_contains_no_wfp_mutation_api(self):
        forbidden = (
            "FwpmFilterAdd",
            "FwpmCalloutAdd",
            "FwpmProviderAdd",
            "FwpmSubLayerAdd",
            "FwpmFilterDelete",
            "FwpmCalloutDelete",
            "FwpmProviderDelete",
            "FwpmSubLayerDelete",
        )
        for symbol in forbidden:
            self.assertNotIn(symbol, SERVICE)

    def test_resource_source_uses_fixed_arvectum_namespace(self):
        self.assertIn('L"Arvectum.ProxyLauncher."', RESOURCES)
        self.assertIn("IsArvectumResourceName", RESOURCES)


if __name__ == "__main__":
    unittest.main()
