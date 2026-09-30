#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <aclapi.h>
#include <fwpmu.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "routing_ioctl.h"
#include "routing_service_wfp.h"
#include "wfp_resources.h"

#pragma comment(lib, "Advapi32.lib")
#pragma comment(lib, "Fwpuclnt.lib")
#pragma comment(lib, "Ws2_32.lib")

namespace arvectum::routing {
namespace {

constexpr wchar_t kDevicePath[] = L"\\\\.\\ArvectumProxyRouting";
constexpr UINT8 kRedirectWeight = 8;
constexpr UINT8 kBypassWeight = 15;

std::string StatusError(const char* operation, DWORD status) {
    return std::string(operation) + " failed status " +
        std::to_string(static_cast<unsigned long>(status));
}

bool CopySidBytes(PSID sid, std::vector<unsigned char>* output) noexcept {
    if (sid == nullptr || output == nullptr || !IsValidSid(sid)) {
        return false;
    }
    const DWORD length = GetLengthSid(sid);
    output->resize(length);
    return CopySid(length, output->data(), sid) != FALSE;
}

DWORD OpenProxyProcessForCaller(
    std::uint32_t pid,
    PSID caller_sid,
    HANDLE* process_out) noexcept
{
    if (caller_sid == nullptr || process_out == nullptr || !IsValidSid(caller_sid)) {
        return ERROR_INVALID_SID;
    }
    *process_out = nullptr;
    HANDLE process = OpenProcess(
        PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
        FALSE,
        pid);
    if (process == nullptr) {
        return GetLastError();
    }
    HANDLE token = nullptr;
    if (!OpenProcessToken(process, TOKEN_QUERY, &token)) {
        const DWORD status = GetLastError();
        CloseHandle(process);
        return status;
    }
    DWORD required = 0;
    GetTokenInformation(token, TokenUser, nullptr, 0, &required);
    if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
        const DWORD status = GetLastError();
        CloseHandle(token);
        CloseHandle(process);
        return status;
    }
    std::vector<unsigned char> storage(required);
    if (!GetTokenInformation(
            token, TokenUser, storage.data(), required, &required)) {
        const DWORD status = GetLastError();
        CloseHandle(token);
        CloseHandle(process);
        return status;
    }
    const TOKEN_USER* user =
        reinterpret_cast<const TOKEN_USER*>(storage.data());
    const bool matches = EqualSid(user->User.Sid, caller_sid) != FALSE;
    CloseHandle(token);
    if (!matches) {
        CloseHandle(process);
        return ERROR_ACCESS_DENIED;
    }
    *process_out = process;
    return ERROR_SUCCESS;
}

DWORD BuildUserSecurityDescriptor(
    PSID caller_sid,
    std::vector<unsigned char>* storage,
    FWP_BYTE_BLOB* blob) noexcept
{
    if (caller_sid == nullptr || storage == nullptr || blob == nullptr ||
        !IsValidSid(caller_sid)) {
        return ERROR_INVALID_SID;
    }
    EXPLICIT_ACCESSW access{};
    access.grfAccessPermissions = FWP_ACTRL_MATCH_FILTER;
    access.grfAccessMode = GRANT_ACCESS;
    access.grfInheritance = NO_INHERITANCE;
    BuildTrusteeWithSidW(&access.Trustee, caller_sid);

    PACL acl = nullptr;
    DWORD status = SetEntriesInAclW(1, &access, nullptr, &acl);
    if (status != ERROR_SUCCESS) {
        return status;
    }
    SECURITY_DESCRIPTOR absolute{};
    if (!InitializeSecurityDescriptor(
            &absolute, SECURITY_DESCRIPTOR_REVISION) ||
        !SetSecurityDescriptorDacl(&absolute, TRUE, acl, FALSE)) {
        status = GetLastError();
        LocalFree(acl);
        return status;
    }
    DWORD required = 0;
    MakeSelfRelativeSD(&absolute, nullptr, &required);
    if (required == 0 || GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
        status = GetLastError();
        LocalFree(acl);
        return status;
    }
    storage->resize(required);
    if (!MakeSelfRelativeSD(
            &absolute,
            reinterpret_cast<PSECURITY_DESCRIPTOR>(storage->data()),
            &required)) {
        status = GetLastError();
        LocalFree(acl);
        return status;
    }
    LocalFree(acl);
    blob->size = required;
    blob->data = storage->data();
    return ERROR_SUCCESS;
}

DWORD ConfigureDriver(
    std::uint32_t proxy_pid,
    std::uint16_t proxy_port,
    bool enabled) noexcept
{
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
    config.proxy_pid = enabled ? proxy_pid : 0u;
    config.proxy_port = enabled ? proxy_port : 0u;
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
    const DWORD status = ok ? ERROR_SUCCESS : GetLastError();
    CloseHandle(device);
    return status;
}

bool ParsePrefix(
    const std::string& cidr,
    int family,
    FWP_V4_ADDR_AND_MASK* v4,
    FWP_V6_ADDR_AND_MASK* v6) noexcept
{
    const std::size_t slash = cidr.find('/');
    if (slash == std::string::npos || slash == 0 ||
        slash + 1 >= cidr.size()) {
        return false;
    }
    unsigned prefix = 0;
    for (std::size_t index = slash + 1; index < cidr.size(); ++index) {
        const unsigned char ch = static_cast<unsigned char>(cidr[index]);
        if (ch < '0' || ch > '9') {
            return false;
        }
        prefix = prefix * 10u + static_cast<unsigned>(ch - '0');
        if (prefix > 128u) {
            return false;
        }
    }
    const std::string address = cidr.substr(0, slash);
    std::wstring wide(address.begin(), address.end());
    if (family == AF_INET) {
        if (v4 == nullptr || prefix > 32u) {
            return false;
        }
        IN_ADDR parsed{};
        if (InetPtonW(AF_INET, wide.c_str(), &parsed) != 1) {
            return false;
        }
        v4->addr = ntohl(parsed.S_un.S_addr);
        v4->mask = prefix == 0
            ? 0u
            : static_cast<UINT32>(0xffffffffu << (32u - prefix));
        v4->addr &= v4->mask;
        return true;
    }
    if (family == AF_INET6) {
        if (v6 == nullptr || prefix > 128u) {
            return false;
        }
        IN6_ADDR parsed{};
        if (InetPtonW(AF_INET6, wide.c_str(), &parsed) != 1) {
            return false;
        }
        std::memcpy(v6->addr, parsed.u.Byte, sizeof(v6->addr));
        v6->prefixLength = static_cast<UINT8>(prefix);
        return true;
    }
    return false;
}

DWORD AddProviderAndCallouts(HANDLE engine) noexcept {
    FWPM_PROVIDER0 provider{};
    provider.providerKey = kProviderKey;
    provider.displayData.name = const_cast<wchar_t*>(kProviderName);
    provider.displayData.description =
        const_cast<wchar_t*>(L"Arvectum per-app routing provider");
    DWORD status = FwpmProviderAdd0(engine, &provider, nullptr);
    if (status != ERROR_SUCCESS) {
        return status;
    }

    FWPM_SUBLAYER0 sublayer{};
    sublayer.subLayerKey = kSublayerKey;
    sublayer.displayData.name = const_cast<wchar_t*>(kSublayerName);
    sublayer.providerKey = const_cast<GUID*>(&kProviderKey);
    sublayer.weight = 0x7000;
    status = FwpmSubLayerAdd0(engine, &sublayer, nullptr);
    if (status != ERROR_SUCCESS) {
        return status;
    }

    struct CalloutSpec {
        const GUID* key;
        wchar_t* name;
        const GUID* layer;
    };
    CalloutSpec callouts[] = {
        {&kCalloutV4Key, const_cast<wchar_t*>(kCalloutV4Name),
         &FWPM_LAYER_ALE_CONNECT_REDIRECT_V4},
        {&kCalloutV6Key, const_cast<wchar_t*>(kCalloutV6Name),
         &FWPM_LAYER_ALE_CONNECT_REDIRECT_V6},
    };
    for (const CalloutSpec& spec : callouts) {
        FWPM_CALLOUT0 callout{};
        callout.calloutKey = *spec.key;
        callout.displayData.name = spec.name;
        callout.providerKey = const_cast<GUID*>(&kProviderKey);
        callout.applicableLayer = *spec.layer;
        status = FwpmCalloutAdd0(engine, &callout, nullptr, nullptr);
        if (status != ERROR_SUCCESS) {
            return status;
        }
    }
    return ERROR_SUCCESS;
}

DWORD AddFilterForFamily(
    HANDLE engine,
    const ServiceFilterSpec& spec,
    unsigned short family,
    FWP_BYTE_BLOB* user_sd) noexcept
{
    const bool ipv4 = family == 4;
    if (!ipv4 && family != 6) {
        return ERROR_INVALID_PARAMETER;
    }
    FWP_BYTE_BLOB app_blob{};
    app_blob.size = static_cast<UINT32>(spec.application_id.size());
    app_blob.data = const_cast<UINT8*>(spec.application_id.data());

    if (user_sd == nullptr || user_sd->data == nullptr || user_sd->size == 0) {
        return ERROR_INVALID_SECURITY_DESCR;
    }

    std::array<FWPM_FILTER_CONDITION0, 5> conditions{};
    std::size_t count = 0;
    conditions[count].fieldKey = FWPM_CONDITION_ALE_USER_ID;
    conditions[count].matchType = FWP_MATCH_EQUAL;
    conditions[count].conditionValue.type = FWP_SECURITY_DESCRIPTOR_TYPE;
    conditions[count].conditionValue.sd = user_sd;
    ++count;

    conditions[count].fieldKey = FWPM_CONDITION_ALE_APP_ID;
    conditions[count].matchType = FWP_MATCH_EQUAL;
    conditions[count].conditionValue.type = FWP_BYTE_BLOB_TYPE;
    conditions[count].conditionValue.byteBlob = &app_blob;
    ++count;

    conditions[count].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
    conditions[count].matchType = FWP_MATCH_EQUAL;
    conditions[count].conditionValue.type = FWP_UINT8;
    conditions[count].conditionValue.uint8 = IPPROTO_TCP;
    ++count;

    FWP_V4_ADDR_AND_MASK v4{};
    FWP_V6_ADDR_AND_MASK v6{};
    if (spec.destination_kind == ServiceDestinationKind::kCidr) {
        const int af = ipv4 ? AF_INET : AF_INET6;
        if (!ParsePrefix(spec.destination_value, af, &v4, &v6)) {
            return ERROR_INVALID_PARAMETER;
        }
        conditions[count].fieldKey = FWPM_CONDITION_IP_REMOTE_ADDRESS;
        conditions[count].matchType = FWP_MATCH_EQUAL;
        if (ipv4) {
            conditions[count].conditionValue.type = FWP_V4_ADDR_MASK;
            conditions[count].conditionValue.v4AddrMask = &v4;
        } else {
            conditions[count].conditionValue.type = FWP_V6_ADDR_MASK;
            conditions[count].conditionValue.v6AddrMask = &v6;
        }
        ++count;
    }

    if (spec.remote_port != 0) {
        conditions[count].fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
        conditions[count].matchType = FWP_MATCH_EQUAL;
        conditions[count].conditionValue.type = FWP_UINT16;
        conditions[count].conditionValue.uint16 = spec.remote_port;
        ++count;
    }

    std::wstring name = L"Arvectum.ProxyLauncher.Rule.";
    name.append(spec.rule_id.begin(), spec.rule_id.end());
    name += ipv4 ? L".v4" : L".v6";

    UINT8 weight = spec.operation == ServiceFilterOperation::kBypass
        ? kBypassWeight : kRedirectWeight;
    FWPM_FILTER0 filter{};
    filter.displayData.name = const_cast<wchar_t*>(name.c_str());
    filter.providerKey = const_cast<GUID*>(&kProviderKey);
    filter.layerKey = ipv4
        ? FWPM_LAYER_ALE_CONNECT_REDIRECT_V4
        : FWPM_LAYER_ALE_CONNECT_REDIRECT_V6;
    filter.subLayerKey = kSublayerKey;
    filter.weight.type = FWP_UINT8;
    filter.weight.uint8 = weight;
    filter.numFilterConditions = static_cast<UINT32>(count);
    filter.filterCondition = conditions.data();
    if (spec.operation == ServiceFilterOperation::kBypass) {
        filter.action.type = FWP_ACTION_PERMIT;
    } else {
        filter.action.type = FWP_ACTION_CALLOUT_TERMINATING;
        filter.action.calloutKey = ipv4 ? kCalloutV4Key : kCalloutV6Key;
    }
    return FwpmFilterAdd0(engine, &filter, nullptr, nullptr);
}

DWORD AddPlan(
    HANDLE engine,
    const ServiceRequest& request,
    FWP_BYTE_BLOB* user_sd) noexcept
{
    DWORD status = FwpmTransactionBegin0(engine, 0);
    if (status != ERROR_SUCCESS) {
        return status;
    }
    status = AddProviderAndCallouts(engine);
    if (status == ERROR_SUCCESS) {
        for (const ServiceFilterSpec& spec : request.filters) {
            for (unsigned short family : spec.address_families) {
                status = AddFilterForFamily(engine, spec, family, user_sd);
                if (status != ERROR_SUCCESS) {
                    break;
                }
            }
            if (status != ERROR_SUCCESS) {
                break;
            }
        }
    }
    if (status == ERROR_SUCCESS) {
        status = FwpmTransactionCommit0(engine);
    } else {
        FwpmTransactionAbort0(engine);
    }
    return status;
}

bool VerifyAbsent(std::string* error) noexcept {
    HANDLE engine = nullptr;
    const DWORD open_status = OpenWfpEngine(&engine);
    if (open_status != ERROR_SUCCESS) {
        if (error != nullptr) {
            *error = StatusError("verify engine open", open_status);
        }
        return false;
    }

    FWPM_PROVIDER0* provider = nullptr;
    FWPM_SUBLAYER0* sublayer = nullptr;
    FWPM_CALLOUT0* callout = nullptr;
    DWORD status = FwpmProviderGetByKey0(engine, &kProviderKey, &provider);
    bool absent = status == FWP_E_PROVIDER_NOT_FOUND;
    if (provider != nullptr) {
        FwpmFreeMemory0(reinterpret_cast<void**>(&provider));
    }
    status = FwpmSubLayerGetByKey0(engine, &kSublayerKey, &sublayer);
    absent = absent && status == FWP_E_SUBLAYER_NOT_FOUND;
    if (sublayer != nullptr) {
        FwpmFreeMemory0(reinterpret_cast<void**>(&sublayer));
    }
    status = FwpmCalloutGetByKey0(engine, &kCalloutV4Key, &callout);
    absent = absent && status == FWP_E_CALLOUT_NOT_FOUND;
    if (callout != nullptr) {
        FwpmFreeMemory0(reinterpret_cast<void**>(&callout));
    }
    status = FwpmCalloutGetByKey0(engine, &kCalloutV6Key, &callout);
    absent = absent && status == FWP_E_CALLOUT_NOT_FOUND;
    if (callout != nullptr) {
        FwpmFreeMemory0(reinterpret_cast<void**>(&callout));
    }
    FwpmEngineClose0(engine);
    if (!absent && error != nullptr) {
        *error = "owned WFP resources remain";
    }
    return absent;
}

}  // namespace

