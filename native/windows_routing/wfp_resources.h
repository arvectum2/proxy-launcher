#pragma once
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <fwpmu.h>

namespace arvectum::routing {

inline constexpr wchar_t kProviderName[] =
    L"Arvectum.ProxyLauncher.WfpProvider";
inline constexpr wchar_t kSublayerName[] =
    L"Arvectum.ProxyLauncher.WfpSublayer";
inline constexpr wchar_t kCalloutV4Name[] =
    L"Arvectum.ProxyLauncher.ConnectRedirectV4";
inline constexpr wchar_t kCalloutV6Name[] =
    L"Arvectum.ProxyLauncher.ConnectRedirectV6";

extern const GUID kProviderKey;
extern const GUID kSublayerKey;
extern const GUID kCalloutV4Key;
extern const GUID kCalloutV6Key;

enum class RedirectDecision : unsigned long {
    kRedirect = 1,
    kBypass = 2,
};

struct FilterDescriptor {
    const wchar_t* rule_id;
    RedirectDecision decision;
    const unsigned char* app_id;
    unsigned long app_id_size;
    UINT16 family;
    const wchar_t* cidr;
};

bool IsArvectumResourceName(const wchar_t* value) noexcept;
DWORD OpenWfpEngine(HANDLE* engine) noexcept;

}  // namespace arvectum::routing
