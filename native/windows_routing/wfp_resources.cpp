#include "wfp_resources.h"

#include <cwchar>

namespace arvectum::routing {

const GUID kProviderKey =
    {0x7f8764a3, 0x5f75, 0x4c43, {0xa8, 0x82, 0x52, 0x15, 0x53, 0x63, 0xb9, 0x31}};
const GUID kSublayerKey =
    {0xb86b9a90, 0x7462, 0x4a26, {0xb1, 0xa6, 0x7f, 0x24, 0x83, 0x27, 0x61, 0xa5}};
const GUID kCalloutV4Key =
    {0x83751a2f, 0x2b83, 0x49cc, {0x8d, 0xc1, 0x50, 0xcf, 0xe1, 0xf5, 0x0b, 0x0b}};
const GUID kCalloutV6Key =
    {0x6c08d7a8, 0x5afd, 0x4012, {0x9d, 0x17, 0x2d, 0xb3, 0xd1, 0xf0, 0xb1, 0x7d}};

bool IsArvectumResourceName(const wchar_t* value) noexcept {
    if (value == nullptr) {
        return false;
    }
    constexpr wchar_t prefix[] = L"Arvectum.ProxyLauncher.";
    return std::wcsncmp(value, prefix, (sizeof(prefix) / sizeof(prefix[0])) - 1) == 0;
}

DWORD OpenWfpEngine(HANDLE* engine) noexcept {
    if (engine == nullptr) {
        return ERROR_INVALID_PARAMETER;
    }
    *engine = nullptr;
    return FwpmEngineOpen0(
        nullptr,
        RPC_C_AUTHN_WINNT,
        nullptr,
        nullptr,
        engine);
}

}  // namespace arvectum::routing
