#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "routing_service_protocol.h"
#include "routing_service_wfp.h"

#pragma comment(lib, "Advapi32.lib")

namespace {
constexpr wchar_t kServiceName[] = L"ArvectumProxyRouting";
constexpr wchar_t kPipeName[] = L"\\\\.\\pipe\\Arvectum.ProxyLauncher.Routing";
constexpr DWORD kMaxFrameBytes = 1024 * 1024;
constexpr DWORD kClientIoTimeoutMs = 5000;

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

DWORD WINAPI ControlHandler(DWORD control, DWORD, LPVOID, LPVOID) {
    if (control == SERVICE_CONTROL_STOP && g_stop_event != nullptr) {
        ReportStatus(SERVICE_STOP_PENDING);
        SetEvent(g_stop_event);
        return NO_ERROR;
    }
    return ERROR_CALL_NOT_IMPLEMENTED;
}

bool IoExact(
    HANDLE pipe,
    void* buffer,
    DWORD bytes,
    bool write) noexcept
{
    auto* cursor = static_cast<unsigned char*>(buffer);
    DWORD total = 0;
    while (total < bytes) {
        HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (event == nullptr) {
            return false;
        }
        OVERLAPPED overlapped{};
        overlapped.hEvent = event;
        DWORD transferred = 0;
        BOOL started = write
            ? WriteFile(
                pipe, cursor + total, bytes - total,
                &transferred, &overlapped)
            : ReadFile(
                pipe, cursor + total, bytes - total,
                &transferred, &overlapped);
        if (!started && GetLastError() == ERROR_IO_PENDING) {
            HANDLE waits[2] = {g_stop_event, event};
            const DWORD wait = WaitForMultipleObjects(
                2, waits, FALSE, kClientIoTimeoutMs);
            if (wait == WAIT_OBJECT_0 + 1) {
                started = GetOverlappedResult(
                    pipe, &overlapped, &transferred, FALSE);
            } else {
                CancelIoEx(pipe, &overlapped);
                CloseHandle(event);
                return false;
            }
        }
        if (!started || transferred == 0) {
            CloseHandle(event);
            return false;
        }
        total += transferred;
        CloseHandle(event);
    }
    return true;
}

bool ReadExact(HANDLE pipe, void* buffer, DWORD bytes) noexcept {
    return IoExact(pipe, buffer, bytes, false);
}

bool WriteExact(
    HANDLE pipe,
    const void* buffer,
    DWORD bytes) noexcept
{
    return IoExact(
        pipe,
        const_cast<void*>(buffer),
        bytes,
        true);
}

bool WriteFrame(HANDLE pipe, const std::string& response) noexcept {
    if (response.empty() || response.size() > kMaxFrameBytes) {
        return false;
    }
    const std::uint32_t length =
        static_cast<std::uint32_t>(response.size());
    std::array<unsigned char, 4> header{
        static_cast<unsigned char>(length & 0xff),
        static_cast<unsigned char>((length >> 8) & 0xff),
        static_cast<unsigned char>((length >> 16) & 0xff),
        static_cast<unsigned char>((length >> 24) & 0xff),
    };
    return WriteExact(
        pipe, header.data(), static_cast<DWORD>(header.size())) &&
        WriteExact(
            pipe, response.data(), static_cast<DWORD>(response.size()));
}

void HandleClient(
    HANDLE pipe,
    arvectum::routing::RoutingWfpSession* lifecycle)
{
    std::array<unsigned char, 4> header{};
    if (!ReadExact(
            pipe, header.data(), static_cast<DWORD>(header.size()))) {
        return;
    }
    const std::uint32_t length =
        static_cast<std::uint32_t>(header[0]) |
        (static_cast<std::uint32_t>(header[1]) << 8) |
        (static_cast<std::uint32_t>(header[2]) << 16) |
        (static_cast<std::uint32_t>(header[3]) << 24);
    if (length == 0 || length > kMaxFrameBytes) {
        return;
    }
    std::vector<unsigned char> body(length);
    if (!ReadExact(pipe, body.data(), length)) {
        return;
    }

    arvectum::routing::ServiceRequest request{};
    std::string error;
    if (!arvectum::routing::ParseServiceRequest(
            body.data(), body.size(), &request, &error)) {
        WriteFrame(
            pipe,
            "{\"command\":\"invalid\","
            "\"error\":\"invalid request\","
            "\"protocol_version\":2,"
            "\"status\":\"error\"}");
        return;
    }

    bool ok = false;
    bool resources_verified = false;
    const bool restore =
        request.command == arvectum::routing::ServiceCommand::kRestore;
    if (restore) {
        ok = lifecycle->Restore(&resources_verified, &error);
    } else {
        ok = lifecycle->Apply(request, &error);
    }
    const std::string response =
        arvectum::routing::BuildServiceResponse(
            request,
            ok,
            error.empty() ? nullptr : error.c_str(),
            restore,
            resources_verified);
    WriteFrame(pipe, response);
}

SECURITY_ATTRIBUTES PipeSecurity(PSECURITY_DESCRIPTOR* descriptor) {
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    constexpr wchar_t kSddl[] =
        L"D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;IU)";
    if (ConvertStringSecurityDescriptorToSecurityDescriptorW(
            kSddl, SDDL_REVISION_1, descriptor, nullptr)) {
        attributes.lpSecurityDescriptor = *descriptor;
    }
    return attributes;
}

bool WaitForConnection(HANDLE pipe) noexcept {
    HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    if (event == nullptr) {
        return false;
    }
    OVERLAPPED overlapped{};
    overlapped.hEvent = event;
    BOOL connected = ConnectNamedPipe(pipe, &overlapped);
    if (!connected) {
        const DWORD error = GetLastError();
        if (error == ERROR_PIPE_CONNECTED) {
            connected = TRUE;
        } else if (error == ERROR_IO_PENDING) {
            HANDLE waits[2] = {g_stop_event, event};
            const DWORD wait = WaitForMultipleObjects(
                2, waits, FALSE, INFINITE);
            if (wait == WAIT_OBJECT_0 + 1) {
                DWORD transferred = 0;
                connected = GetOverlappedResult(
                    pipe, &overlapped, &transferred, FALSE);
            } else {
                CancelIoEx(pipe, &overlapped);
                connected = FALSE;
            }
        }
    }
    CloseHandle(event);
    return connected == TRUE;
}

void RunPipeLoop(arvectum::routing::RoutingWfpSession* lifecycle) {
    while (WaitForSingleObject(g_stop_event, 0) == WAIT_TIMEOUT) {
        PSECURITY_DESCRIPTOR descriptor = nullptr;
        SECURITY_ATTRIBUTES attributes = PipeSecurity(&descriptor);
        HANDLE pipe = CreateNamedPipeW(
            kPipeName,
            PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
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
            if (WaitForSingleObject(g_stop_event, 250) != WAIT_TIMEOUT) {
                break;
            }
            continue;
        }
        if (WaitForConnection(pipe)) {
            HandleClient(pipe, lifecycle);
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

    arvectum::routing::RoutingWfpSession lifecycle;
    ReportStatus(SERVICE_RUNNING);
    RunPipeLoop(&lifecycle);
    bool verified = false;
    std::string ignored;
    lifecycle.Restore(&verified, &ignored);

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
