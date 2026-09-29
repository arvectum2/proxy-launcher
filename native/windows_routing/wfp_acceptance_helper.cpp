#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <fwpmu.h>
#include <mstcpip.h>

#include <array>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "routing_ioctl.h"
#include "wfp_resources.h"

#pragma comment(lib, "Fwpuclnt.lib")
#pragma comment(lib, "Ws2_32.lib")

namespace {
constexpr wchar_t kDevicePath[] = L"\\\\.\\ArvectumProxyRouting";

DWORD ConfigureDriver(DWORD proxy_pid, USHORT proxy_port, bool enabled) {
    HANDLE device = CreateFileW(
        kDevicePath,
        GENERIC_READ | GENERIC_WRITE,
        0,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
    if (device == INVALID_HANDLE_VALUE) {
        return GetLastError();
    }

    ARVECTUM_ROUTING_CONFIG config{};
    config.version = ARVECTUM_ROUTING_IOCTL_VERSION;
    config.enabled = enabled ? 1u : 0u;
    config.proxy_pid = proxy_pid;
    config.proxy_port = proxy_port;

    DWORD returned = 0;
    const BOOL ok = DeviceIoControl(
        device,
        IOCTL_ARVECTUM_ROUTING_SET_CONFIG,
        &config,
        sizeof(config),
        nullptr,
        0,
        &returned,
        nullptr);
    const DWORD result = ok ? ERROR_SUCCESS : GetLastError();
    CloseHandle(device);
    return result;
}
DWORD AddOwnedObjects(
    HANDLE engine,
    const wchar_t* executable_path,
    UINT64* filter_id)
{
    FWP_BYTE_BLOB* app_id = nullptr;
    DWORD status = FwpmGetAppIdFromFileName0(executable_path, &app_id);
    if (status != ERROR_SUCCESS || app_id == nullptr) {
        return status != ERROR_SUCCESS ? status : ERROR_INVALID_DATA;
    }

    status = FwpmTransactionBegin0(engine, 0);
    if (status != ERROR_SUCCESS) {
        FwpmFreeMemory0(reinterpret_cast<void**>(&app_id));
        return status;
    }

    FWPM_PROVIDER0 provider{};
    provider.providerKey = arvectum::routing::kProviderKey;
    provider.displayData.name =
        const_cast<wchar_t*>(arvectum::routing::kProviderName);
    provider.displayData.description =
        const_cast<wchar_t*>(L"Arvectum per-app routing acceptance provider");
    status = FwpmProviderAdd0(engine, &provider, nullptr);

    if (status == ERROR_SUCCESS) {
        FWPM_SUBLAYER0 sublayer{};
        sublayer.subLayerKey = arvectum::routing::kSublayerKey;
        sublayer.displayData.name =
            const_cast<wchar_t*>(arvectum::routing::kSublayerName);
        sublayer.providerKey =
            const_cast<GUID*>(&arvectum::routing::kProviderKey);
        sublayer.weight = 0x7000;
        status = FwpmSubLayerAdd0(engine, &sublayer, nullptr);
    }
    if (status == ERROR_SUCCESS) {
        FWPM_CALLOUT0 callout{};
        callout.calloutKey = arvectum::routing::kCalloutV4Key;
        callout.displayData.name =
            const_cast<wchar_t*>(arvectum::routing::kCalloutV4Name);
        callout.providerKey =
            const_cast<GUID*>(&arvectum::routing::kProviderKey);
        callout.applicableLayer = FWPM_LAYER_ALE_CONNECT_REDIRECT_V4;
        status = FwpmCalloutAdd0(engine, &callout, nullptr, nullptr);
    }

    if (status == ERROR_SUCCESS) {
        FWPM_FILTER_CONDITION0 conditions[2]{};
        conditions[0].fieldKey = FWPM_CONDITION_ALE_APP_ID;
        conditions[0].matchType = FWP_MATCH_EQUAL;
        conditions[0].conditionValue.type = FWP_BYTE_BLOB_TYPE;
        conditions[0].conditionValue.byteBlob = app_id;

        conditions[1].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
        conditions[1].matchType = FWP_MATCH_EQUAL;
        conditions[1].conditionValue.type = FWP_UINT8;
        conditions[1].conditionValue.uint8 = IPPROTO_TCP;

        FWPM_FILTER0 filter{};
        filter.displayData.name =
            const_cast<wchar_t*>(L"Arvectum.ProxyLauncher.AcceptanceRedirectV4");
        filter.providerKey =
            const_cast<GUID*>(&arvectum::routing::kProviderKey);
        filter.layerKey = FWPM_LAYER_ALE_CONNECT_REDIRECT_V4;
        filter.subLayerKey = arvectum::routing::kSublayerKey;
        filter.weight.type = FWP_EMPTY;
        filter.numFilterConditions = 2;
        filter.filterCondition = conditions;
        filter.action.type = FWP_ACTION_CALLOUT_TERMINATING;
        filter.action.calloutKey = arvectum::routing::kCalloutV4Key;
        status = FwpmFilterAdd0(engine, &filter, nullptr, filter_id);
    }
    if (status == ERROR_SUCCESS) {
        status = FwpmTransactionCommit0(engine);
    } else {
        FwpmTransactionAbort0(engine);
    }

    FwpmFreeMemory0(reinterpret_cast<void**>(&app_id));
    return status;
}


bool QueryRedirectData(
    SOCKET client,
    ARVECTUM_REDIRECT_CONTEXT* context,
    std::vector<unsigned char>* records)
{
    if (context == nullptr || records == nullptr) {
        return false;
    }
    records->assign(16384, 0);
    DWORD returned = 0;
    int result = WSAIoctl(
        client,
        SIO_QUERY_WFP_CONNECTION_REDIRECT_RECORDS,
        nullptr,
        0,
        records->data(),
        static_cast<DWORD>(records->size()),
        &returned,
        nullptr,
        nullptr);
    if (result == SOCKET_ERROR || returned == 0) {
        return false;
    }
    records->resize(returned);

    returned = 0;
    result = WSAIoctl(
        client,
        SIO_QUERY_WFP_CONNECTION_REDIRECT_CONTEXT,
        nullptr,
        0,
        context,
        sizeof(*context),
        &returned,
        nullptr,
        nullptr);
    return result != SOCKET_ERROR &&
        returned == sizeof(*context) &&
        context->magic == ARVECTUM_ROUTING_CONTEXT_MAGIC &&
        context->version == ARVECTUM_ROUTING_CONTEXT_VERSION;
}

std::wstring EndpointText(const SOCKADDR_STORAGE& storage) {
    wchar_t host[INET6_ADDRSTRLEN]{};
    USHORT port = 0;
    if (storage.ss_family == AF_INET) {
        const auto* address =
            reinterpret_cast<const SOCKADDR_IN*>(&storage);
        InetNtopW(
            AF_INET,
            const_cast<IN_ADDR*>(&address->sin_addr),
            host,
            INET6_ADDRSTRLEN);
        port = ntohs(address->sin_port);
    } else if (storage.ss_family == AF_INET6) {
        const auto* address =
            reinterpret_cast<const SOCKADDR_IN6*>(&storage);
        InetNtopW(
            AF_INET6,
            const_cast<IN6_ADDR*>(&address->sin6_addr),
            host,
            INET6_ADDRSTRLEN);
        port = ntohs(address->sin6_port);
    } else {
        return L"<unavailable>";
    }
    return std::wstring(host) + L":" + std::to_wstring(port);
}

bool RelayPair(SOCKET first, SOCKET second) {
    std::array<char, 65536> buffer{};
    for (;;) {
        fd_set reads;
        FD_ZERO(&reads);
        FD_SET(first, &reads);
        FD_SET(second, &reads);
        TIMEVAL timeout{30, 0};
        const int ready = select(0, &reads, nullptr, nullptr, &timeout);
        if (ready <= 0) {
            return ready == 0;
        }
        for (SOCKET source : {first, second}) {
            if (!FD_ISSET(source, &reads)) {
                continue;
            }
            SOCKET target = source == first ? second : first;
            const int received = recv(source, buffer.data(), static_cast<int>(buffer.size()), 0);
            if (received <= 0) {
                return true;
            }
            int sent_total = 0;
            while (sent_total < received) {
                const int sent = send(
                    target,
                    buffer.data() + sent_total,
                    received - sent_total,
                    0);
                if (sent <= 0) {
                    return false;
                }
                sent_total += sent;
            }
        }
    }
}

bool RelayRedirectedClient(SOCKET client) {
    ARVECTUM_REDIRECT_CONTEXT context{};
    std::vector<unsigned char> records;
    if (!QueryRedirectData(client, &context, &records)) {
        std::wcerr << L"redirect metadata query failed: " << WSAGetLastError() << L"\n";
        return false;
    }

    const bool has_metadata_original =
        (context.flags & ARVECTUM_REDIRECT_CONTEXT_HAS_METADATA_ORIGINAL) != 0 &&
        (context.metadata_original.ss_family == AF_INET ||
         context.metadata_original.ss_family == AF_INET6);
    const SOCKADDR_STORAGE& destination =
        has_metadata_original ? context.metadata_original : context.original_remote;
    const int family = destination.ss_family;
    if (family != AF_INET && family != AF_INET6) {
        return false;
    }
    std::wcout
        << L"ARVECTUM_WFP_REDIRECT_CONTEXT request_remote="
        << EndpointText(context.original_remote)
        << L" request_local=" << EndpointText(context.original_local)
        << L" metadata_original="
        << (has_metadata_original
                ? EndpointText(context.metadata_original)
                : std::wstring(L"<unavailable>"))
        << L" selected=" << EndpointText(destination)
        << L" records=" << records.size() << L"\n";
    std::wcout.flush();

    SOCKET outbound = WSASocketW(
        family,
        SOCK_STREAM,
        IPPROTO_TCP,
        nullptr,
        0,
        WSA_FLAG_OVERLAPPED);
    if (outbound == INVALID_SOCKET) {
        return false;
    }

    DWORD returned = 0;
    if (WSAIoctl(
            outbound,
            SIO_SET_WFP_CONNECTION_REDIRECT_RECORDS,
            records.data(),
            static_cast<DWORD>(records.size()),
            nullptr,
            0,
            &returned,
            nullptr,
            nullptr) == SOCKET_ERROR) {
        closesocket(outbound);
        return false;
    }

    const int address_length =
        family == AF_INET ? sizeof(SOCKADDR_IN) : sizeof(SOCKADDR_IN6);
    if (connect(
            outbound,
            reinterpret_cast<const sockaddr*>(&destination),
            address_length) == SOCKET_ERROR) {
        closesocket(outbound);
        return false;
    }

    std::wcout
        << L"ARVECTUM_WFP_REDIRECT_OBSERVED original="
        << EndpointText(destination)
        << L" records=" << records.size() << L"\n";

    const bool relayed = RelayPair(client, outbound);
    closesocket(outbound);
    return relayed;
}

int RunSelfRelay(const wchar_t* executable_path, unsigned long seconds) {
    WSADATA winsock{};
    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) {
        return 20;
    }

    SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) {
        WSACleanup();
        return 21;
    }
    SOCKADDR_IN bind_address{};
    bind_address.sin_family = AF_INET;
    bind_address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind_address.sin_port = 0;
    if (bind(listener, reinterpret_cast<sockaddr*>(&bind_address), sizeof(bind_address)) == SOCKET_ERROR ||
        listen(listener, 8) == SOCKET_ERROR) {
        closesocket(listener);
        WSACleanup();
        return 22;
    }
    int bind_length = sizeof(bind_address);
    if (getsockname(listener, reinterpret_cast<sockaddr*>(&bind_address), &bind_length) == SOCKET_ERROR) {
        closesocket(listener);
        WSACleanup();
        return 23;
    }
    const USHORT proxy_port = ntohs(bind_address.sin_port);

