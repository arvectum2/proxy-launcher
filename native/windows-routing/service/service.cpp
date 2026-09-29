#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>
#include <sddl.h>
#include <shlobj.h>
#include <winsvc.h>
#include <ws2tcpip.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <mutex>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include <initguid.h>
#include "../include/arvectum_routing_guids.h"

using winrt::Windows::Data::Json::JsonArray;
using winrt::Windows::Data::Json::JsonObject;
using winrt::Windows::Data::Json::JsonValue;

namespace {
constexpr wchar_t kServiceName[] = L"ArvectumProxyRouting";
constexpr wchar_t kDriverServiceName[] = L"ArvectumProxyRoutingDriver";
constexpr wchar_t kPipeName[] = LR"(\\.\pipe\Arvectum.ProxyLauncher.Routing.v1)";
constexpr wchar_t kRegistryKey[] = L"SOFTWARE\\Arvectum\\ProxyLauncher\\Routing";
constexpr wchar_t kOwnerSidValue[] = L"OwnerSid";
constexpr wchar_t kProtocolSchema[] = L"arvectum.windows.routing-ipc.v1";
constexpr wchar_t kPlanSchema[] = L"arvectum.windows.app-routing.v1";
constexpr size_t kMaxMessage = 64 * 1024;
constexpr size_t kMaxRedirects = 256;
constexpr DWORD kIoTimeoutMs = 5000;
constexpr wchar_t kResourcePrefix[] = L"Arvectum.ProxyLauncher.AppExclusion.";

SERVICE_STATUS_HANDLE g_statusHandle = nullptr;
SERVICE_STATUS g_status{};
HANDLE g_stopEvent = nullptr;
HANDLE g_engine = nullptr;
std::mutex g_filterMutex;
std::vector<std::pair<std::wstring, UINT64>> g_filters;
std::wstring g_sessionId;
std::wstring g_ownerSid;

struct Win32Error : std::runtime_error {
    explicit Win32Error(const char* what, DWORD code = GetLastError())
        : std::runtime_error(std::string(what) + " (win32=" + std::to_string(code) + ")"), code(code) {}
    DWORD code;
};

std::wstring ToWide(const std::string& value) {
    if (value.empty()) return {};
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                                    static_cast<int>(value.size()), nullptr, 0);
    if (count <= 0) throw Win32Error("invalid UTF-8");
    std::wstring out(static_cast<size_t>(count), L'\0');
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), out.data(), count) != count) {
        throw Win32Error("UTF-8 conversion failed");
    }
    return out;
}

std::string ToUtf8(const std::wstring& value) {
    if (value.empty()) return {};
    int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                                    static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (count <= 0) throw Win32Error("UTF-8 conversion failed");
    std::string out(static_cast<size_t>(count), '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), out.data(), count, nullptr, nullptr) != count) {
        throw Win32Error("UTF-8 conversion failed");
    }
    return out;
}

std::wstring CanonicalSid(const std::wstring& input) {
    PSID sid = nullptr;
    if (!ConvertStringSidToSidW(input.c_str(), &sid)) {
        throw Win32Error("invalid owner SID");
    }
    LPWSTR canonical = nullptr;
    std::wstring out;
    if (!ConvertSidToStringSidW(sid, &canonical)) {
        LocalFree(sid);
        throw Win32Error("could not canonicalize owner SID");
    }
    out = canonical;
    LocalFree(canonical);
    LocalFree(sid);
    return out;
}

void WriteOwnerSid(const std::wstring& sid) {
    HKEY key = nullptr;
    DWORD disposition = 0;
    LONG rc = RegCreateKeyExW(HKEY_LOCAL_MACHINE, kRegistryKey, 0, nullptr, 0,
                              KEY_SET_VALUE, nullptr, &key, &disposition);
    if (rc != ERROR_SUCCESS) throw Win32Error("could not open routing registry key", rc);
    const DWORD bytes = static_cast<DWORD>((sid.size() + 1) * sizeof(wchar_t));
    rc = RegSetValueExW(key, kOwnerSidValue, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(sid.c_str()), bytes);
    RegCloseKey(key);
    if (rc != ERROR_SUCCESS) throw Win32Error("could not store routing owner SID", rc);
}

