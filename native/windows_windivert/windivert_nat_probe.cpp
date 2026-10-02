#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cwctype>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>

#include "windivert.h"

namespace {

constexpr INT16 kSocketPriority = 2000;
constexpr INT16 kNetworkPriority = 1900;

std::atomic<bool> g_stop{false};
std::atomic<std::uint64_t> g_selected_connects{0};
std::atomic<std::uint64_t> g_redirected_outbound{0};
std::atomic<std::uint64_t> g_rewritten_return{0};
std::atomic<std::uint64_t> g_unmatched_proxy_packets{0};
std::mutex g_ports_mutex;
std::unordered_set<UINT16> g_selected_ports;

std::wstring NormalizePath(std::wstring value) {
    std::replace(value.begin(), value.end(), L'/', L'\\');
    DWORD required = GetFullPathNameW(value.c_str(), 0, nullptr, nullptr);
    if (required != 0) {
        std::wstring full(required, L'\0');
        DWORD written = GetFullPathNameW(
            value.c_str(), required, full.data(), nullptr);
        if (written != 0 && written < required) {
            full.resize(written);
            value.swap(full);
        }
    }
    std::transform(
        value.begin(), value.end(), value.begin(),
        [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
    return value;
}

bool ProcessPathMatches(UINT32 pid, const std::wstring& selected) {
    HANDLE process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (process == nullptr) {
        return false;
    }
    std::wstring path(32768, L'\0');
    DWORD length = static_cast<DWORD>(path.size());
    const BOOL ok = QueryFullProcessImageNameW(
        process, 0, path.data(), &length);
    CloseHandle(process);
    if (!ok || length == 0) {
        return false;
    }
    path.resize(length);
    return NormalizePath(path) == selected;
}

bool IsSelectedPort(UINT16 port) {
    std::lock_guard<std::mutex> guard(g_ports_mutex);
    return g_selected_ports.find(port) != g_selected_ports.end();
}

void AddSelectedPort(UINT16 port) {
    std::lock_guard<std::mutex> guard(g_ports_mutex);
    g_selected_ports.insert(port);
}

void RemoveSelectedPort(UINT16 port) {
    std::lock_guard<std::mutex> guard(g_ports_mutex);
    g_selected_ports.erase(port);
}

void SocketLoop(
    HANDLE handle,
    const std::wstring& selected_path,
    UINT16 proxy_port)
{
    while (!g_stop.load()) {
        WINDIVERT_ADDRESS address{};
        if (!WinDivertRecv(handle, nullptr, 0, nullptr, &address)) {
            if (g_stop.load()) {
                break;
            }
            std::cerr << "socket recv failed=" << GetLastError() << "\n";
            continue;
        }
        const auto& socket = address.Socket;
        if (socket.Protocol != IPPROTO_TCP ||
            socket.RemotePort != proxy_port ||
            socket.LocalPort == 0) {
            continue;
        }
        if (address.Event == WINDIVERT_EVENT_SOCKET_CONNECT) {
            if (ProcessPathMatches(socket.ProcessId, selected_path)) {
                AddSelectedPort(socket.LocalPort);
                ++g_selected_connects;
                std::cout
                    << "SELECT pid=" << socket.ProcessId
                    << " local_port=" << socket.LocalPort
                    << " proxy_port=" << socket.RemotePort << "\n";
            }
        } else if (address.Event == WINDIVERT_EVENT_SOCKET_CLOSE) {
            RemoveSelectedPort(socket.LocalPort);
        }
    }
}

bool RewriteTcpPort(
    PWINDIVERT_TCPHDR tcp,
    UINT16 proxy_port,
    UINT16 direct_port)
{
    const UINT16 src = WinDivertHelperNtohs(tcp->SrcPort);
    const UINT16 dst = WinDivertHelperNtohs(tcp->DstPort);
    if (dst == proxy_port) {
        if (!IsSelectedPort(src)) {
            ++g_unmatched_proxy_packets;
            return false;
        }
        tcp->DstPort = WinDivertHelperHtons(direct_port);
        ++g_redirected_outbound;
        return true;
    }
    if (src == direct_port && IsSelectedPort(dst)) {
        tcp->SrcPort = WinDivertHelperHtons(proxy_port);
        ++g_rewritten_return;
        return true;
    }
    return false;
}

void NetworkLoop(
    HANDLE handle,
    UINT16 proxy_port,
    UINT16 direct_port)
{
    unsigned char packet[WINDIVERT_MTU_MAX];
    while (!g_stop.load()) {
        UINT packet_len = 0;
        WINDIVERT_ADDRESS address{};
        if (!WinDivertRecv(
                handle, packet, sizeof(packet), &packet_len, &address)) {
            if (g_stop.load()) {
                break;
            }
            std::cerr << "network recv failed=" << GetLastError() << "\n";
            continue;
        }
        PWINDIVERT_TCPHDR tcp = nullptr;
        if (!WinDivertHelperParsePacket(
                packet, packet_len, nullptr, nullptr, nullptr,
                nullptr, nullptr, &tcp, nullptr,
                nullptr, nullptr, nullptr, nullptr) ||
            tcp == nullptr) {
            WinDivertSend(handle, packet, packet_len, nullptr, &address);
            continue;
        }
        if (RewriteTcpPort(tcp, proxy_port, direct_port)) {
            WinDivertHelperCalcChecksums(
                packet, packet_len, &address, 0);
        }
        if (!WinDivertSend(
                handle, packet, packet_len, nullptr, &address)) {
            std::cerr << "network send failed=" << GetLastError() << "\n";
        }
    }
}

bool ParsePort(const wchar_t* text, UINT16* output) {
    if (text == nullptr || output == nullptr) {
        return false;
    }
    wchar_t* end = nullptr;
    const unsigned long value = std::wcstoul(text, &end, 10);
    if (end == text || *end != L'\0' || value == 0 || value > 65535) {
        return false;
    }
    *output = static_cast<UINT16>(value);
    return true;
}

std::string SocketFilter(UINT16 proxy_port) {
    return "loopback and tcp and remotePort == " +
        std::to_string(proxy_port) +
        " and (event == CONNECT or event == CLOSE)";
}

std::string NetworkFilter(UINT16 proxy_port, UINT16 direct_port) {
    return "loopback and tcp and (tcp.DstPort == " +
        std::to_string(proxy_port) +
        " or tcp.SrcPort == " + std::to_string(direct_port) + ")";
}

bool ValidateFilter(
    const std::string& filter,
    WINDIVERT_LAYER layer)
{
    const char* error = nullptr;
    UINT position = 0;
    if (WinDivertHelperCompileFilter(
            filter.c_str(), layer, nullptr, 0, &error, &position)) {
        return true;
    }
    std::cerr << "filter invalid position=" << position
              << " error=" << (error == nullptr ? "unknown" : error)
              << "\n";
    return false;
}

int Run(
    const std::wstring& selected_path,
    UINT16 proxy_port,
    UINT16 direct_port,
    DWORD duration_seconds)
{
    const std::string socket_filter = SocketFilter(proxy_port);
    const std::string network_filter =
        NetworkFilter(proxy_port, direct_port);

    HANDLE socket_handle = WinDivertOpen(
        socket_filter.c_str(),
        WINDIVERT_LAYER_SOCKET,
        kSocketPriority,
        WINDIVERT_FLAG_SNIFF | WINDIVERT_FLAG_RECV_ONLY);
    if (socket_handle == INVALID_HANDLE_VALUE) {
        std::cerr << "socket open failed=" << GetLastError() << "\n";
        return 10;
    }
    HANDLE network_handle = WinDivertOpen(
        network_filter.c_str(),
        WINDIVERT_LAYER_NETWORK,
        kNetworkPriority,
        0);
    if (network_handle == INVALID_HANDLE_VALUE) {
        std::cerr << "network open failed=" << GetLastError() << "\n";
        WinDivertClose(socket_handle);
        return 11;
    }

    std::thread socket_thread(
        SocketLoop, socket_handle, selected_path, proxy_port);
    std::thread network_thread(
        NetworkLoop, network_handle, proxy_port, direct_port);

    std::cout
        << "READY proxy_port=" << proxy_port
        << " direct_port=" << direct_port
        << " duration=" << duration_seconds << std::endl;
    Sleep(duration_seconds * 1000);
    g_stop.store(true);
    WinDivertShutdown(socket_handle, WINDIVERT_SHUTDOWN_BOTH);
    WinDivertShutdown(network_handle, WINDIVERT_SHUTDOWN_BOTH);
    socket_thread.join();
    network_thread.join();
    WinDivertClose(socket_handle);
    WinDivertClose(network_handle);

    std::cout
        << "RESULT selected_connects=" << g_selected_connects.load()
        << " redirected_outbound=" << g_redirected_outbound.load()
        << " rewritten_return=" << g_rewritten_return.load()
        << " unmatched_proxy_packets=" << g_unmatched_proxy_packets.load()
        << "\n";
    return 0;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc < 4 || argc > 5) {
        std::wcerr
            << L"usage: windivert_nat_probe.exe "
            << L"<selected-exe> <proxy-port> <direct-port> [seconds]\n"
            << L"       windivert_nat_probe.exe "
            << L"--validate-filters <proxy-port> <direct-port>\n";
        return 2;
    }
    UINT16 proxy_port = 0;
    UINT16 direct_port = 0;
    if (!ParsePort(argv[2], &proxy_port) ||
        !ParsePort(argv[3], &direct_port) ||
        proxy_port == direct_port) {
        std::cerr << "invalid ports\n";
        return 2;
    }
    if (std::wstring(argv[1]) == L"--validate-filters") {
        if (argc != 4 ||
            !ValidateFilter(
                SocketFilter(proxy_port),
                WINDIVERT_LAYER_SOCKET) ||
            !ValidateFilter(
                NetworkFilter(proxy_port, direct_port),
                WINDIVERT_LAYER_NETWORK)) {
            return 3;
        }
        std::cout << "FILTERS_VALID" << std::endl;
        return 0;
    }

    DWORD duration = 60;
    if (argc == 5) {
        wchar_t* end = nullptr;
        const unsigned long value = std::wcstoul(argv[4], &end, 10);
        if (end == argv[4] || *end != L'\0' ||
            value < 5 || value > 600) {
            std::cerr << "invalid duration\n";
            return 2;
        }
        duration = static_cast<DWORD>(value);
    }
    return Run(
        NormalizePath(argv[1]),
        proxy_port,
        direct_port,
        duration);
}
