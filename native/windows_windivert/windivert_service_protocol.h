#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace arvectum::windivert {

inline constexpr std::uint32_t kProtocolVersion = 1;
inline constexpr std::size_t kMaxApplications = 128;

enum class ServiceCommand {
    kApplyPlan,
    kRestore,
};

struct ApplicationSpec {
    std::string rule_id;
    std::string application_path_sha256;
    std::uint16_t local_proxy_port = 0;
};

struct ServiceRequest {
    ServiceCommand command = ServiceCommand::kRestore;
    std::string session_id;
    std::string plan_digest;
    std::uint32_t proxy_pid = 0;
    std::uint16_t direct_listener_port = 0;
    std::vector<ApplicationSpec> applications;
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

}  // namespace arvectum::windivert