std::wstring ReadOwnerSid() {
    HKEY key = nullptr;
    LONG rc = RegOpenKeyExW(HKEY_LOCAL_MACHINE, kRegistryKey, 0, KEY_QUERY_VALUE, &key);
    if (rc != ERROR_SUCCESS) throw Win32Error("routing owner SID is not configured", rc);
    DWORD type = 0;
    DWORD bytes = 0;
    rc = RegQueryValueExW(key, kOwnerSidValue, nullptr, &type, nullptr, &bytes);
    if (rc != ERROR_SUCCESS || type != REG_SZ || bytes < sizeof(wchar_t) || bytes > 4096) {
        RegCloseKey(key);
        throw Win32Error("routing owner SID registry value is invalid", rc);
    }
    std::vector<wchar_t> buffer(bytes / sizeof(wchar_t) + 1, L'\0');
    rc = RegQueryValueExW(key, kOwnerSidValue, nullptr, &type,
                          reinterpret_cast<BYTE*>(buffer.data()), &bytes);
    RegCloseKey(key);
    if (rc != ERROR_SUCCESS) throw Win32Error("could not read routing owner SID", rc);
    return CanonicalSid(buffer.data());
}

std::filesystem::path ModuleDirectory() {
    std::vector<wchar_t> buffer(32768);
    DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0 || length >= buffer.size()) throw Win32Error("GetModuleFileNameW failed");
    return std::filesystem::path(std::wstring(buffer.data(), length)).parent_path();
}


std::filesystem::path ProtectedInstallDirectory() {
    PWSTR programFiles = nullptr;
    HRESULT hr = SHGetKnownFolderPath(FOLDERID_ProgramFiles, KF_FLAG_DEFAULT, nullptr, &programFiles);
    if (FAILED(hr) || programFiles == nullptr)
        throw std::runtime_error("Program Files location is unavailable");
    std::filesystem::path result(programFiles);
    CoTaskMemFree(programFiles);
    result /= L"Arvectum";
    result /= L"Proxy Launcher";
    result /= L"Routing";
    return result;
}

void CopyNativePayloadToProtectedDirectory(
    std::filesystem::path* serviceOut,
    std::filesystem::path* driverOut)
{
    const auto sourceDir = ModuleDirectory();
    const auto sourceService = sourceDir / L"ArvectumRoutingService.exe";
    const auto sourceDriver = sourceDir / L"ArvectumProxyRouting.sys";
    if (!std::filesystem::is_regular_file(sourceService))
        throw std::runtime_error("ArvectumRoutingService.exe source is missing");
    if (!std::filesystem::is_regular_file(sourceDriver))
        throw std::runtime_error("ArvectumProxyRouting.sys is missing next to the service executable");

    const auto destination = ProtectedInstallDirectory();
    std::filesystem::create_directories(destination);
    const auto service = destination / L"ArvectumRoutingService.exe";
    const auto driver = destination / L"ArvectumProxyRouting.sys";
    std::filesystem::copy_file(
        sourceService, service, std::filesystem::copy_options::overwrite_existing);
    std::filesystem::copy_file(
        sourceDriver, driver, std::filesystem::copy_options::overwrite_existing);
    *serviceOut = service;
    *driverOut = driver;
}

SC_HANDLE CreateOrUpdateService(
    SC_HANDLE scm,
    const wchar_t* name,
    const wchar_t* displayName,
    DWORD serviceType,
    DWORD startType,
    const std::wstring& quotedBinaryPath)
{
    SC_HANDLE service = CreateServiceW(
        scm, name, displayName,
        SERVICE_START | SERVICE_STOP | DELETE | SERVICE_QUERY_STATUS | SERVICE_CHANGE_CONFIG,
        serviceType, startType, SERVICE_ERROR_NORMAL,
        quotedBinaryPath.c_str(), nullptr, nullptr, nullptr, nullptr, nullptr);
    if (service != nullptr) return service;
    if (GetLastError() != ERROR_SERVICE_EXISTS)
        throw Win32Error("CreateServiceW failed");

    service = OpenServiceW(
        scm, name,
        SERVICE_START | SERVICE_STOP | DELETE | SERVICE_QUERY_STATUS | SERVICE_CHANGE_CONFIG);
    if (!service) throw Win32Error("OpenServiceW(existing) failed");
    if (!ChangeServiceConfigW(
            service, serviceType, startType, SERVICE_ERROR_NORMAL,
            quotedBinaryPath.c_str(), nullptr, nullptr, nullptr, nullptr, nullptr, displayName)) {
        DWORD error = GetLastError();
        CloseServiceHandle(service);
        throw Win32Error("ChangeServiceConfigW failed", error);
    }
    return service;
}

