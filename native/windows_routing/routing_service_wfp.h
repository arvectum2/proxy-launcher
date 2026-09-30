#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <string>
#include <vector>

#include "routing_service_protocol.h"

namespace arvectum::routing {

class RoutingWfpSession {
public:
    RoutingWfpSession() noexcept;
    ~RoutingWfpSession();

    RoutingWfpSession(const RoutingWfpSession&) = delete;
    RoutingWfpSession& operator=(const RoutingWfpSession&) = delete;

    bool Apply(
        const ServiceRequest& request,
        PSID caller_sid,
        std::string* error) noexcept;
    bool RestoreForCaller(
        PSID caller_sid,
        bool* resources_verified,
        std::string* error) noexcept;
    bool Restore(bool* resources_verified, std::string* error) noexcept;
    HANDLE ProxyProcessHandle() const noexcept;

private:
    void* engine_;
    HANDLE proxy_process_;
    std::vector<unsigned char> owner_sid_;
};

}  // namespace arvectum::routing
