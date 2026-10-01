#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>

#include "windivert_routing_session.h"

#include <bcrypt.h>
#include <windivert.h>

#include <algorithm>
#include <array>
#include <cwctype>
#include <memory>
#include <utility>

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Bcrypt.lib")
#pragma comment(lib, "Ws2_32.lib")

namespace arvectum::windivert {
namespace {

constexpr INT16 kSocketPriority = 2000;
constexpr INT16 kNetworkPriority = 1900;
constexpr wchar_t kDriverOpenMutex[] =
    L"Global\\Arvectum.ProxyLauncher.WinDivert.DriverOpen";
constexpr DWORD kDriverOpenMutexTimeoutMs = 15000;

bool NtOk(NTSTATUS status) noexcept {
    return status >= 0;
}

std::uint32_t PortKey(
    bool ipv6,
    std::uint16_t port) noexcept
{
    return (ipv6 ? 0x10000u : 0u) |
        static_cast<std::uint32_t>(port);
}

std::wstring NormalizePath(std::wstring value) {
    std::replace(value.begin(), value.end(), L'/', L'\\');
    DWORD required =
        GetFullPathNameW(value.c_str(), 0, nullptr, nullptr);
    if (required != 0) {
        std::wstring full(required, L'\0');
        const DWORD written = GetFullPathNameW(
            value.c_str(), required, full.data(), nullptr);
        if (written != 0 && written < required) {
            full.resize(written);
            value.swap(full);
        }
    }

    if (!value.empty()) {
        std::wstring lower(value.size(), L'\0');
        const int mapped = LCMapStringEx(
            LOCALE_NAME_INVARIANT,
            LCMAP_LOWERCASE,
            value.data(),
            static_cast<int>(value.size()),
            lower.data(),
            static_cast<int>(lower.size()),
            nullptr,
            nullptr,
            0);
        if (mapped == static_cast<int>(value.size())) {
            value.swap(lower);
        } else {
            CharLowerBuffW(
                value.data(),
                static_cast<DWORD>(value.size()));
        }
    }
    return value;
}

bool WideToUtf8(
    const std::wstring& value,
    std::string* output) noexcept
{
    if (output == nullptr) {
        return false;
    }
    output->clear();
    if (value.empty()) {
        return true;
    }
    const int required = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    if (required <= 0) {
        return false;
    }
    output->resize(static_cast<std::size_t>(required));
    const int written = WideCharToMultiByte(
        CP_UTF8,
        WC_ERR_INVALID_CHARS,
        value.data(),
        static_cast<int>(value.size()),
        output->data(),
        required,
        nullptr,
        nullptr);
    return written == required;
}

bool Sha256Hex(
    const std::string& value,
    std::string* output) noexcept
{
    if (output == nullptr) {
        return false;
    }

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD object_size = 0;
    DWORD hash_size = 0;
    DWORD bytes = 0;
    std::vector<unsigned char> object;
    std::vector<unsigned char> digest;
    bool ok = false;

    if (!NtOk(BCryptOpenAlgorithmProvider(
            &algorithm,
            BCRYPT_SHA256_ALGORITHM,
            nullptr,
            0))) {
        goto cleanup;
    }
    if (!NtOk(BCryptGetProperty(
            algorithm,
            BCRYPT_OBJECT_LENGTH,
            reinterpret_cast<PUCHAR>(&object_size),
            sizeof(object_size),
            &bytes,
            0)) ||
        object_size == 0) {
        goto cleanup;
    }
    if (!NtOk(BCryptGetProperty(
            algorithm,
            BCRYPT_HASH_LENGTH,
            reinterpret_cast<PUCHAR>(&hash_size),
            sizeof(hash_size),
            &bytes,
            0)) ||
        hash_size != 32) {
        goto cleanup;
    }

    object.resize(object_size);
    digest.resize(hash_size);
    if (!NtOk(BCryptCreateHash(
            algorithm,
            &hash,
            object.data(),
            object_size,
            nullptr,
            0,
            0))) {
        goto cleanup;
    }
    if (!value.empty() &&
        !NtOk(BCryptHashData(
            hash,
            reinterpret_cast<PUCHAR>(
                const_cast<char*>(value.data())),
            static_cast<ULONG>(value.size()),
            0))) {
        goto cleanup;
    }
    if (!NtOk(BCryptFinishHash(
            hash,
            digest.data(),
            static_cast<ULONG>(digest.size()),
            0))) {
        goto cleanup;
    }

    {
        static constexpr char kHex[] = "0123456789abcdef";
        output->clear();
        output->reserve(digest.size() * 2);
        for (unsigned char byte : digest) {
            output->push_back(kHex[(byte >> 4) & 0x0f]);
            output->push_back(kHex[byte & 0x0f]);
        }
    }
    ok = true;

cleanup:
    if (hash != nullptr) {
        BCryptDestroyHash(hash);
    }
    if (algorithm != nullptr) {
        BCryptCloseAlgorithmProvider(algorithm, 0);
    }
    return ok;
}

bool ProcessPathHash(
    std::uint32_t pid,
    std::string* output) noexcept
{
    HANDLE process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE,
        pid);
    if (process == nullptr) {
        return false;
    }