void SetServiceState(DWORD state, DWORD win32Exit = NO_ERROR, DWORD waitHint = 0) {
    g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_status.dwCurrentState = state;
    g_status.dwControlsAccepted = state == SERVICE_RUNNING ? SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN : 0;
    g_status.dwWin32ExitCode = win32Exit;
    g_status.dwWaitHint = waitHint;
    g_status.dwCheckPoint = 0;
    if (g_statusHandle) SetServiceStatus(g_statusHandle, &g_status);
}

bool StartKernelDriver() {
    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scm) return false;
    SC_HANDLE service = OpenServiceW(scm, kDriverServiceName, SERVICE_START | SERVICE_QUERY_STATUS);
    if (!service) {
        CloseServiceHandle(scm);
        return false;
    }
    BOOL started = StartServiceW(service, 0, nullptr);
    DWORD error = started ? ERROR_SUCCESS : GetLastError();
    bool ok = started || error == ERROR_SERVICE_ALREADY_RUNNING;
    CloseServiceHandle(service);
    CloseServiceHandle(scm);
    return ok;
}

void InitializeWfp() {
    FWPM_SESSION0 session{};
    session.displayData.name = const_cast<wchar_t*>(L"Arvectum Proxy Launcher routing session");
    session.flags = FWPM_SESSION_FLAG_DYNAMIC;
    DWORD result = FwpmEngineOpen0(nullptr, RPC_C_AUTHN_WINNT, nullptr, &session, &g_engine);
    if (result != ERROR_SUCCESS) throw Win32Error("FwpmEngineOpen0 failed", result);

    FWPM_PROVIDER0 provider{};
    provider.providerKey = ARVECTUM_ROUTING_PROVIDER;
    provider.displayData.name = const_cast<wchar_t*>(L"Arvectum Proxy Launcher");
    provider.displayData.description =
        const_cast<wchar_t*>(L"Owned provider for per-application proxy routing");
    result = FwpmProviderAdd0(g_engine, &provider, nullptr);
    if (result != ERROR_SUCCESS && result != FWP_E_ALREADY_EXISTS)
        throw Win32Error("FwpmProviderAdd0 failed", result);

    FWPM_SUBLAYER0 sublayer{};
    sublayer.subLayerKey = ARVECTUM_ROUTING_SUBLAYER;
    sublayer.displayData.name = const_cast<wchar_t*>(L"Arvectum application routing");
    sublayer.providerKey = const_cast<GUID*>(&ARVECTUM_ROUTING_PROVIDER);
    sublayer.weight = 0x200;
    result = FwpmSubLayerAdd0(g_engine, &sublayer, nullptr);
    if (result != ERROR_SUCCESS && result != FWP_E_ALREADY_EXISTS)
        throw Win32Error("FwpmSubLayerAdd0 failed", result);

    FWPM_CALLOUT0 callout{};
    callout.calloutKey = ARVECTUM_CONNECT_REDIRECT_V4_CALLOUT;
    callout.displayData.name = const_cast<wchar_t*>(L"Arvectum loopback proxy redirect");
    callout.providerKey = const_cast<GUID*>(&ARVECTUM_ROUTING_PROVIDER);
    callout.applicableLayer = FWPM_LAYER_ALE_CONNECT_REDIRECT_V4;
    result = FwpmCalloutAdd0(g_engine, &callout, nullptr, nullptr);
    if (result != ERROR_SUCCESS && result != FWP_E_ALREADY_EXISTS)
        throw Win32Error("FwpmCalloutAdd0 failed", result);
}

void CloseWfp() {
    if (g_engine) {
        FwpmEngineClose0(g_engine);
        g_engine = nullptr;
    }
    std::lock_guard<std::mutex> lock(g_filterMutex);
    g_filters.clear();
    g_sessionId.clear();
}

uint16_t JsonPort(const JsonObject& object, const wchar_t* key) {
    double number = object.GetNamedNumber(key);
    if (number < 1 || number > 65535 || number != static_cast<double>(static_cast<uint16_t>(number)))
        throw std::runtime_error("port outside 1..65535");
    return static_cast<uint16_t>(number);
}

std::vector<uint8_t> HexToBytes(const std::wstring& value) {
    if (value.empty() || (value.size() & 1u) != 0 || value.size() > 8192)
        throw std::runtime_error("invalid WFP application id hex length");
    auto nibble = [](wchar_t c) -> int {
        if (c >= L'0' && c <= L'9') return c - L'0';
        if (c >= L'a' && c <= L'f') return 10 + c - L'a';
        if (c >= L'A' && c <= L'F') return 10 + c - L'A';
        return -1;
    };
    std::vector<uint8_t> out(value.size() / 2);
    for (size_t i = 0; i < out.size(); ++i) {
        int high = nibble(value[i * 2]);
        int low = nibble(value[i * 2 + 1]);
        if (high < 0 || low < 0) throw std::runtime_error("invalid WFP application id hex");
        out[i] = static_cast<uint8_t>((high << 4) | low);
    }
    return out;
}

