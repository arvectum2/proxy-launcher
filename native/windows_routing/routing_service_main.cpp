#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#pragma comment(lib, "Advapi32.lib")

namespace {
constexpr wchar_t kServiceName[] = L"ArvectumProxyRouting";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\Arvectum.ProxyLauncher.Routing";
constexpr DWORD kMaxFrameBytes = 1024 * 1024;

SERVICE_STATUS_HANDLE g_status_handle = nullptr;
HANDLE g_stop_event = nullptr;

void ReportStatus(DWORD state, DWORD error = NO_ERROR) {
    SERVICE_STATUS status{};
    status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    status.dwCurrentState = state;
    status.dwWin32ExitCode = error;
    status.dwControlsAccepted =
        state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP : 0;
    SetServiceStatus(g_status_handle, &status);
}
DWORD WINAPI ControlHandler(
    DWORD control, DWORD, LPVOID, LPVOID) {
    if (control == SERVICE_CONTROL_STOP && g_stop_event != nullptr) {
        ReportStatus(SERVICE_STOP_PENDING);
        SetEvent(g_stop_event);
        return NO_ERROR;
    }
    return ERROR_CALL_NOT_IMPLEMENTED;
}

bool ReadExact(HANDLE pipe, void* buffer, DWORD bytes) {
    auto* cursor = static_cast<unsigned char*>(buffer);
    DWORD total = 0;
    while (total < bytes) {
        DWORD received = 0;
        if (!ReadFile(pipe, cursor + total, bytes - total, &received, nullptr) ||
            received == 0) {
            return false;
        }
        total += received;
    }
    return true;
}

bool WriteExact(HANDLE pipe, const void* buffer, DWORD bytes) {
    const auto* cursor = static_cast<const unsigned char*>(buffer);
    DWORD total = 0;
    while (total < bytes) {
        DWORD sent = 0;
        if (!WriteFile(pipe, cursor + total, bytes - total, &sent, nullptr) ||
            sent == 0) {
            return false;
        }
        total += sent;
    }
    return true;
}

void HandleClient(HANDLE pipe) {
    std::array<unsigned char, 4> header{};
    if (!ReadExact(pipe, header.data(), static_cast<DWORD>(header.size()))) {
        return;
    }
    const uint32_t length =
        static_cast<uint32_t>(header[0]) |
        (static_cast<uint32_t>(header[1]) << 8) |
        (static_cast<uint32_t>(header[2]) << 16) |
        (static_cast<uint32_t>(header[3]) << 24);
    if (length == 0 || length > kMaxFrameBytes) {
        return;
    }
    std::vector<unsigned char> body(length);
    if (!ReadExact(pipe, body.data(), length)) {
        return;
    }

    // Phase 1 deliberately does not mutate WFP state. The service host proves
    // the privileged/local IPC boundary before the callout lifecycle is wired.
    constexpr char response[] =
        "{\"protocol_version\":1,\"command\":\"unsupported\","
        "\"status\":\"error\",\"error\":\"native enforcement not wired\"}";
    const uint32_t response_length =
        static_cast<uint32_t>(sizeof(response) - 1);
    std::array<unsigned char, 4> response_header{
        static_cast<unsigned char>(response_length & 0xff),
        static_cast<unsigned char>((response_length >> 8) & 0xff),
        static_cast<unsigned char>((response_length >> 16) & 0xff),
        static_cast<unsigned char>((response_length >> 24) & 0xff),
    };
    WriteExact(
        pipe, response_header.data(),
        static_cast<DWORD>(response_header.size()));
    WriteExact(pipe, response, response_length);
}

SECURITY_ATTRIBUTES PipeSecurity(PSECURITY_DESCRIPTOR* descriptor) {
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    // SYSTEM + Administrators full control; interactive users read/write.
    constexpr wchar_t kSddl[] =
        L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;IU)";
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
            kSddl, SDDL_REVISION_1, descriptor, nullptr)) {
        attributes.lpSecurityDescriptor = *descriptor;
    }
    return attributes;
}

void RunPipeLoop() {
    while (WaitForSingleObject(g_stop_event, 0) == WAIT_TIMEOUT) {
        PSECURITY_DESCRIPTOR descriptor = nullptr;
        SECURITY_ATTRIBUTES attributes = PipeSecurity(&descriptor);
        HANDLE pipe = CreateNamedPipeW(
            kPipeName,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT |
                PIPE_REJECT_REMOTE_CLIENTS,
            1,
            kMaxFrameBytes,
            kMaxFrameBytes,
            1000,
            attributes.lpSecurityDescriptor ? &attributes : nullptr);
        if (descriptor != nullptr) {
            LocalFree(descriptor);
        }
        if (pipe == INVALID_HANDLE_VALUE) {
            Sleep(250);
            continue;
        }
        const BOOL connected =
            ConnectNamedPipe(pipe, nullptr) ||
            GetLastError() == ERROR_PIPE_CONNECTED;
        if (connected) {
            HandleClient(pipe);
            FlushFileBuffers(pipe);
            DisconnectNamedPipe(pipe);
        }
        CloseHandle(pipe);
    }
}

void WINAPI ServiceMain(DWORD, wchar_t**) {
    g_status_handle = RegisterServiceCtrlHandlerExW(
        kServiceName, ControlHandler, nullptr);
    if (g_status_handle == nullptr) {
        return;
    }
    g_stop_event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (g_stop_event == nullptr) {
        ReportStatus(SERVICE_STOPPED, GetLastError());
        return;
    }
    ReportStatus(SERVICE_RUNNING);
    RunPipeLoop();
    CloseHandle(g_stop_event);
    g_stop_event = nullptr;
    ReportStatus(SERVICE_STOPPED);
}
}  // namespace

int wmain() {
    SERVICE_TABLE_ENTRYW table[] = {
        {const_cast<LPWSTR>(kServiceName), ServiceMain},
        {nullptr, nullptr},
    };
    if (!StartServiceCtrlDispatcherW(table)) {
        return static_cast<int>(GetLastError());
    }
    return 0;
}