RoutingWfpSession::RoutingWfpSession() noexcept
    : engine_(nullptr), proxy_process_(nullptr) {}

RoutingWfpSession::~RoutingWfpSession() {
    bool verified = false;
    std::string ignored;
    Restore(&verified, &ignored);
}

bool RoutingWfpSession::Apply(
    const ServiceRequest& request,
    PSID caller_sid,
    std::string* error) noexcept
{
    bool verified = false;
    std::string restore_error;
    if (!Restore(&verified, &restore_error) || !verified) {
        if (error != nullptr) {
            *error = restore_error.empty()
                ? "previous WFP state could not be restored"
                : restore_error;
        }
        return false;
    }

    HANDLE proxy_process = nullptr;
    DWORD status = OpenProxyProcessForCaller(
        request.proxy_pid, caller_sid, &proxy_process);
    if (status != ERROR_SUCCESS) {
        if (error != nullptr) {
            *error = StatusError("proxy process ownership validation", status);
        }
        return false;
    }

    std::vector<unsigned char> security_descriptor;
    FWP_BYTE_BLOB user_sd{};
    status = BuildUserSecurityDescriptor(
        caller_sid, &security_descriptor, &user_sd);
    if (status != ERROR_SUCCESS) {
        CloseHandle(proxy_process);
        if (error != nullptr) {
            *error = StatusError("user security descriptor", status);
        }
        return false;
    }

    FWPM_SESSION0 session{};
    session.flags = FWPM_SESSION_FLAG_DYNAMIC;
    session.displayData.name =
        const_cast<wchar_t*>(L"Arvectum Proxy Launcher routing session");
    HANDLE engine = nullptr;
    status = FwpmEngineOpen0(
        nullptr, RPC_C_AUTHN_WINNT, nullptr, &session, &engine);
    if (status != ERROR_SUCCESS) {
        CloseHandle(proxy_process);
        if (error != nullptr) {
            *error = StatusError("WFP engine open", status);
        }
        return false;
    }

    status = AddPlan(engine, request, &user_sd);
    if (status != ERROR_SUCCESS) {
        FwpmEngineClose0(engine);
        CloseHandle(proxy_process);
        if (error != nullptr) {
            *error = StatusError("WFP plan transaction", status);
        }
        return false;
    }
    status = ConfigureDriver(request.proxy_pid, request.proxy_port, true);
    if (status != ERROR_SUCCESS || WaitForSingleObject(proxy_process, 0) != WAIT_TIMEOUT) {
        FwpmEngineClose0(engine);
        ConfigureDriver(0, 0, false);
        CloseHandle(proxy_process);
        if (error != nullptr) {
            *error = status == ERROR_SUCCESS
                ? "proxy process exited during routing activation"
                : StatusError("driver configuration", status);
        }
        return false;
    }
    if (!CopySidBytes(caller_sid, &owner_sid_)) {
        FwpmEngineClose0(engine);
        ConfigureDriver(0, 0, false);
        CloseHandle(proxy_process);
        if (error != nullptr) {
            *error = "failed to persist routing owner SID";
        }
        return false;
    }
    engine_ = engine;
    proxy_process_ = proxy_process;
    return true;
}