bool ValidResourceId(const std::wstring& value) {
    if (value.size() < 32 || value.size() > 128 ||
        value.rfind(kResourcePrefix, 0) != 0) return false;
    return std::all_of(value.begin(), value.end(), [](wchar_t c) {
        return (c >= L'A' && c <= L'Z') || (c >= L'a' && c <= L'z') ||
               (c >= L'0' && c <= L'9') || c == L'.' || c == L'-' || c == L'_';
    });
}

struct ParsedRedirect {
    std::wstring resourceId;
    std::vector<uint8_t> appId;
    uint16_t sourcePort{};
    uint16_t directPort{};
};

std::vector<ParsedRedirect> ParsePlan(const JsonObject& plan) {
    if (plan.GetNamedString(L"schema") != kPlanSchema ||
        plan.GetNamedString(L"mode") != L"application_exclusion_direct") {
        throw std::runtime_error("unsupported routing plan schema/mode");
    }
    JsonArray redirects = plan.GetNamedArray(L"redirects");
    if (redirects.Size() == 0 || redirects.Size() > kMaxRedirects)
        throw std::runtime_error("routing redirect count is outside protocol limits");

    std::set<std::wstring> resources;
    std::vector<ParsedRedirect> parsed;
    parsed.reserve(redirects.Size());
    for (uint32_t i = 0; i < redirects.Size(); ++i) {
        JsonObject item = redirects.GetObjectAt(i);
        std::wstring resource = item.GetNamedString(L"resource_id").c_str();
        if (!ValidResourceId(resource) || !resources.insert(resource).second)
            throw std::runtime_error("routing resource id is invalid or duplicated");
        if (item.GetNamedString(L"remote_address") != L"127.0.0.1" ||
            item.GetNamedString(L"transport") != L"tcp" ||
            item.GetNamedString(L"family") != L"ipv4") {
            throw std::runtime_error("routing plan attempted a non-loopback/non-TCP redirect");
        }
        std::wstring kind = item.GetNamedString(L"proxy_kind").c_str();
        if (kind != L"http" && kind != L"socks5")
            throw std::runtime_error("unsupported proxy kind");
        uint16_t sourcePort = JsonPort(item, L"source_proxy_port");
        uint16_t directPort = JsonPort(item, L"direct_port");
        if (sourcePort == directPort)
            throw std::runtime_error("source/direct proxy ports collide");

        ParsedRedirect redirect;
        redirect.resourceId = std::move(resource);
        redirect.appId = HexToBytes(item.GetNamedString(L"app_id_hex").c_str());
        redirect.sourcePort = sourcePort;
        redirect.directPort = directPort;
        parsed.push_back(std::move(redirect));
    }
    return parsed;
}

UINT64 AddFilter(const ParsedRedirect& redirect) {
    FWP_BYTE_BLOB appBlob{};
    appBlob.size = static_cast<UINT32>(redirect.appId.size());
    appBlob.data = const_cast<UINT8*>(redirect.appId.data());

    FWPM_FILTER_CONDITION0 conditions[4]{};
    conditions[0].fieldKey = FWPM_CONDITION_ALE_APP_ID;
    conditions[0].matchType = FWP_MATCH_EQUAL;
    conditions[0].conditionValue.type = FWP_BYTE_BLOB_TYPE;
    conditions[0].conditionValue.byteBlob = &appBlob;

    conditions[1].fieldKey = FWPM_CONDITION_IP_REMOTE_ADDRESS;
    conditions[1].matchType = FWP_MATCH_EQUAL;
    conditions[1].conditionValue.type = FWP_UINT32;
    conditions[1].conditionValue.uint32 = 0x7F000001u;  // host-order 127.0.0.1

    conditions[2].fieldKey = FWPM_CONDITION_IP_REMOTE_PORT;
    conditions[2].matchType = FWP_MATCH_EQUAL;
    conditions[2].conditionValue.type = FWP_UINT16;
    conditions[2].conditionValue.uint16 = redirect.sourcePort;

    conditions[3].fieldKey = FWPM_CONDITION_IP_PROTOCOL;
    conditions[3].matchType = FWP_MATCH_EQUAL;
    conditions[3].conditionValue.type = FWP_UINT8;
    conditions[3].conditionValue.uint8 = IPPROTO_TCP;

    FWPM_FILTER0 filter{};
    filter.displayData.name = const_cast<wchar_t*>(redirect.resourceId.c_str());
    filter.providerKey = const_cast<GUID*>(&ARVECTUM_ROUTING_PROVIDER);
    filter.layerKey = FWPM_LAYER_ALE_CONNECT_REDIRECT_V4;
    filter.subLayerKey = ARVECTUM_ROUTING_SUBLAYER;
    filter.action.type = FWP_ACTION_CALLOUT_TERMINATING;
    filter.action.calloutKey = ARVECTUM_CONNECT_REDIRECT_V4_CALLOUT;
    filter.filterCondition = conditions;
    filter.numFilterConditions = ARRAYSIZE(conditions);
    filter.rawContext = redirect.directPort;
    filter.weight.type = FWP_EMPTY;

    UINT64 id = 0;
    DWORD result = FwpmFilterAdd0(g_engine, &filter, nullptr, &id);
    if (result != ERROR_SUCCESS) throw Win32Error("FwpmFilterAdd0 failed", result);
    return id;
}

