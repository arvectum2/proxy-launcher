from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (
    ROOT / "native" / "windows_routing" / "routing_service_main.cpp"
).read_text(encoding="utf-8")
RESOURCES = (
    ROOT / "native" / "windows_routing" / "wfp_resources.cpp"
).read_text(encoding="utf-8")
LIFECYCLE = (
    ROOT / "native" / "windows_routing" / "routing_service_wfp.cpp"
).read_text(encoding="utf-8")
CALLOUT = (
    ROOT / "native" / "windows_routing" / "routing_callout.cpp"
).read_text(encoding="utf-8")
ACCEPTANCE = (
    ROOT / "native" / "windows_routing" / "wfp_acceptance_helper.cpp"
).read_text(encoding="utf-8")
SELECTED_CLIENT = (
    ROOT / "native" / "windows_routing" / "wfp_selected_client.cpp"
).read_text(encoding="utf-8")
TEST_INSTALL = (
    ROOT / "tools" / "windows_wfp_test_install.ps1"
).read_text(encoding="utf-8")
TEST_ROLLBACK = (
    ROOT / "tools" / "windows_wfp_test_rollback.ps1"
).read_text(encoding="utf-8")
LIVE_ACCEPTANCE = (
    ROOT / "tools" / "windows_wfp_live_acceptance.ps1"
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

    def test_service_dispatches_strict_protocol_and_wfp_lifecycle(self):
        self.assertIn("ParseServiceRequest", SERVICE)
        self.assertIn("BuildServiceResponse", SERVICE)
        self.assertIn("RoutingWfpSession", SERVICE)
        self.assertIn("kClientIoTimeoutMs = 5000", SERVICE)
        self.assertIn("FILE_FLAG_OVERLAPPED", SERVICE)
        self.assertIn("CancelIoEx", SERVICE)

    def test_service_wfp_lifecycle_is_dynamic_transactional_and_dual_stack(self):
        self.assertIn("FWPM_SESSION_FLAG_DYNAMIC", LIFECYCLE)
        self.assertIn("FwpmTransactionBegin0", LIFECYCLE)
        self.assertIn("FwpmTransactionCommit0", LIFECYCLE)
        self.assertIn("FwpmTransactionAbort0", LIFECYCLE)
        self.assertIn("FWPM_LAYER_ALE_CONNECT_REDIRECT_V4", LIFECYCLE)
        self.assertIn("FWPM_LAYER_ALE_CONNECT_REDIRECT_V6", LIFECYCLE)
        self.assertIn("FWPM_CONDITION_ALE_APP_ID", LIFECYCLE)
        self.assertIn("FWPM_CONDITION_IP_PROTOCOL", LIFECYCLE)
        self.assertIn("FWPM_CONDITION_IP_REMOTE_ADDRESS", LIFECYCLE)
        self.assertIn("FWP_ACTION_CALLOUT_TERMINATING", LIFECYCLE)
        self.assertIn("FWP_ACTION_PERMIT", LIFECYCLE)
        self.assertIn("ConfigureDriver(request.proxy_pid, request.proxy_port, true)", LIFECYCLE)
        self.assertIn("VerifyAbsent", LIFECYCLE)

    def test_resource_source_uses_fixed_arvectum_namespace(self):
        self.assertIn('L"Arvectum.ProxyLauncher."', RESOURCES)
        self.assertIn("IsArvectumResourceName", RESOURCES)

    def test_callout_has_loop_prevention_and_bounded_admin_device(self):
        self.assertIn("FwpsQueryConnectionRedirectState0", CALLOUT)
        self.assertIn("FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF", CALLOUT)
        self.assertNotIn("state == FWPS_CONNECTION_REDIRECTED_BY_OTHER", CALLOUT)
        self.assertIn("FWPS_METADATA_FIELD_PROCESS_ID", CALLOUT)
        self.assertIn("meta->processId == (UINT64)(ULONG)proxy_pid", CALLOUT)
        self.assertIn("FWPS_METADATA_FIELD_LOCAL_REDIRECT_TARGET_PID", CALLOUT)
        self.assertIn("meta->localRedirectTargetPID == (DWORD)proxy_pid", CALLOUT)
        self.assertIn("request->previousVersion != NULL", CALLOUT)
        self.assertIn("request->previousVersion->modifierFilterId == filter->filterId", CALLOUT)
        self.assertIn("request->previousVersion->localRedirectHandle != NULL", CALLOUT)
        self.assertIn("classify_out->rights |= FWPS_RIGHT_ACTION_WRITE", CALLOUT)
        self.assertIn("SDDL_DEVOBJ_SYS_ALL_ADM_ALL", CALLOUT)

    def test_callout_preserves_original_destination_context(self):
        self.assertIn("ARVECTUM_REDIRECT_CONTEXT", CALLOUT)
        self.assertIn("original_remote", CALLOUT)
        self.assertIn("original_local", CALLOUT)
        self.assertIn("localRedirectContext", CALLOUT)
        self.assertIn("localRedirectTargetPID", CALLOUT)
        self.assertIn("CaptureClassifyEndpoints", CALLOUT)
        self.assertIn("FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_REMOTE_ADDRESS", CALLOUT)
        self.assertIn("FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_REMOTE_PORT", CALLOUT)
        self.assertIn("FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_IP_REMOTE_ADDRESS", CALLOUT)
        self.assertIn("RtlUlongByteSwap(remote_address->uint32)", CALLOUT)
        self.assertIn("RtlUshortByteSwap(remote_port->uint16)", CALLOUT)
        self.assertNotIn(
            "&redirect_context->original_remote,\n        &request->remoteAddressAndPort",
            CALLOUT,
        )
        self.assertIn("FWPS_METADATA_FIELD_ORIGINAL_DESTINATION", CALLOUT)
        self.assertIn("meta->originalDestination", CALLOUT)
        self.assertIn("ARVECTUM_REDIRECT_CONTEXT_HAS_METADATA_ORIGINAL", CALLOUT)

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

    def test_acceptance_self_relay_proves_redirect_context_and_records(self):
        self.assertIn("--self-relay", ACCEPTANCE)
        self.assertIn("SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS", ACCEPTANCE)
        self.assertIn("SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT", ACCEPTANCE)
        self.assertIn("SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS", ACCEPTANCE)
        self.assertIn("ARVECTUM_WFP_REDIRECT_OBSERVED", ACCEPTANCE)
        self.assertIn("ARVECTUM_WFP_REDIRECT_CONTEXT request_remote=", ACCEPTANCE)
        self.assertIn("context.metadata_original", ACCEPTANCE)
        self.assertIn("GetCurrentProcessId()", ACCEPTANCE)

    def test_live_acceptance_uses_deterministic_selected_client(self):
        self.assertIn("ArvectumWfpSelectedClient.exe", LIVE_ACCEPTANCE)
        self.assertIn("selected-wfp-client.exe", LIVE_ACCEPTANCE)
        self.assertNotIn("selected-curl.exe", LIVE_ACCEPTANCE)
        self.assertIn("ARVECTUM_WFP_SELECTED_CLIENT_HTTP_200", LIVE_ACCEPTANCE)
        self.assertIn("$null -ne $helperExit -and $helperExit -ne 0", LIVE_ACCEPTANCE)
        self.assertIn(
            "ARVECTUM_WFP_REDIRECT_OBSERVED original=(127\\.|::1:)",
            LIVE_ACCEPTANCE,
        )

    def test_selected_client_is_single_socket_http_probe(self):
        self.assertIn("socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)", SELECTED_CLIENT)
        self.assertEqual(SELECTED_CLIENT.count("connect("), 1)
        self.assertIn("InetPtonW(AF_INET", SELECTED_CLIENT)
        self.assertIn("GET / HTTP/1.1", SELECTED_CLIENT)
        self.assertIn("ARVECTUM_WFP_SELECTED_CLIENT_HTTP_200", SELECTED_CLIENT)

    def test_test_install_rolls_back_only_certificates_added_by_this_attempt(self):
        self.assertIn("$certWasInRoot", TEST_INSTALL)
        self.assertIn("$certWasInPublisher", TEST_INSTALL)
        self.assertIn("function Remove-TestCertificates", TEST_INSTALL)
        self.assertIn("certutil.exe -addstore -f", TEST_INSTALL)
        self.assertIn("certutil.exe -delstore", TEST_INSTALL)
        self.assertNotIn("Import-Certificate", TEST_INSTALL)
        self.assertIn("certutil.exe -delstore", TEST_ROLLBACK)
        self.assertGreaterEqual(
            TEST_INSTALL.count("Remove-TestCertificates -Thumbprint $thumbprint"),
            4,
        )


if __name__ == "__main__":
    unittest.main()