    FWPM_SESSION0 session{};
    session.flags = FWPM_SESSION_FLAG_DYNAMIC;
    session.displayData.name =
        const_cast<wchar_t*>(L"Arvectum per-app routing self-relay acceptance");
    HANDLE engine = nullptr;
    DWORD status = FwpmEngineOpen0(
        nullptr, RPC_C_AUTHN_WINNT, nullptr, &session, &engine);
    if (status != ERROR_SUCCESS) {
        closesocket(listener);
        WSACleanup();
        return 24;
    }

    UINT64 filter_id = 0;
    status = AddOwnedObjects(engine, executable_path, &filter_id);
    if (status != ERROR_SUCCESS) {
        FwpmEngineClose0(engine);
        closesocket(listener);
        WSACleanup();
        return 25;
    }
    status = ConfigureDriver(GetCurrentProcessId(), proxy_port, true);
    if (status != ERROR_SUCCESS) {
        FwpmEngineClose0(engine);
        closesocket(listener);
        WSACleanup();
        return 26;
    }

    std::wcout
        << L"ARVECTUM_WFP_SELF_RELAY_READY filter=" << filter_id
        << L" pid=" << GetCurrentProcessId()
        << L" port=" << proxy_port
        << L" seconds=" << seconds << L"\n";
    std::wcout.flush();