bool RoutingWfpSession::RestoreForCaller(
    PSID caller_sid,
    bool* resources_verified,
    std::string* error) noexcept
{
    if (engine_ != nullptr) {
        if (caller_sid == nullptr || !IsValidSid(caller_sid) ||
            owner_sid_.empty() ||
            !EqualSid(owner_sid_.data(), caller_sid)) {
            if (error != nullptr) {
                *error = "active routing session belongs to another user";
            }
            if (resources_verified != nullptr) {
                *resources_verified = false;
            }
            return false;
        }
    }
    return Restore(resources_verified, error);
}

HANDLE RoutingWfpSession::ProxyProcessHandle() const noexcept {
    return proxy_process_;
}

bool RoutingWfpSession::Restore(
    bool* resources_verified,
    std::string* error) noexcept
{
    if (resources_verified != nullptr) {
        *resources_verified = false;
    }
    DWORD disable_status = ConfigureDriver(0, 0, false);
    if (disable_status == ERROR_FILE_NOT_FOUND ||
        disable_status == ERROR_PATH_NOT_FOUND) {
        disable_status = ERROR_SUCCESS;
    }
    if (engine_ != nullptr) {
        FwpmEngineClose0(static_cast<HANDLE>(engine_));
        engine_ = nullptr;
    }
    if (proxy_process_ != nullptr) {
        CloseHandle(proxy_process_);
        proxy_process_ = nullptr;
    }
    owner_sid_.clear();
    std::string verify_error;
    const bool absent = VerifyAbsent(&verify_error);
    if (resources_verified != nullptr) {
        *resources_verified = absent;
    }
    if (disable_status != ERROR_SUCCESS) {
        if (error != nullptr) {
            *error = StatusError("driver disable", disable_status);
        }
        return false;
    }
    if (!absent) {
        if (error != nullptr) {
            *error = verify_error;
        }
        return false;
    }
    return true;
}

}  // namespace arvectum::routing
