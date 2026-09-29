from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (
    ROOT / "native" / "windows_routing" / "routing_service_main.cpp"
).read_text(encoding="utf-8")
RESOURCES = (
    ROOT / "native" / "windows_routing" / "wfp_resources.cpp"
).read_text(encoding="utf-8")
CALLOUT = (
    ROOT / "native" / "windows_routing" / "routing_callout.cpp"
).read_text(encoding="utf-8")
ACCEPTANCE = (
    ROOT / "native" / "windows_routing" / "wfp_acceptance_helper.cpp"
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

    def test_callout_has_loop_prevention_and_bounded_admin_device(self):
        self.assertIn("FwpsQueryConnectionRedirectState0", CALLOUT)
        self.assertIn("FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF", CALLOUT)
        self.assertIn("FWPS_CONNECTION_REDIRECTED_BY_OTHER", CALLOUT)
        self.assertIn("SDDL_DEVOBJ_SYS_ALL_ADM_ALL", CALLOUT)

    def test_callout_preserves_original_destination_context(self):
        self.assertIn("ARVECTUM_REDIRECT_CONTEXT", CALLOUT)
        self.assertIn("original_remote", CALLOUT)
        self.assertIn("original_local", CALLOUT)
        self.assertIn("localRedirectContext", CALLOUT)
        self.assertIn("localRedirectTargetPID", CALLOUT)

    def test_callout_fail_closed_after_writable_acquisition_failure(self):
        self.assertIn("classify_out->actionType = FWP_ACTION_BLOCK", CALLOUT)
        self.assertIn("FwpsApplyModifiedLayerData0", CALLOUT)
        self.assertIn("FwpsReleaseClassifyHandle0", CALLOUT)

    def test_acceptance_helper_is_dynamic_and_app_scoped(self):
        self.assertIn("FWPM_SESSION_FLAG_DYNAMIC", ACCEPTANCE)
        self.assertIn("FWPM_CONDITION_ALE_APP_ID", ACCEPTANCE)
        self.assertIn("FWPM_CONDITION_IP_PROTOCOL", ACCEPTANCE)
        self.assertIn("FWP_ACTION_CALLOUT_TERMINATING", ACCEPTANCE)
        self.assertIn("FWPM_LAYER_ALE_CONNECT_REDIRECT_V4", ACCEPTANCE)

    def test_acceptance_helper_uses_transaction_and_disables_driver(self):
        self.assertIn("FwpmTransactionBegin0", ACCEPTANCE)
        self.assertIn("FwpmTransactionCommit0", ACCEPTANCE)
        self.assertIn("FwpmTransactionAbort0", ACCEPTANCE)
        self.assertIn("ConfigureDriver(0, 0, false)", ACCEPTANCE)
        self.assertNotIn("FwpmFilterDeleteById", ACCEPTANCE)
        self.assertNotIn("FwpmProviderDeleteByKey", ACCEPTANCE)


if __name__ == "__main__":
    unittest.main()