JsonObject BaseReply(bool ok) {
    JsonObject reply;
    reply.Insert(L"schema", JsonValue::CreateStringValue(kProtocolSchema));
    reply.Insert(L"ok", JsonValue::CreateBooleanValue(ok));
    return reply;
}

JsonObject HandleApply(const JsonObject& request) {
    std::wstring session = request.GetNamedString(L"session_id").c_str();
    if (session.size() < 16 || session.size() > 64)
        throw std::runtime_error("invalid routing session id");
    std::vector<ParsedRedirect> redirects = ParsePlan(request.GetNamedObject(L"plan"));

    std::lock_guard<std::mutex> lock(g_filterMutex);
    if (!g_filters.empty())
        throw std::runtime_error("an application-routing session is already active");

    DWORD result = FwpmTransactionBegin0(g_engine, 0);
    if (result != ERROR_SUCCESS) throw Win32Error("FwpmTransactionBegin0 failed", result);

    std::vector<std::pair<std::wstring, UINT64>> pending;
    try {
        for (const auto& redirect : redirects)
            pending.emplace_back(redirect.resourceId, AddFilter(redirect));
        result = FwpmTransactionCommit0(g_engine);
        if (result != ERROR_SUCCESS) throw Win32Error("FwpmTransactionCommit0 failed", result);
    } catch (...) {
        FwpmTransactionAbort0(g_engine);
        throw;
    }

    g_filters = std::move(pending);
    g_sessionId = session;
    JsonObject reply = BaseReply(true);
    reply.Insert(L"filters", JsonValue::CreateNumberValue(static_cast<double>(g_filters.size())));
    return reply;
}

JsonObject HandleRestore(const JsonObject& request) {
    std::wstring session = request.GetNamedString(L"session_id").c_str();
    JsonArray requested = request.GetNamedArray(L"resource_ids");
    if (requested.Size() > kMaxRedirects)
        throw std::runtime_error("restore resource count exceeds protocol limit");

    std::set<std::wstring> requestedIds;
    for (uint32_t i = 0; i < requested.Size(); ++i) {
        std::wstring id = requested.GetStringAt(i).c_str();
        if (!ValidResourceId(id) || !requestedIds.insert(id).second)
            throw std::runtime_error("invalid restore resource id");
    }

    std::lock_guard<std::mutex> lock(g_filterMutex);
    if (!g_filters.empty() && session != g_sessionId)
        throw std::runtime_error("restore session does not own active routing filters");

    for (auto it = g_filters.begin(); it != g_filters.end();) {
        if (requestedIds.count(it->first) == 0) {
            ++it;
            continue;
        }
        DWORD result = FwpmFilterDeleteById0(g_engine, it->second);
        if (result != ERROR_SUCCESS && result != FWP_E_FILTER_NOT_FOUND)
            throw Win32Error("FwpmFilterDeleteById0 failed", result);
        it = g_filters.erase(it);
    }
    if (g_filters.empty()) g_sessionId.clear();

    JsonObject reply = BaseReply(true);
    reply.Insert(L"remaining_resources",
                 JsonValue::CreateNumberValue(static_cast<double>(g_filters.size())));
    return reply;
}

JsonObject HandleStatus() {
    std::lock_guard<std::mutex> lock(g_filterMutex);
    JsonObject reply = BaseReply(true);
    reply.Insert(L"state", JsonValue::CreateStringValue(
        g_filters.empty() ? L"ready" : L"applied"));
    reply.Insert(L"driver_loaded", JsonValue::CreateBooleanValue(true));
    reply.Insert(L"filters", JsonValue::CreateNumberValue(static_cast<double>(g_filters.size())));
    return reply;
}

