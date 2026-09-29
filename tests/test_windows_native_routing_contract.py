from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
DRIVER = (ROOT / "native/windows-routing/driver/driver.c").read_text(encoding="utf-8")
SERVICE = (ROOT / "native/windows-routing/service/service.cpp").read_text(encoding="utf-8")
PROJECT = (ROOT / "native/windows-routing/driver/ArvectumRoutingDriver.vcxproj").read_text(encoding="utf-8")


class WindowsNativeRoutingContractTests(unittest.TestCase):
    def test_kernel_surface_is_single_connect_redirect_v4_callout(self):
        self.assertIn("FwpsCalloutRegister0", DRIVER)
        self.assertIn("FwpsAcquireWritableLayerDataPointer0", DRIVER)
        self.assertIn("FwpsApplyModifiedLayerData0", DRIVER)
        self.assertIn("FwpsRedirectHandleCreate0", DRIVER)
        self.assertNotIn("ALE_BIND_REDIRECT", DRIVER)
        self.assertNotIn("CONNECT_REDIRECT_V6", DRIVER)

    def test_kernel_redirect_is_loopback_port_only_and_has_loop_guard(self):
        self.assertIn("filter->context & 0xFFFFu", DRIVER)
        self.assertIn("ARVECTUM_LOOPBACK_V4_NETWORK_ORDER", DRIVER)
        self.assertIn("FwpsQueryConnectionRedirectState0", DRIVER)
        self.assertIn("FWPS_CONNECTION_REDIRECTED_BY_SELF", DRIVER)
        self.assertNotIn("ExAllocatePool", DRIVER)

    def test_service_uses_dynamic_wfp_session_and_owned_namespace(self):
        self.assertIn("FWPM_SESSION_FLAG_DYNAMIC", SERVICE)
        self.assertIn("ARVECTUM_ROUTING_PROVIDER", SERVICE)
        self.assertIn("ARVECTUM_ROUTING_SUBLAYER", SERVICE)
        self.assertIn("Arvectum.ProxyLauncher.AppExclusion.", SERVICE)
        self.assertNotIn("FWPM_FILTER_FLAG_PERSISTENT", SERVICE)

    def test_service_filter_is_bounded_to_app_loopback_port_and_tcp(self):
        for token in (
            "FWPM_CONDITION_ALE_APP_ID",
            "FWPM_CONDITION_IP_REMOTE_ADDRESS",
            "FWPM_CONDITION_IP_REMOTE_PORT",
            "FWPM_CONDITION_IP_PROTOCOL",
            "0x7F000001u",
            "IPPROTO_TCP",
            "FWP_ACTION_CALLOUT_TERMINATING",
        ):
            self.assertIn(token, SERVICE)
        self.assertIn('L"127.0.0.1"', SERVICE)
        self.assertIn('L"application_exclusion_direct"', SERVICE)

    def test_pipe_is_local_owner_sid_only_not_world_writable(self):
        self.assertIn("PIPE_REJECT_REMOTE_CLIENTS", SERVICE)
        self.assertIn("ImpersonateNamedPipeClient", SERVICE)
        self.assertIn("EqualSid", SERVICE)
        self.assertIn("D:P(A;;GA;;;SY)(A;;GRGW;;;", SERVICE)
        self.assertNotIn(";;;WD)", SERVICE)
        self.assertNotIn(";;;AU)", SERVICE)

    def test_driver_project_is_x64_wdm_and_wfp_linked(self):
        self.assertIn("<DriverType>WDM</DriverType>", PROJECT)
        self.assertIn("WindowsKernelModeDriver10.0", PROJECT)
        self.assertIn("Fwpkclnt.lib", PROJECT)
        self.assertIn("<Platform>x64</Platform>", PROJECT)


if __name__ == "__main__":
    unittest.main()