    std::wstring path(32768, L'\0');
    DWORD length = static_cast<DWORD>(path.size());
    const BOOL queried = QueryFullProcessImageNameW(
        process,
        0,
        path.data(),
        &length);
    CloseHandle(process);
    if (!queried || length == 0) {
        return false;
    }
    path.resize(length);

    std::string utf8;
    return WideToUtf8(NormalizePath(std::move(path)), &utf8) &&
        Sha256Hex(utf8, output);
}

bool ProcessOwnedBySid(
    HANDLE process,
    PSID expected_sid) noexcept
{
    if (process == nullptr || !IsValidSid(expected_sid)) {
        return false;
    }
    HANDLE token = nullptr;
    if (!OpenProcessToken(process, TOKEN_QUERY, &token)) {
        return false;
    }

    DWORD required = 0;
    GetTokenInformation(
        token, TokenUser, nullptr, 0, &required);
    if (required == 0 ||
        GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
        CloseHandle(token);
        return false;
    }

    std::vector<unsigned char> storage(required);
    const BOOL ok = GetTokenInformation(
        token,
        TokenUser,
        storage.data(),
        required,
        &required);
    CloseHandle(token);
    if (!ok) {
        return false;
    }
    TOKEN_USER* user =
        reinterpret_cast<TOKEN_USER*>(storage.data());
    return IsValidSid(user->User.Sid) &&
        EqualSid(user->User.Sid, expected_sid);
}

bool CopySidBytes(
    PSID sid,
    std::vector<unsigned char>* output) noexcept
{
    if (output == nullptr || !IsValidSid(sid)) {
        return false;
    }
    const DWORD length = GetLengthSid(sid);
    output->resize(length);
    if (!CopySid(length, output->data(), sid)) {
        output->clear();
        return false;
    }
    return true;
}

bool StoredSidEquals(
    const std::vector<unsigned char>& stored,
    PSID candidate) noexcept
{
    return !stored.empty() &&
        IsValidSid(
            const_cast<unsigned char*>(stored.data())) &&
        IsValidSid(candidate) &&
        EqualSid(
            const_cast<unsigned char*>(stored.data()),
            candidate);
}

std::string SocketFilter(std::uint16_t proxy_port) {
    return "loopback and tcp and remotePort == " +
        std::to_string(proxy_port) +
        " and (event == CONNECT or event == CLOSE)";
}

std::string NetworkFilter(
    std::uint16_t proxy_port,
    std::uint16_t direct_port)
{
    return "loopback and tcp and (tcp.DstPort == " +
        std::to_string(proxy_port) +
        " or tcp.SrcPort == " +
        std::to_string(direct_port) + ")";
}

}  // namespace

RoutingSession::~RoutingSession() {
    bool ignored = false;
    std::string error;
    Restore(&ignored, &error);
}

bool RoutingSession::ProcessPathMatches(
    std::uint32_t pid) const noexcept
{
    std::string hash;
    return ProcessPathHash(pid, &hash) &&
        application_hashes_.find(hash) !=
            application_hashes_.end();
}