std::string ProcessRequest(const std::string& raw) {
    try {
        JsonObject request = JsonObject::Parse(winrt::to_hstring(raw));
        if (request.GetNamedString(L"schema") != kProtocolSchema)
            throw std::runtime_error("routing service protocol mismatch");
        std::wstring command = request.GetNamedString(L"command").c_str();
        JsonObject reply;
        if (command == L"apply") reply = HandleApply(request);
        else if (command == L"restore") reply = HandleRestore(request);
        else if (command == L"status") reply = HandleStatus();
        else throw std::runtime_error("unsupported routing command");
        return winrt::to_string(reply.Stringify());
    } catch (const std::exception& error) {
        JsonObject reply = BaseReply(false);
        reply.Insert(L"error", JsonValue::CreateStringValue(winrt::to_hstring(error.what())));
        return winrt::to_string(reply.Stringify());
    }
}

bool ClientIsOwner(HANDLE pipe) {
    if (!ImpersonateNamedPipeClient(pipe)) return false;
    HANDLE token = nullptr;
    bool equal = false;
    if (OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &token)) {
        DWORD bytes = 0;
        GetTokenInformation(token, TokenUser, nullptr, 0, &bytes);
        std::vector<BYTE> buffer(bytes);
        if (bytes && GetTokenInformation(token, TokenUser, buffer.data(), bytes, &bytes)) {
            auto* user = reinterpret_cast<TOKEN_USER*>(buffer.data());
            PSID configured = nullptr;
            if (ConvertStringSidToSidW(g_ownerSid.c_str(), &configured)) {
                equal = EqualSid(user->User.Sid, configured) != FALSE;
                LocalFree(configured);
            }
        }
        CloseHandle(token);
    }
    RevertToSelf();
    return equal;
}

bool ReadExact(HANDLE pipe, void* data, DWORD length) {
    BYTE* cursor = static_cast<BYTE*>(data);
    DWORD done = 0;
    while (done < length) {
        OVERLAPPED ov{};
        ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!ov.hEvent) return false;
        DWORD chunk = 0;
        BOOL ok = ReadFile(pipe, cursor + done, length - done, &chunk, &ov);
        if (!ok && GetLastError() == ERROR_IO_PENDING) {
            HANDLE waits[2] = {g_stopEvent, ov.hEvent};
            DWORD wait = WaitForMultipleObjects(2, waits, FALSE, kIoTimeoutMs);
            if (wait != WAIT_OBJECT_0 + 1) {
                CancelIoEx(pipe, &ov);
                CloseHandle(ov.hEvent);
                return false;
            }
            ok = GetOverlappedResult(pipe, &ov, &chunk, FALSE);
        }
        CloseHandle(ov.hEvent);
        if (!ok || chunk == 0) return false;
        done += chunk;
    }
    return true;
}

bool WriteExact(HANDLE pipe, const void* data, DWORD length) {
    const BYTE* cursor = static_cast<const BYTE*>(data);
    DWORD done = 0;
    while (done < length) {
        OVERLAPPED ov{};
        ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!ov.hEvent) return false;
        DWORD chunk = 0;
        BOOL ok = WriteFile(pipe, cursor + done, length - done, &chunk, &ov);
        if (!ok && GetLastError() == ERROR_IO_PENDING) {
            HANDLE waits[2] = {g_stopEvent, ov.hEvent};
            DWORD wait = WaitForMultipleObjects(2, waits, FALSE, kIoTimeoutMs);
            if (wait != WAIT_OBJECT_0 + 1) {
                CancelIoEx(pipe, &ov);
                CloseHandle(ov.hEvent);
                return false;
            }
            ok = GetOverlappedResult(pipe, &ov, &chunk, FALSE);
        }
        CloseHandle(ov.hEvent);
        if (!ok || chunk == 0) return false;
        done += chunk;
    }
    return true;
}

void ServeClient(HANDLE pipe) {
    if (!ClientIsOwner(pipe)) return;
    uint32_t length = 0;
    if (!ReadExact(pipe, &length, sizeof(length)) || length == 0 || length > kMaxMessage) return;
    std::string raw(length, '\0');
    if (!ReadExact(pipe, raw.data(), length)) return;
    std::string reply = ProcessRequest(raw);
    if (reply.empty() || reply.size() > kMaxMessage) return;
    uint32_t replyLength = static_cast<uint32_t>(reply.size());
    if (!WriteExact(pipe, &replyLength, sizeof(replyLength))) return;
    WriteExact(pipe, reply.data(), replyLength);
}

