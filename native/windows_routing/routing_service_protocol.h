#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace arvectum::routing {

inline constexpr std::uint32_t kServiceProtocolVersion = 2;
inline constexpr std::size_t kServiceMaxFilters = 512;

enum class ServiceCommand {
    kApplyPlan,
    kRestore,
};

enum class ServiceFilterOperation {
    kRedirect,
    kBypass,
};

enum class ServiceDestinationKind {
    kAll,
    kCidr,
};

struct ServiceFilterSpec {
    std::string rule_id;
    ServiceFilterOperation operation;
    std::vector<unsigned char> application_id;
    ServiceDestinationKind destination_kind;
    std::string destination_value;
    std::vector<unsigned short> address_families;
};

struct ServiceRequest {
    ServiceCommand command;
    std::string session_id;
    std::string plan_digest;
    std::uint32_t proxy_pid = 0;
    std::uint16_t proxy_port = 0;
    std::vector<ServiceFilterSpec> filters;
};

bool ParseServiceRequest(
    const unsigned char* data,
    std::size_t size,
    ServiceRequest* request,
    std::string* error) noexcept;

std::string BuildServiceResponse(
    const ServiceRequest& request,
    bool ok,
    const char* error,
    bool restore,
    bool resources_verified);

}  // namespace arvectum::routing