bool RoutingSession::IsSelectedPort(
    bool ipv6,
    std::uint16_t port) const noexcept
{
    std::lock_guard<std::mutex> guard(ports_mutex_);
    return selected_ports_.find(PortKey(ipv6, port)) !=
        selected_ports_.end();
}

void RoutingSession::AddSelectedPort(
    bool ipv6,
    std::uint16_t port)
{
    std::lock_guard<std::mutex> guard(ports_mutex_);
    selected_ports_.insert(PortKey(ipv6, port));
}

void RoutingSession::RemoveSelectedPort(
    bool ipv6,
    std::uint16_t port)
{
    std::lock_guard<std::mutex> guard(ports_mutex_);
    selected_ports_.erase(PortKey(ipv6, port));
}

void RoutingSession::SocketLoop() noexcept {
    while (!stop_.load()) {
        WINDIVERT_ADDRESS address{};
        if (!WinDivertRecv(
                socket_handle_,
                nullptr,
                0,
                nullptr,
                &address)) {
            if (stop_.load()) {
                break;
            }
            Sleep(1);
            continue;
        }
        const auto& socket = address.Socket;
        if (socket.Protocol != IPPROTO_TCP ||
            socket.RemotePort != proxy_port_ ||
            socket.LocalPort == 0) {
            continue;
        }

        const bool ipv6 = address.IPv6 != 0;
        if (address.Event ==
                WINDIVERT_EVENT_SOCKET_CONNECT) {
            if (ProcessPathMatches(socket.ProcessId)) {
                AddSelectedPort(
                    ipv6,
                    static_cast<std::uint16_t>(
                        socket.LocalPort));
            }
        } else if (
            address.Event == WINDIVERT_EVENT_SOCKET_CLOSE) {
            RemoveSelectedPort(
                ipv6,
                static_cast<std::uint16_t>(
                    socket.LocalPort));
        }
    }
}

void RoutingSession::NetworkLoop() noexcept {
    unsigned char packet[WINDIVERT_MTU_MAX];
    while (!stop_.load()) {
        UINT packet_length = 0;
        WINDIVERT_ADDRESS address{};
        if (!WinDivertRecv(
                network_handle_,
                packet,
                sizeof(packet),
                &packet_length,
                &address)) {
            if (stop_.load()) {
                break;
            }
            Sleep(1);
            continue;
        }

        PWINDIVERT_TCPHDR tcp = nullptr;
        if (!WinDivertHelperParsePacket(
                packet,
                packet_length,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                &tcp,
                nullptr,
                nullptr,
                nullptr,
                nullptr,
                nullptr) ||
            tcp == nullptr) {
            WinDivertSend(
                network_handle_,
                packet,
                packet_length,
                nullptr,
                &address);
            continue;
        }

        const std::uint16_t source =
            WinDivertHelperNtohs(tcp->SrcPort);
        const std::uint16_t destination =
            WinDivertHelperNtohs(tcp->DstPort);
        const bool ipv6 = address.IPv6 != 0;
        bool changed = false;

        if (destination == proxy_port_ &&
            IsSelectedPort(ipv6, source)) {
            tcp->DstPort =
                WinDivertHelperHtons(direct_port_);
            changed = true;
        } else if (
            source == direct_port_ &&
            IsSelectedPort(ipv6, destination)) {
            tcp->SrcPort =
                WinDivertHelperHtons(proxy_port_);
            changed = true;
        }

        if (changed) {
            WinDivertHelperCalcChecksums(
                packet,
                packet_length,
                &address,
                0);
        }
        WinDivertSend(
            network_handle_,
            packet,
            packet_length,
            nullptr,
            &address);
    }
}

