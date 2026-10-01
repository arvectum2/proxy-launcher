#pragma once

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

#include "windivert_service_protocol.h"

namespace arvectum::windivert {

class RoutingSession {
public:
    RoutingSession() = default;
    ~RoutingSession();

    RoutingSession(const RoutingSession&) = delete;
    RoutingSession& operator=(const RoutingSession&) = delete;

    bool Apply(
        const ServiceRequest& request,
        PSID caller_sid,
        std::string* error);

    bool RestoreForCaller(
        const ServiceRequest& request,
        PSID caller_sid,
        bool* resources_verified,
        std::string* error);

    bool Restore(
        bool* resources_verified,
        std::string* error);

    HANDLE ProxyProcessHandle() const noexcept;

private:
    bool StopLocked(
        bool* resources_verified,
        std::string* error) noexcept;

    void SocketLoop() noexcept;
    void NetworkLoop() noexcept;
    bool ProcessPathMatches(std::uint32_t pid) const noexcept;
    bool IsSelectedPort(bool ipv6, std::uint16_t port) const noexcept;
    void AddSelectedPort(bool ipv6, std::uint16_t port);
    void RemoveSelectedPort(bool ipv6, std::uint16_t port);

    mutable std::mutex state_mutex_;
    mutable std::mutex ports_mutex_;
    std::atomic<bool> stop_{false};
    HANDLE socket_handle_ = INVALID_HANDLE_VALUE;
    HANDLE network_handle_ = INVALID_HANDLE_VALUE;
    HANDLE proxy_process_ = nullptr;
    std::thread socket_thread_;
    std::thread network_thread_;
    std::unordered_set<std::string> application_hashes_;
    std::unordered_set<std::uint32_t> selected_ports_;
    std::vector<unsigned char> caller_sid_;
    std::string session_id_;
    std::string plan_digest_;
    std::uint16_t proxy_port_ = 0;
    std::uint16_t direct_port_ = 0;
};

}  // namespace arvectum::windivert

