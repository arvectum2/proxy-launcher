#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <fwpmu.h>

#include <cstdlib>
#include <iostream>
#include <string>

#include "routing_ioctl.h"
#include "wfp_resources.h"

#pragma comment(lib, "Fwpuclnt.lib")

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

int Usage() {
    std::wcerr
        << L"usage: ArvectumWfpAcceptance.exe <exe> <proxy-pid> <port> <seconds>\n";
    return 2;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
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