bool RoutingSession::Apply(
    const ServiceRequest& request,
    PSID caller_sid,
    std::string* error)
{
    if (error != nullptr) {
        error->clear();
    }
    std::lock_guard<std::mutex> guard(state_mutex_);

    if (socket_handle_ != INVALID_HANDLE_VALUE ||
        network_handle_ != INVALID_HANDLE_VALUE ||
        proxy_process_ != nullptr) {
        if (error != nullptr) {
            *error = "WinDivert routing session already active";
        }
        return false;
    }
    if (request.applications.empty() ||
        !IsValidSid(caller_sid)) {
        if (error != nullptr) {
            *error = "WinDivert routing request is incomplete";
        }
        return false;
    }

    HANDLE process = OpenProcess(
        SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION,
        FALSE,
        request.proxy_pid);
    if (process == nullptr) {
        if (error != nullptr) {
            *error = "proxy process cannot be opened";
        }
        return false;
    }
    if (!ProcessOwnedBySid(process, caller_sid)) {
        CloseHandle(process);
        if (error != nullptr) {
            *error = "proxy process owner does not match caller";
        }
        return false;
    }

    std::unordered_set<std::string> hashes;
    const std::uint16_t proxy_port =
        request.applications.front().local_proxy_port;
    for (const auto& application : request.applications) {
        if (application.local_proxy_port != proxy_port ||
            application.application_path_sha256.size() != 64) {
            CloseHandle(process);
            if (error != nullptr) {
                *error = "WinDivert application plan is invalid";
            }
            return false;
        }
        hashes.insert(application.application_path_sha256);
    }

    HANDLE open_mutex = CreateMutexW(
        nullptr, FALSE, kDriverOpenMutex);
    if (open_mutex == nullptr) {
        CloseHandle(process);
        if (error != nullptr) {
            *error = "WinDivert driver-open mutex failed";
        }
        return false;
    }
    const DWORD wait = WaitForSingleObject(
        open_mutex,
        kDriverOpenMutexTimeoutMs);
    if (wait != WAIT_OBJECT_0 &&
        wait != WAIT_ABANDONED) {
        CloseHandle(open_mutex);
        CloseHandle(process);
        if (error != nullptr) {
            *error = "WinDivert driver-open mutex timed out";
        }
        return false;
    }

    const std::string socket_filter =
        SocketFilter(proxy_port);
    const std::string network_filter =
        NetworkFilter(
            proxy_port,
            request.direct_listener_port);

    HANDLE socket_handle = WinDivertOpen(
        socket_filter.c_str(),
        WINDIVERT_LAYER_SOCKET,
        kSocketPriority,
        WINDIVERT_FLAG_SNIFF |
            WINDIVERT_FLAG_RECV_ONLY);
    const DWORD socket_error =
        socket_handle == INVALID_HANDLE_VALUE
            ? GetLastError()
            : ERROR_SUCCESS;

    HANDLE network_handle = INVALID_HANDLE_VALUE;
    DWORD network_error = ERROR_SUCCESS;
    if (socket_handle != INVALID_HANDLE_VALUE) {
        network_handle = WinDivertOpen(
            network_filter.c_str(),
            WINDIVERT_LAYER_NETWORK,
            kNetworkPriority,
            0);
        if (network_handle == INVALID_HANDLE_VALUE) {
            network_error = GetLastError();
        }
    }

    ReleaseMutex(open_mutex);
    CloseHandle(open_mutex);

    if (socket_handle == INVALID_HANDLE_VALUE ||
        network_handle == INVALID_HANDLE_VALUE) {
        if (network_handle != INVALID_HANDLE_VALUE) {
            WinDivertClose(network_handle);
        }
        if (socket_handle != INVALID_HANDLE_VALUE) {
            WinDivertClose(socket_handle);
        }
        CloseHandle(process);
        if (error != nullptr) {
            *error = socket_error != ERROR_SUCCESS
                ? "WinDivert socket-layer open failed"
                : "WinDivert network-layer open failed";
        }
        SetLastError(
            socket_error != ERROR_SUCCESS
                ? socket_error
                : network_error);
        return false;
    }

    std::vector<unsigned char> sid;
    if (!CopySidBytes(caller_sid, &sid)) {
        WinDivertClose(network_handle);
        WinDivertClose(socket_handle);
        CloseHandle(process);
        if (error != nullptr) {
            *error = "caller SID could not be retained";
        }
        return false;
    }

    application_hashes_ = std::move(hashes);
    caller_sid_ = std::move(sid);
    session_id_ = request.session_id;
    plan_digest_ = request.plan_digest;
    proxy_port_ = proxy_port;
    direct_port_ = request.direct_listener_port;
    proxy_process_ = process;
    socket_handle_ = socket_handle;
    network_handle_ = network_handle;
    stop_.store(false);

    try {
        socket_thread_ =
            std::thread(&RoutingSession::SocketLoop, this);
        network_thread_ =
            std::thread(&RoutingSession::NetworkLoop, this);
    } catch (...) {
        bool ignored = false;
        StopLocked(&ignored, error);
        if (error != nullptr && error->empty()) {
            *error = "WinDivert worker startup failed";
        }
        return false;
    }
    return true;
}