SECURITY_ATTRIBUTES PipeSecurity(PSECURITY_DESCRIPTOR* descriptor) {
    std::wstring sddl = L"D:P(A;;GA;;;SY)(A;;GRGW;;;" + g_ownerSid + L")";
    *descriptor = nullptr;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(
            sddl.c_str(), SDDL_REVISION_1, descriptor, nullptr)) {
        throw Win32Error("could not build routing pipe ACL");
    }
    SECURITY_ATTRIBUTES attributes{};
    attributes.nLength = sizeof(attributes);
    attributes.lpSecurityDescriptor = *descriptor;
    attributes.bInheritHandle = FALSE;
    return attributes;
}

void PipeLoop() {
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    SECURITY_ATTRIBUTES security = PipeSecurity(&descriptor);
    while (WaitForSingleObject(g_stopEvent, 0) != WAIT_OBJECT_0) {
        HANDLE pipe = CreateNamedPipeW(
            kPipeName,
            PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
            1,
            static_cast<DWORD>(kMaxMessage + 4),
            static_cast<DWORD>(kMaxMessage + 4),
            0,
            &security);
        if (pipe == INVALID_HANDLE_VALUE) break;

        OVERLAPPED ov{};
        ov.hEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!ov.hEvent) {
            CloseHandle(pipe);
            break;
        }
        BOOL connected = ConnectNamedPipe(pipe, &ov);
        DWORD error = connected ? ERROR_SUCCESS : GetLastError();
        bool ready = connected != FALSE;
        if (!ready && error == ERROR_PIPE_CONNECTED) {
            ready = true;
            SetEvent(ov.hEvent);
        } else if (!ready && error == ERROR_IO_PENDING) {
            HANDLE waits[2] = {g_stopEvent, ov.hEvent};
            DWORD wait = WaitForMultipleObjects(2, waits, FALSE, INFINITE);
            ready = wait == WAIT_OBJECT_0 + 1;
        }
        if (ready && WaitForSingleObject(g_stopEvent, 0) != WAIT_OBJECT_0)
            ServeClient(pipe);

        CancelIoEx(pipe, nullptr);
        FlushFileBuffers(pipe);
        DisconnectNamedPipe(pipe);
        CloseHandle(ov.hEvent);
        CloseHandle(pipe);
    }
    if (descriptor) LocalFree(descriptor);
}

void WINAPI ServiceControl(DWORD control) {
    if (control == SERVICE_CONTROL_STOP || control == SERVICE_CONTROL_SHUTDOWN) {
        SetServiceState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        if (g_stopEvent) SetEvent(g_stopEvent);
    }
}

void WINAPI ServiceMain(DWORD, LPWSTR*) {
    g_statusHandle = RegisterServiceCtrlHandlerW(kServiceName, ServiceControl);
    if (!g_statusHandle) return;
    SetServiceState(SERVICE_START_PENDING, NO_ERROR, 10000);

    try {
        winrt::init_apartment(winrt::apartment_type::multi_threaded);
        g_stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!g_stopEvent) throw Win32Error("CreateEventW failed");
        g_ownerSid = ReadOwnerSid();
        if (!StartKernelDriver()) throw Win32Error("Arvectum routing driver could not be started");
        InitializeWfp();
        SetServiceState(SERVICE_RUNNING);
        PipeLoop();
        SetServiceState(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        CloseWfp();
        CloseHandle(g_stopEvent);
        g_stopEvent = nullptr;
        SetServiceState(SERVICE_STOPPED);
    } catch (...) {
        CloseWfp();
        if (g_stopEvent) {
            CloseHandle(g_stopEvent);
            g_stopEvent = nullptr;
        }
        SetServiceState(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR);
    }
}

void EnsureAdmin() {
    BOOL isMember = FALSE;
    SID_IDENTIFIER_AUTHORITY nt = SECURITY_NT_AUTHORITY;
    PSID admins = nullptr;
    if (!AllocateAndInitializeSid(&nt, 2, SECURITY_BUILTIN_DOMAIN_RID,
                                  DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &admins))
        throw Win32Error("AllocateAndInitializeSid failed");
    BOOL checked = CheckTokenMembership(nullptr, admins, &isMember);
    FreeSid(admins);
    if (!checked || !isMember)
        throw std::runtime_error("administrator elevation is required");
}

