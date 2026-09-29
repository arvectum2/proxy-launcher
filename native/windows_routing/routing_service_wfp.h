#pragma once

#include <string>

#include "routing_service_protocol.h"

namespace arvectum::routing {

class RoutingWfpSession {
public:
    RoutingWfpSession() noexcept;
    ~RoutingWfpSession();

    RoutingWfpSession(const RoutingWfpSession&) = delete;
    RoutingWfpSession& operator=(const RoutingWfpSession&) = delete;

    bool Apply(const ServiceRequest& request, std::string* error) noexcept;
    bool Restore(bool* resources_verified, std::string* error) noexcept;

private:
    void* engine_;
};

}  // namespace arvectum::routing