bool RoutingSession::StopLocked(
    bool* resources_verified,
    std::string* error) noexcept
{
    if (resources_verified != nullptr) {
        *resources_verified = false;
    }
    if (error != nullptr) {
        error->clear();
    }

    stop_.store(true);
    if (socket_handle_ != INVALID_HANDLE_VALUE) {
        WinDivertShutdown(
            socket_handle_,
            WINDIVERT_SHUTDOWN_BOTH);
    }
    if (network_handle_ != INVALID_HANDLE_VALUE) {
        WinDivertShutdown(
            network_handle_,
            WINDIVERT_SHUTDOWN_BOTH);
    }

    if (socket_thread_.joinable()) {
        socket_thread_.join();
    }
    if (network_thread_.joinable()) {
        network_thread_.join();
    }
    bool ok = true;
    if (socket_handle_ != INVALID_HANDLE_VALUE) {
        ok = WinDivertClose(socket_handle_) && ok;
        socket_handle_ = INVALID_HANDLE_VALUE;
    }
    if (network_handle_ != INVALID_HANDLE_VALUE) {
        ok = WinDivertClose(network_handle_) && ok;
        network_handle_ = INVALID_HANDLE_VALUE;
    }
    if (proxy_process_ != nullptr) {
        CloseHandle(proxy_process_);
        proxy_process_ = nullptr;
    }

    application_hashes_.clear();
    {
        std::lock_guard<std::mutex> ports_guard(ports_mutex_);
        selected_ports_.clear();
    }
    caller_sid_.clear();
    session_id_.clear();
    plan_digest_.clear();
    proxy_port_ = 0;
    direct_port_ = 0;
    stop_.store(false);

    if (resources_verified != nullptr) {
        *resources_verified = ok;
    }
    if (!ok && error != nullptr) {
        *error = "WinDivert handles did not close cleanly";
    }
    return ok;
}

bool RoutingSession::RestoreForCaller(
    const ServiceRequest& request,
    PSID caller_sid,
    bool* resources_verified,
    std::string* error)
{
    std::lock_guard<std::mutex> guard(state_mutex_);
    const bool inactive =
        socket_handle_ == INVALID_HANDLE_VALUE &&
        network_handle_ == INVALID_HANDLE_VALUE &&
        proxy_process_ == nullptr;
    if (inactive) {
        if (resources_verified != nullptr) {
            *resources_verified = true;
        }
        if (error != nullptr) {
            error->clear();
        }
        return true;
    }
    if (!StoredSidEquals(caller_sid_, caller_sid)) {
        if (resources_verified != nullptr) {
            *resources_verified = false;
        }
        if (error != nullptr) {
            *error = "WinDivert restore caller does not own session";
        }
        return false;
    }
    if (request.session_id != session_id_ ||
        request.plan_digest != plan_digest_) {
        if (resources_verified != nullptr) {
            *resources_verified = false;
        }
        if (error != nullptr) {
            *error = "WinDivert restore session does not match";
        }
        return false;
    }
    return StopLocked(resources_verified, error);
}

bool RoutingSession::Restore(
    bool* resources_verified,
    std::string* error)
{
    std::lock_guard<std::mutex> guard(state_mutex_);
    return StopLocked(resources_verified, error);
}

HANDLE RoutingSession::ProxyProcessHandle() const noexcept {
    std::lock_guard<std::mutex> guard(state_mutex_);
    return proxy_process_;
}

}  // namespace arvectum::windivert