    fd_set reads;
    FD_ZERO(&reads);
    FD_SET(listener, &reads);
    TIMEVAL timeout{
        static_cast<long>(seconds),
        0
    };
    bool success = false;
    const int ready = select(0, &reads, nullptr, nullptr, &timeout);
    if (ready > 0) {
        SOCKET client = accept(listener, nullptr, nullptr);
        if (client != INVALID_SOCKET) {
            success = RelayRedirectedClient(client);
            closesocket(client);
        }
    }

    const DWORD disable_status = ConfigureDriver(0, 0, false);
    FwpmEngineClose0(engine);
    closesocket(listener);
    WSACleanup();
    if (disable_status != ERROR_SUCCESS) {
        return 27;
    }
    std::wcout << L"ARVECTUM_WFP_SELF_RELAY_RESTORED\n";
    return success ? 0 : 28;
}

int Usage() {
    std::wcerr
        << L"usage: ArvectumWfpAcceptance.exe <exe> <proxy-pid> <port> <seconds>\n"
        << L"   or: ArvectumWfpAcceptance.exe --self-relay <exe> <seconds>\n";
    return 2;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc == 4 && std::wstring(argv[1]) == L"--self-relay") {
        const unsigned long seconds = std::wcstoul(argv[3], nullptr, 10);
        if (seconds == 0 || seconds > 600) {
            return Usage();
        }
        return RunSelfRelay(argv[2], seconds);
    }
    if (argc != 5) {
        return Usage();
    }

    const wchar_t* executable_path = argv[1];
    const unsigned long proxy_pid = std::wcstoul(argv[2], nullptr, 10);
    const unsigned long proxy_port = std::wcstoul(argv[3], nullptr, 10);
    const unsigned long seconds = std::wcstoul(argv[4], nullptr, 10);
    if (proxy_pid == 0 || proxy_port == 0 || proxy_port > 65535 ||
        seconds == 0 || seconds > 600) {
        return Usage();
    }

    FWPM_SESSION0 session{};
    session.flags = FWPM_SESSION_FLAG_DYNAMIC;
    session.displayData.name =
        const_cast<wchar_t*>(L"Arvectum per-app routing acceptance session");

    HANDLE engine = nullptr;
    DWORD status = FwpmEngineOpen0(
        nullptr, RPC_C_AUTHN_WINNT, nullptr, &session, &engine);
    if (status != ERROR_SUCCESS) {
        std::wcerr << L"FwpmEngineOpen0 failed: " << status << L"\n";
        return 3;
    }

    UINT64 filter_id = 0;
    status = AddOwnedObjects(engine, executable_path, &filter_id);
    if (status != ERROR_SUCCESS) {
        std::wcerr << L"WFP object transaction failed: " << status << L"\n";
        FwpmEngineClose0(engine);
        return 4;
    }

    status = ConfigureDriver(
        static_cast<DWORD>(proxy_pid),
        static_cast<USHORT>(proxy_port),
        true);
    if (status != ERROR_SUCCESS) {
        std::wcerr << L"driver configuration failed: " << status << L"\n";
        FwpmEngineClose0(engine);
        return 5;
    }

    std::wcout
        << L"ARVECTUM_WFP_ACCEPTANCE_ACTIVE filter=" << filter_id
        << L" pid=" << proxy_pid
        << L" port=" << proxy_port
        << L" seconds=" << seconds << L"\n";
    Sleep(static_cast<DWORD>(seconds * 1000));

    const DWORD disable_status = ConfigureDriver(0, 0, false);
    FwpmEngineClose0(engine);
    if (disable_status != ERROR_SUCCESS) {
        std::wcerr
            << L"driver disable failed: " << disable_status << L"\n";
        return 6;
    }
    std::wcout << L"ARVECTUM_WFP_ACCEPTANCE_RESTORED\n";
    return 0;
}