void StopAndDelete(SC_HANDLE scm, const wchar_t* name) {
    SC_HANDLE service = OpenServiceW(scm, name, SERVICE_STOP | SERVICE_QUERY_STATUS | DELETE);
    if (!service) {
        if (GetLastError() == ERROR_SERVICE_DOES_NOT_EXIST) return;
        throw Win32Error("OpenServiceW failed");
    }
    SERVICE_STATUS status{};
    ControlService(service, SERVICE_CONTROL_STOP, &status);
    for (int i = 0; i < 50; ++i) {
        SERVICE_STATUS_PROCESS process{};
        DWORD bytes = 0;
        if (!QueryServiceStatusEx(service, SC_STATUS_PROCESS_INFO,
                                  reinterpret_cast<BYTE*>(&process), sizeof(process), &bytes) ||
            process.dwCurrentState == SERVICE_STOPPED) break;
        Sleep(100);
    }
    if (!DeleteService(service) && GetLastError() != ERROR_SERVICE_MARKED_FOR_DELETE) {
        DWORD error = GetLastError();
        CloseServiceHandle(service);
        throw Win32Error("DeleteService failed", error);
    }
    CloseServiceHandle(service);
}

void Install(const std::wstring& ownerSid) {
    EnsureAdmin();
    const std::wstring canonicalSid = CanonicalSid(ownerSid);
    std::filesystem::path serviceBinary;
    std::filesystem::path driverBinary;
    CopyNativePayloadToProtectedDirectory(&serviceBinary, &driverBinary);

    WriteOwnerSid(canonicalSid);
    SC_HANDLE scm = OpenSCManagerW(
        nullptr, nullptr, SC_MANAGER_CREATE_SERVICE | SC_MANAGER_CONNECT);
    if (!scm) throw Win32Error("OpenSCManagerW failed");

    std::wstring driverPath = L"\"" + driverBinary.wstring() + L"\"";
    SC_HANDLE driver = nullptr;
    SC_HANDLE service = nullptr;
    try {
        driver = CreateOrUpdateService(
            scm,
            kDriverServiceName,
            L"Arvectum Proxy Routing Driver",
            SERVICE_KERNEL_DRIVER,
            SERVICE_DEMAND_START,
            driverPath);
        CloseServiceHandle(driver);
        driver = nullptr;

        std::wstring servicePath = L"\"" + serviceBinary.wstring() + L"\" --service";
        service = CreateOrUpdateService(
            scm,
            kServiceName,
            L"Arvectum Proxy Application Routing",
            SERVICE_WIN32_OWN_PROCESS,
            SERVICE_AUTO_START,
            servicePath);

        SERVICE_DESCRIPTIONW description{};
        description.lpDescription =
            const_cast<wchar_t*>(L"Arvectum-owned WFP service for per-application proxy exclusions.");
        ChangeServiceConfig2W(service, SERVICE_CONFIG_DESCRIPTION, &description);

        if (!StartServiceW(service, 0, nullptr) &&
            GetLastError() != ERROR_SERVICE_ALREADY_RUNNING) {
            throw Win32Error("StartServiceW failed");
        }
        CloseServiceHandle(service);
        CloseServiceHandle(scm);
    } catch (...) {
        if (service) CloseServiceHandle(service);
        if (driver) CloseServiceHandle(driver);
        CloseServiceHandle(scm);
        throw;
    }
}

void Uninstall() {
    EnsureAdmin();
    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    if (!scm) throw Win32Error("OpenSCManagerW failed");
    StopAndDelete(scm, kServiceName);
    StopAndDelete(scm, kDriverServiceName);
    CloseServiceHandle(scm);
    RegDeleteTreeW(HKEY_LOCAL_MACHINE, kRegistryKey);
    std::error_code ignored;
    std::filesystem::remove_all(ProtectedInstallDirectory(), ignored);
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc == 2 && std::wstring(argv[1]) == L"--service") {
            SERVICE_TABLE_ENTRYW table[] = {
                {const_cast<LPWSTR>(kServiceName), ServiceMain},
                {nullptr, nullptr},
            };
            if (!StartServiceCtrlDispatcherW(table)) throw Win32Error("StartServiceCtrlDispatcherW failed");
            return 0;
        }
        if (argc == 4 && std::wstring(argv[1]) == L"--install" &&
            std::wstring(argv[2]) == L"--owner-sid") {
            Install(argv[3]);
            return 0;
        }
        if (argc == 2 && std::wstring(argv[1]) == L"--uninstall") {
            Uninstall();
            return 0;
        }
        return 2;
    } catch (...) {
        return 1;
    }
}
