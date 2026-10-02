from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "native" / "windows_windivert"


def _read(name):
    return (NATIVE / name).read_text(encoding="utf-8-sig")


def test_service_is_user_mode_and_uses_signed_windivert_dependency():
    source = _read("windivert_service_main.cpp")
    session = _read("windivert_routing_session.cpp")
    assert "ArvectumProxyWinDivertRouting" in source
    assert "Arvectum.ProxyLauncher.WinDivertRouting" in source
    assert "WinDivertOpen(" in session
    assert "ArvectumProxyRoutingCallout" not in source + session
    assert "TESTSIGNING" not in source + session
    assert "bcdedit" not in (source + session).lower()


def test_service_serializes_cold_driver_open():
    source = _read("windivert_routing_session.cpp")
    mutex = "Global\\\\Arvectum.ProxyLauncher.WinDivert.DriverOpen"
    assert mutex in source
    wait_at = source.index("WaitForSingleObject(")
    first_open = source.index("WinDivertOpen(", wait_at)
    second_open = source.index("WinDivertOpen(", first_open + 1)
    release = source.index("ReleaseMutex(", second_open)
    assert wait_at < first_open < second_open < release


def test_service_binds_proxy_process_to_pipe_caller_sid():
    source = _read("windivert_routing_session.cpp")
    assert "ProcessOwnedBySid(process, caller_sid)" in source
    assert "OpenProcessToken(process, TOKEN_QUERY" in source
    assert "EqualSid(user->User.Sid, expected_sid)" in source
    assert "RestoreForCaller(" in source
    assert "StoredSidEquals(caller_sid_, caller_sid)" in source


def test_native_protocol_never_receives_plain_executable_paths():
    protocol = _read("windivert_service_protocol.cpp")
    header = _read("windivert_service_protocol.h")
    assert "application_path_sha256" in protocol + header
    assert "executable_path" not in protocol + header
    assert "kMaxApplications = 128" in header
    assert "WinDivert.SocketTracker" in protocol
    assert "WinDivert.NetworkTranslator" in protocol


def test_loopback_smoke_supports_ipv4_and_ipv6():
    source = _read("loopback_smoke.cpp")
    assert "AF_INET" in source
    assert "AF_INET6" in source
    assert "in6addr_loopback" in source
    assert '"ipv4"' in source
    assert '"ipv6"' in source


def test_session_is_tcp_loopback_bounded_and_fail_safe():
    source = _read("windivert_routing_session.cpp")
    assert '"loopback and tcp and remotePort == "' in source
    assert '"loopback and tcp and (tcp.DstPort == "' in source
    assert "IsSelectedPort(ipv6, source)" in source
    assert "IsSelectedPort(ipv6, destination)" in source
    assert "WinDivertHelperCalcChecksums(" in source
    assert "WinDivertSend(" in source

